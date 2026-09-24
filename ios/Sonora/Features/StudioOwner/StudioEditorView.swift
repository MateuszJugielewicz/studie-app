import SwiftUI
import PhotosUI
import MapKit

/// Create or edit a studio listing. Used for the application and for later edits.
struct StudioEditorView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State var studio: Studio
    var isApplication: Bool
    var onSaved: (Studio) -> Void = { _ in }

    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        Form {
            if isApplication {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("List your studio").font(.title2.bold())
                        Text("Fill in each section. When you're ready, submit your studio for review – our team usually replies within 1–2 business days.")
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }
            }

            Section("Your listing") {
                editorLink("Basics & photos", "photo.on.rectangle", done: !studio.name.isEmpty && !studio.photoUrls.isEmpty && studio.description.count >= 40) {
                    StudioBasicsEditor(studio: $studio)
                }
                editorLink("Address & contact", "mappin.and.ellipse", done: !studio.address.city.isEmpty && studio.latitude != 0) {
                    StudioLocationEditor(studio: $studio)
                }
                editorLink("Prices & services", "eurosign.circle", done: !studio.sessionTypes.isEmpty) {
                    StudioPricingEditor(studio: $studio)
                }
                editorLink("Opening hours", "clock", done: !studio.openingHours.allSatisfy(\.isClosed)) {
                    OpeningHoursEditor(hours: $studio.openingHours)
                }
                editorLink("Facilities, gear & genres", "slider.vertical.3", done: !studio.genres.isEmpty && !studio.facilities.isEmpty) {
                    StudioFeaturesEditor(studio: $studio)
                }
                editorLink("Rules & booking terms", "list.bullet.clipboard", done: true) {
                    StudioPolicyEditor(studio: $studio)
                }
                editorLink("Payout details", "building.columns", done: true) {
                    PayoutAccountEditor(studioId: studio.id)
                }
            }

            let problems = StudioValidator.problems(in: studio)
            if isApplication && !problems.isEmpty {
                Section("Still missing") {
                    ForEach(problems, id: \.self) { Label($0, systemImage: "exclamationmark.circle").foregroundStyle(Theme.warning).font(.footnote) }
                }
            }
        }
        .navigationTitle(isApplication ? "Studio application" : "Edit studio")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save") { save() }.disabled(isSaving)
            }
        }
        .errorAlert($error)
    }

    private func editorLink<Destination: View>(_ title: String, _ symbol: String, done: Bool, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? Theme.positive : Color.secondary)
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let saved = try await app.backend.saveStudio(studio)
                studio = saved
                app.ownedStudio = saved
                onSaved(saved)
                if !isApplication { dismiss() }
            } catch {
                self.error = error.userMessage
                // If the application was stored after all, show it instead of this unsaved draft.
                if isApplication, let existing = try? await app.backend.ownedStudio() { app.ownedStudio = existing }
            }
        }
    }
}

struct StudioBasicsEditor: View {
    @Environment(AppState.self) private var app
    @Binding var studio: Studio
    @State private var items: [PhotosPickerItem] = []
    @State private var isUploading = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Name") {
                TextField("Studio name", text: $studio.name)
                TextField("Tagline, e.g. “Warm analog vocals in Exarchia”", text: $studio.tagline)
            }
            Section {
                TextField("Describe the rooms, the vibe, who you work with…", text: $studio.description, axis: .vertical).lineLimit(5...15)
            } header: {
                Text("Description")
            } footer: {
                Text("\(studio.description.count) characters (min. 40)")
            }
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(studio.photoUrls, id: \.self) { url in
                            RemoteImage(url: url)
                                .frame(width: 120, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(alignment: .topTrailing) {
                                    Button { studio.photoUrls.removeAll { $0 == url } } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .padding(4)
                                }
                        }
                        PhotosPicker(selection: $items, maxSelectionCount: 10, matching: .images) {
                            VStack {
                                Image(systemName: isUploading ? "hourglass" : "plus")
                                Text("Add").font(.caption)
                            }
                            .frame(width: 120, height: 90)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                TextField("Video link (YouTube, Vimeo…)", text: Binding(get: { studio.videoUrl ?? "" }, set: { studio.videoUrl = $0.isEmpty ? nil : $0 }))
                    .keyboardType(.URL).textInputAutocapitalization(.never)
            } header: {
                Text("Photos & video")
            } footer: {
                Text("The first photo is your cover. Show the live room, control room and booth.")
            }
        }
        .navigationTitle("Basics & photos")
        .onChange(of: items) { _, newItems in upload(newItems) }
        .errorAlert($error)
    }

    private func upload(_ newItems: [PhotosPickerItem]) {
        guard !newItems.isEmpty else { return }
        isUploading = true
        Task {
            defer { isUploading = false; items = [] }
            for item in newItems {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let jpeg = ImageCompressor.jpeg(from: data, maxDimension: 1600) else { continue }
                    let url = try await app.backend.uploadImage(jpeg, folder: "studios/\(studio.id.uuidString)")
                    studio.photoUrls.append(url)
                } catch { self.error = error.userMessage }
            }
        }
    }
}

struct StudioLocationEditor: View {
    @Binding var studio: Studio
    @State private var isLocating = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                TextField("Street and number", text: $studio.address.street)
                TextField("Postal code", text: $studio.address.postalCode)
                TextField("City", text: $studio.address.city)
                TextField("Area / neighbourhood", text: $studio.address.area)
                TextField("Country", text: $studio.address.country)
            } header: {
                Text("Address")
            } footer: {
                Text("Artists see the area before booking and the full address after booking.")
            }
            Section {
                Button {
                    locate()
                } label: {
                    Label(isLocating ? "Finding…" : "Find on map", systemImage: "location.magnifyingglass")
                }
                .disabled(isLocating || studio.address.city.isEmpty)
                if studio.latitude != 0 || studio.longitude != 0 {
                    Map(position: .constant(.region(MKCoordinateRegion(center: studio.coordinate, latitudinalMeters: 800, longitudinalMeters: 800)))) {
                        Marker(studio.name.isEmpty ? "Studio" : studio.name, coordinate: studio.coordinate)
                    }
                    .frame(height: 180)
                    .listRowInsets(EdgeInsets())
                }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
            Section("Contact") {
                TextField("Phone", text: $studio.contact.phone).keyboardType(.phonePad)
                TextField("Email", text: $studio.contact.email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                TextField("Website", text: $studio.contact.website).keyboardType(.URL).textInputAutocapitalization(.never)
            }
        }
        .navigationTitle("Address & contact")
    }

    private func locate() {
        isLocating = true
        Task {
            defer { isLocating = false }
            if let coordinate = try? await LocationService.geocode(studio.address.singleLine) {
                studio.latitude = coordinate.latitude
                studio.longitude = coordinate.longitude
                message = nil
            } else {
                message = "We couldn't find that address. Check the spelling."
            }
        }
    }
}

struct StudioPricingEditor: View {
    @Binding var studio: Studio

    var body: some View {
        Form {
            Section {
                Picker("Currency", selection: $studio.currency) {
                    ForEach(["EUR", "DKK", "SEK", "NOK", "GBP", "USD"], id: \.self) { Text($0) }
                }
            }
            Section {
                ForEach($studio.sessionTypes) { $type in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Session name", text: $type.name).font(.headline)
                        TextField("Short description", text: $type.details)
                        MoneyField(title: "Per hour", amount: $type.hourlyRate, currency: studio.currency)
                        Stepper("Minimum \(type.minimumHours) h", value: $type.minimumHours, in: 1...8)
                        Toggle("Engineer included", isOn: $type.includesEngineer)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { studio.sessionTypes.remove(atOffsets: $0) }
                Button("Add session type", systemImage: "plus") {
                    studio.sessionTypes.append(SessionType(id: UUID().uuidString.lowercased(), name: "", details: "", hourlyRate: studio.priceFrom > 0 ? studio.priceFrom : 3000, minimumHours: 1, includesEngineer: false))
                }
            } header: {
                Text("Session types")
            } footer: {
                Text("e.g. Recording, Recording + engineer, Mixing session, Podcast, Rehearsal.")
            }
            Section {
                ForEach($studio.addOns) { $addOn in
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Type", selection: $addOn.kind) {
                            ForEach(AddOnKind.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        TextField("Name", text: $addOn.name)
                        MoneyField(title: "Price", amount: $addOn.price, currency: studio.currency)
                        Picker("Charged", selection: $addOn.unit) {
                            ForEach(PriceUnit.allCases, id: \.self) { Text($0.suffix).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { studio.addOns.remove(atOffsets: $0) }
                Button("Add service", systemImage: "plus") {
                    studio.addOns.append(ServiceAddOn(id: UUID().uuidString.lowercased(), kind: .mixing, name: "Mixing", price: 5000, unit: .perTrack))
                }
            } header: {
                Text("Mix, mastering, engineer & producer")
            }
        }
        .navigationTitle("Prices & services")
    }
}

struct MoneyField: View {
    let title: String
    @Binding var amount: Int
    let currency: String
    @State private var text = ""

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                .onChange(of: text) { _, value in if let parsed = Money.parse(value) { amount = parsed } }
            Text(currency).foregroundStyle(.secondary)
        }
        .onAppear { text = Money.editableString(amount) }
    }
}

struct OpeningHoursEditor: View {
    @Binding var hours: [OpeningHours]

    var body: some View {
        Form {
            ForEach(OpeningHours.displayOrder, id: \.self) { weekday in
                if let index = hours.firstIndex(where: { $0.weekday == weekday }) {
                    Section(hours[index].weekdayName) {
                        Toggle("Open", isOn: Binding(get: { !hours[index].isClosed }, set: { hours[index].isClosed = !$0 }))
                        if !hours[index].isClosed {
                            MinutePicker(title: "Opens", minutes: $hours[index].opensAt, range: 0...(23 * 60 + 30))
                            MinutePicker(title: "Closes", minutes: $hours[index].closesAt, range: 60...(30 * 60))
                        }
                    }
                }
            }
            Section {
                Button("Copy Monday to all days") {
                    guard let monday = hours.first(where: { $0.weekday == 2 }) else { return }
                    for index in hours.indices {
                        hours[index].isClosed = monday.isClosed
                        hours[index].opensAt = monday.opensAt
                        hours[index].closesAt = monday.closesAt
                    }
                }
            } footer: {
                Text("Closing times after midnight (e.g. 02:00) are allowed for late sessions.")
            }
        }
        .navigationTitle("Opening hours")
        .onAppear {
            for weekday in 1...7 where !hours.contains(where: { $0.weekday == weekday }) {
                hours.append(OpeningHours(weekday: weekday, isClosed: true, opensAt: 600, closesAt: 1320))
            }
        }
    }
}

struct MinutePicker: View {
    let title: String
    @Binding var minutes: Int
    let range: ClosedRange<Int>

    var body: some View {
        Picker(title, selection: $minutes) {
            ForEach(Array(stride(from: range.lowerBound, through: range.upperBound, by: 30)), id: \.self) { value in
                Text(OpeningHours.format(value) + (value >= 24 * 60 ? " (+1)" : "")).tag(value)
            }
        }
    }
}

struct StudioFeaturesEditor: View {
    @Binding var studio: Studio
    @State private var facilities: Set<Facility> = []
    @State private var genres: Set<Genre> = []
    @State private var newCategory: EquipmentCategory = .microphone
    @State private var newItem = ""

    var body: some View {
        Form {
            Section("Capacity") {
                Stepper("Up to \(studio.capacity) people", value: $studio.capacity, in: 1...60)
            }
            Section("Facilities") {
                ChipPicker(items: Facility.allCases, selection: $facilities, title: { $0.title }, symbol: { $0.symbol }).padding(.vertical, 4)
            }
            Section("Genres you work with") {
                ChipPicker(items: Genre.allCases, selection: $genres, title: { $0.title }).padding(.vertical, 4)
            }
            Section {
                ForEach(EquipmentCategory.allCases) { category in
                    let items = studio.equipment.filter { $0.category == category }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.title).font(.caption.bold()).foregroundStyle(.secondary)
                            ForEach(items) { item in
                                HStack {
                                    Text(item.name)
                                    Spacer()
                                    Button { studio.equipment.removeAll { $0.id == item.id } } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                Picker("Category", selection: $newCategory) {
                    ForEach(EquipmentCategory.allCases) { Text($0.title).tag($0) }
                }
                HStack {
                    TextField("e.g. Neumann U87 Ai", text: $newItem)
                    Button("Add") {
                        studio.equipment.append(EquipmentItem(id: UUID().uuidString.lowercased(), category: newCategory, name: newItem.trimmingCharacters(in: .whitespaces)))
                        newItem = ""
                    }
                    .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Equipment & microphones")
            }
            Section {
                ForEach($studio.engineers) { $person in
                    VStack(alignment: .leading) {
                        TextField("Name", text: $person.name).font(.headline)
                        TextField("Role (Engineer, Producer…)", text: $person.role)
                        TextField("Short bio", text: $person.bio)
                    }
                }
                .onDelete { studio.engineers.remove(atOffsets: $0) }
                Button("Add person", systemImage: "person.badge.plus") {
                    studio.engineers.append(StudioPerson(id: UUID().uuidString.lowercased(), name: "", role: "Engineer", bio: ""))
                }
            } header: {
                Text("Engineers & producers")
            }
        }
        .navigationTitle("Facilities & gear")
        .onAppear {
            facilities = Set(studio.facilities)
            genres = Set(studio.genres)
        }
        .onChange(of: facilities) { _, value in studio.facilities = Facility.allCases.filter(value.contains) }
        .onChange(of: genres) { _, value in studio.genres = Genre.allCases.filter(value.contains) }
    }
}

struct StudioPolicyEditor: View {
    @Binding var studio: Studio
    @State private var newRule = ""

    var body: some View {
        Form {
            Section {
                ForEach(studio.rules, id: \.self) { Text($0) }
                    .onDelete { studio.rules.remove(atOffsets: $0) }
                HStack {
                    TextField("Add a rule", text: $newRule)
                    Button("Add") {
                        studio.rules.append(newRule.trimmingCharacters(in: .whitespaces))
                        newRule = ""
                    }
                    .disabled(newRule.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("House rules")
            }
            Section {
                Toggle("Instant booking", isOn: $studio.bookingPolicy.instantBook)
            } footer: {
                Text(studio.bookingPolicy.instantBook
                     ? "Artists are confirmed immediately when they pay."
                     : "You accept or decline each request. The artist's card is authorised and only charged when you accept.")
            }
            Section {
                Picker("Cancellation policy", selection: $studio.bookingPolicy.cancellationPolicy) {
                    ForEach(CancellationPolicy.allCases) { Text($0.title).tag($0) }
                }
                Text(studio.bookingPolicy.cancellationPolicy.summary).font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Picker("Deposit", selection: $studio.bookingPolicy.depositPercent) {
                    Text("No deposit – full payment").tag(0)
                    ForEach([20, 30, 50], id: \.self) { Text("\($0)% deposit").tag($0) }
                }
            } footer: {
                Text("With a deposit, the rest is charged automatically after the session.")
            }
            Section {
                Toggle("Accept cash payments", isOn: $studio.bookingPolicy.acceptsCash)
                    .disabled(studio.bookingPolicy.depositPercent > 0)
            } footer: {
                Text(studio.bookingPolicy.depositPercent > 0
                     ? "Cash isn't available when you require a deposit."
                     : "Artists can choose to pay you in cash at the session. EasySesh's \(PlatformConfig.platformFeePercent)% platform fee on cash bookings is deducted from your next payout or invoiced monthly. Cash bookings have no card guarantee for no-shows.")
            }
            Section("Scheduling") {
                Stepper("Min. notice: \(studio.bookingPolicy.minimumNoticeHours) h", value: $studio.bookingPolicy.minimumNoticeHours, in: 0...72)
                Stepper("Book up to \(studio.bookingPolicy.maxAdvanceDays) days ahead", value: $studio.bookingPolicy.maxAdvanceDays, in: 7...365, step: 7)
                Stepper("Buffer between sessions: \(studio.bookingPolicy.bufferMinutes) min", value: $studio.bookingPolicy.bufferMinutes, in: 0...120, step: 15)
            }
            Section("Booking terms") {
                TextField("Overtime, damage, guests, recording rights…", text: $studio.bookingPolicy.terms, axis: .vertical).lineLimit(3...10)
            }
        }
        .navigationTitle("Rules & terms")
    }
}

struct PayoutAccountEditor: View {
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL
    let studioId: UUID
    @State private var account: PayoutAccount?
    @State private var holder = ""
    @State private var saved = false
    @State private var isOpeningStripe = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                if let account, account.payoutsEnabled {
                    Label(account.ibanLast4.isEmpty ? "Payouts enabled" : "Payouts enabled to •••• \(account.ibanLast4)", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Theme.positive)
                } else {
                    Label("Payouts not set up yet", systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warning)
                }
                TextField("Account holder / company name", text: $holder)
            } footer: {
                Text("Payouts are sent \(PlatformConfig.payoutDelayDays) days after each completed session, minus EasySesh's \(PlatformConfig.platformFeePercent)% platform fee. Platform fees for cash bookings are deducted from the same payouts.")
            }
            Section {
                Button(saved ? "Saved" : "Save") { save() }
                    .disabled(holder.isEmpty)
            }
            Section {
                Button {
                    openStripe()
                } label: {
                    Label(isOpeningStripe ? "Opening…" : (account?.payoutsEnabled == true ? "Update bank details" : "Connect bank account"), systemImage: "building.columns")
                }
                .disabled(isOpeningStripe)
            } footer: {
                Text("Bank details and identity checks are handled securely by Stripe, our payment provider.")
            }
        }
        .navigationTitle("Payout details")
        .task { await load() }
        .refreshable { await load() }
        .errorAlert($error)
    }

    private func load() async {
        account = try? await app.backend.payoutAccount(studioId: studioId)
        if holder.isEmpty { holder = account?.accountHolder ?? "" }
    }

    private func save() {
        Task {
            do {
                var updated = account ?? PayoutAccount(studioId: studioId, accountHolder: holder, ibanLast4: "", stripeAccountId: nil, payoutsEnabled: false)
                updated.accountHolder = holder
                account = try await app.backend.savePayoutAccount(updated, iban: nil)
                saved = true
            } catch { self.error = error.userMessage }
        }
    }

    private func openStripe() {
        isOpeningStripe = true
        Task {
            defer { isOpeningStripe = false }
            do {
                if let url = try await app.backend.payoutOnboardingURL(studioId: studioId) { openURL(url) }
            } catch { self.error = error.userMessage }
        }
    }
}
