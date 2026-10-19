import SwiftUI
import EventKit

@MainActor
@Observable
final class BookingDraft {
    let studio: Studio
    var sessionTypeId: String
    var hours: Int
    var day: Date
    var selectedSlot: TimeSlot?
    var addOns: [String: Int] = [:]
    var notes = ""

    var busy: [DateInterval] = []
    var isLoadingSlots = false
    var offers: [StudioOffer] = []
    /// The server's price for `quoteKey` (offers applied); the local quote is shown until it arrives.
    private var serverQuote: (key: String, price: PriceBreakdown)?

    private let engine = AvailabilityEngine()

    init(studio: Studio) {
        self.studio = studio
        let first = studio.sessionTypes.first
        sessionTypeId = first?.id ?? ""
        hours = first?.minimumHours ?? 2
        day = Date.now.startOfDay
    }

    var sessionType: SessionType? { studio.sessionType(id: sessionTypeId) }

    var slots: [TimeSlot] { engine.availableSlots(for: studio, on: day, hours: hours, busy: busy) }

    var quote: PriceBreakdown? {
        if let serverQuote, serverQuote.key == quoteKey { return serverQuote.price }
        return sessionType.map { PricingEngine.quote(studio: studio, sessionType: $0, hours: hours, addOns: addOns) }
    }

    var quoteKey: String {
        "\(sessionTypeId)|\(hours)|" + addOns.filter { $0.value > 0 }.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    func refreshQuote(_ backend: Backend) async {
        let key = quoteKey
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled, let price = try? await backend.quoteBooking(studio: studio, sessionTypeId: sessionTypeId, hours: hours, addOns: addOns, promoCode: nil) else { return }
        serverQuote = (key, price)
    }

    var request: BookingRequest? {
        guard let sessionType, let slot = selectedSlot else { return nil }
        return BookingRequest(studio: studio, sessionType: sessionType, startsAt: slot.start, hours: hours, addOns: addOns, notes: notes)
    }

    func loadBusy(_ backend: Backend) async {
        isLoadingSlots = true
        defer { isLoadingSlots = false }
        let start = day.startOfDay.adding(days: -1)
        busy = (try? await backend.busyIntervals(studioIds: [studio.id], from: start, to: start.adding(days: 3)))?[studio.id] ?? []
        if let selected = selectedSlot, !slots.contains(selected) { selectedSlot = nil }
    }
}

struct BookingFlowView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft: BookingDraft
    @State private var goToCheckout = false

    init(studio: Studio) {
        _draft = State(initialValue: BookingDraft(studio: studio))
    }

    var body: some View {
        NavigationStack {
            Form {
                StudioOffersSection(studio: draft.studio, offers: draft.offers)

                Section("Session type") {
                    Picker("Session type", selection: $draft.sessionTypeId) {
                        ForEach(draft.studio.sessionTypes) { type in
                            Text("\(type.name) · \(Money.format(type.hourlyRate, currency: draft.studio.currency))/h").tag(type.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Duration") {
                    Stepper(value: $draft.hours, in: (draft.sessionType?.minimumHours ?? 1)...PlatformConfig.maxSessionHours) {
                        Text("\(draft.hours) hours").bold()
                    }
                }

                Section("Date") {
                    DatePicker("Date", selection: $draft.day, in: Date.now.startOfDay...Date.now.adding(days: draft.studio.bookingPolicy.maxAdvanceDays), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }

                Section {
                    if draft.isLoadingSlots {
                        ProgressView()
                    } else if draft.slots.isEmpty {
                        Text(AvailabilityEngine().openingWindow(for: draft.studio, on: draft.day) == nil ? L10n.tr("The studio is closed this day.") : L10n.format("No free %lld-hour slots this day. Try fewer hours or another date.", draft.hours))
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84))], spacing: 8) {
                            ForEach(draft.slots) { slot in
                                Button {
                                    draft.selectedSlot = slot
                                } label: {
                                    Text(slot.start.formatted(date: .omitted, time: .shortened))
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(draft.selectedSlot == slot ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.card), in: RoundedRectangle(cornerRadius: 10))
                                        .foregroundStyle(draft.selectedSlot == slot ? Theme.onAccent : Color.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Start time")
                } footer: {
                    if let slot = draft.selectedSlot {
                        Text("\(slot.start.formatted(date: .complete, time: .shortened)) – \(slot.end.formatted(date: .omitted, time: .shortened))")
                    }
                }

                if !draft.studio.addOns.isEmpty {
                    Section("Add-ons") {
                        ForEach(draft.studio.addOns) { addOn in
                            AddOnRow(addOn: addOn, currency: draft.studio.currency, quantity: Binding(
                                get: { draft.addOns[addOn.id] ?? 0 },
                                set: { draft.addOns[addOn.id] = $0 }
                            ))
                        }
                    }
                }

                Section("Notes for the studio") {
                    TextField("What are you working on? Anything they should prepare?", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let quote = draft.quote {
                    Section("Price") {
                        PriceBreakdownView(price: quote)
                    }
                }
            }
            .easyseshGrouped()
            .task(id: draft.quoteKey) { await draft.refreshQuote(app.backend) }
            .task { draft.offers = (try? await app.backend.studioOffers(studioId: draft.studio.id)) ?? [] }
            .navigationTitle(draft.studio.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    goToCheckout = true
                } label: {
                    Text(draft.selectedSlot == nil ? L10n.tr("Pick a time") : L10n.format("Continue · %@", Money.format(draft.quote?.total ?? 0, currency: draft.studio.currency)))
                }
                .buttonStyle(.primary)
                .disabled(draft.request == nil)
                .padding()
                .background(.ultraThinMaterial)
            }
            .navigationDestination(isPresented: $goToCheckout) {
                if let request = draft.request {
                    CheckoutView(request: request, onFinish: { dismiss() })
                }
            }
            .task(id: draft.day) { await draft.loadBusy(app.backend) }
            .onChange(of: draft.sessionTypeId) {
                if let minimum = draft.sessionType?.minimumHours, draft.hours < minimum { draft.hours = minimum }
            }
            .onChange(of: draft.hours) {
                if let selected = draft.selectedSlot, !draft.slots.contains(where: { $0.start == selected.start }) {
                    draft.selectedSlot = nil
                } else if let selected = draft.selectedSlot {
                    draft.selectedSlot = draft.slots.first { $0.start == selected.start }
                }
            }
        }
    }
}

struct AddOnRow: View {
    let addOn: ServiceAddOn
    let currency: String
    @Binding var quantity: Int

    var body: some View {
        VStack(alignment: .leading) {
            if addOn.unit == .perTrack {
                Stepper(value: $quantity, in: 0...20) {
                    label
                    if quantity > 0 { Text(quantity == 1 ? L10n.tr("1 track") : L10n.format("%lld tracks", quantity)).font(.caption).foregroundStyle(Theme.accent) }
                }
            } else {
                Toggle(isOn: Binding(get: { quantity > 0 }, set: { quantity = $0 ? 1 : 0 })) { label }
            }
        }
    }

    private var label: some View {
        VStack(alignment: .leading) {
            Text(addOn.name)
            Text("\(Money.format(addOn.price, currency: currency)) \(addOn.unit.suffix)").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct PriceBreakdownView: View {
    let price: PriceBreakdown

    var body: some View {
        VStack(spacing: 8) {
            PriceRow(title: "\(Money.format(price.hourlyRate, currency: price.currency)) × \(price.hours) h", amount: price.sessionAmount, currency: price.currency)
            if price.addOnsAmount > 0 {
                PriceRow(title: "Add-ons", amount: price.addOnsAmount, currency: price.currency)
            }
            ForEach(Array((price.discounts ?? []).enumerated()), id: \.offset) { _, discount in
                HStack {
                    Label(discount.kind == "offer" ? "\(discount.label) (−\(discount.percent)%)" : L10n.format("Code %@", discount.label) + " (−\(discount.percent)%)", systemImage: "tag")
                    Spacer()
                    Text("−" + Money.format(discount.amount, currency: price.currency))
                }
                .foregroundStyle(Theme.positive)
            }
            if price.serviceFee > 0 {
                PriceRow(title: "Service fee", amount: price.serviceFee, currency: price.currency)
            }
            Divider()
            PriceRow(title: "Total", amount: price.total, currency: price.currency, emphasized: true)
            if price.depositAmount > 0 {
                PriceRow(title: price.serviceFee > 0 ? "Due now (deposit + fee)" : "Due now (deposit)", amount: price.dueNow, currency: price.currency)
                PriceRow(title: "Charged after the session", amount: price.dueLater, currency: price.currency)
            }
        }
    }
}

// MARK: - Checkout

struct CheckoutView: View {
    @Environment(AppState.self) private var app
    let request: BookingRequest
    let onFinish: () -> Void

    @State private var method: PaymentMethod = .applePay
    @State private var payWithCash = false
    @State private var agreed = false
    @State private var isPaying = false
    @State private var confirmed: Booking?
    @State private var error: String?
    @State private var codeInput = ""
    @State private var promo: PromoCheck?
    @State private var isCheckingCode = false
    @State private var serverPrice: PriceBreakdown?

    /// Card/Apple Pay needs Stripe keys; cash needs a studio that accepts it.
    private var cardAvailable: Bool { AppConfig.stripePublishableKey != nil }
    private var cashAvailable: Bool { PricingEngine.acceptsCash(request.studio) }

    private var payButtonTitle: LocalizedStringKey {
        let amount = Money.format(price.dueNow, currency: price.currency)
        switch (payWithCash, request.studio.bookingPolicy.instantBook) {
        case (true, true): return "Book · pay cash at the studio"
        case (true, false): return "Request to book · pay cash"
        case (false, true): return "Pay \(amount)"
        case (false, false): return "Request to book · \(amount)"
        }
    }

    private var price: PriceBreakdown {
        serverPrice ?? PricingEngine.quote(studio: request.studio, sessionType: request.sessionType, hours: request.hours, addOns: request.addOns)
    }

    private func applyCode() {
        let code = codeInput.trimmingCharacters(in: .whitespaces).uppercased()
        guard !code.isEmpty else { return }
        isCheckingCode = true
        Task {
            defer { isCheckingCode = false }
            do {
                promo = try await app.backend.checkPromoCode(studioId: request.studio.id, code: code)
                codeInput = ""
            } catch {
                self.error = error.userMessage
            }
        }
    }

    var body: some View {
        Form {
            Section("Your session") {
                InfoRow(symbol: "building.2", title: request.studio.name)
                InfoRow(symbol: "waveform", title: request.sessionType.name, value: "\(request.hours) h")
                InfoRow(symbol: "calendar", title: request.startsAt.formatted(date: .abbreviated, time: .omitted), value: "\(request.startsAt.formatted(date: .omitted, time: .shortened)) – \(request.startsAt.adding(hours: request.hours).formatted(date: .omitted, time: .shortened))")
            }

            Section("Payment") {
                PriceBreakdownView(price: price)
            }

            if confirmed == nil {
                Section {
                    if let promo {
                        HStack {
                            Label("\(promo.code) · −\(promo.percentOff)%", systemImage: "tag.fill")
                                .foregroundStyle(Theme.positive)
                            Spacer()
                            Button("Remove", role: .destructive) { self.promo = nil }
                                .font(.subheadline)
                        }
                    } else {
                        HStack {
                            TextField("Enter a code", text: $codeInput)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .onSubmit(applyCode)
                            Button("Apply", action: applyCode)
                                .disabled(codeInput.trimmingCharacters(in: .whitespaces).isEmpty || isCheckingCode)
                        }
                    }
                } header: {
                    Text("Promo code")
                } footer: {
                    if let promo, !promo.description.isEmpty { Text(promo.description) }
                }
            }

            if cashAvailable && cardAvailable {
                Section {
                    Picker("Payment", selection: $payWithCash) {
                        Label("Pay now in the app", systemImage: "creditcard").tag(false)
                        Label("Pay cash at the studio", systemImage: "banknote").tag(true)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("How do you want to pay?")
                } footer: {
                    if payWithCash {
                        Text("Bring \(Money.format(price.total, currency: price.currency)) in cash to your session. Paying in the app gives you automatic refunds under the cancellation policy.")
                    }
                }
            }

            if payWithCash {
                Section {
                    Label("Pay \(Money.format(price.total, currency: price.currency)) in cash at the session.", systemImage: "banknote")
                        .font(.footnote)
                    Label("When you pay cash we cannot guarantee a refund, as EasySesh does not handle the cash. We will, however, look into it and try to help.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                }
            } else if cardAvailable {
                Section {
                    Label("Card or Apple Pay – securely processed by Stripe.", systemImage: "lock.shield")
                        .font(.footnote)
                }
            } else {
                Section {
                    Label("In-app payment isn't available yet, and this studio doesn't accept cash. Message the studio to arrange your session.", systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                }
            }

            Section {
                Toggle(isOn: $agreed) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("I agree to the studio's rules and the \(L10n.tr(request.studio.bookingPolicy.cancellationPolicy.title).lowercased()) cancellation policy.")
                        Text(localized: request.studio.bookingPolicy.cancellationPolicy.summary).font(.caption).foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }
            } footer: {
                if !request.studio.bookingPolicy.instantBook {
                    Text(payWithCash
                         ? LocalizedStringKey("This studio confirms requests manually, within 24 hours.")
                         : LocalizedStringKey("This studio confirms requests manually, within 24 hours. Your card is authorised now and only charged if they accept."))
                }
            }

            Section {
                if request.studio.bookingPolicy.checkInEnabled {
                    Label("Check in in the app when you arrive. EasySesh recommends it: it protects you against fraud and helps us sort out any problem.", systemImage: "location.circle")
                        .font(.footnote)
                } else {
                    Label("This studio has turned off check-in. EasySesh can't promise a refund if something goes wrong with this session.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                }
            }
        }
        .easyseshGrouped()
        .navigationTitle("Checkout")
        .safeAreaInset(edge: .bottom) {
            Button { pay() } label: {
                if isPaying {
                    ProgressView().tint(.white)
                } else {
                    Text(payButtonTitle)
                }
            }
            .buttonStyle(.primary)
            .disabled(!agreed || isPaying || (!payWithCash && !cardAvailable))
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationDestination(item: $confirmed) { booking in
            BookingConfirmationView(booking: booking, onDone: onFinish)
        }
        .onAppear {
            if !cardAvailable && cashAvailable { payWithCash = true }
        }
        .task(id: promo?.code) {
            serverPrice = try? await app.backend.quoteBooking(studio: request.studio, sessionTypeId: request.sessionType.id, hours: request.hours, addOns: request.addOns, promoCode: promo?.code)
        }
        .errorAlert($error)
    }

    private func pay() {
        isPaying = true
        Task {
            defer { isPaying = false }
            do {
                var request = request
                request.promoCode = promo?.code
                let booking = try await app.backend.createBooking(request)
                if payWithCash {
                    confirmed = try await app.backend.confirmCashBooking(bookingId: booking.id)
                    await app.refreshBadges()
                    return
                }
                let intent = try await app.backend.preparePayment(bookingId: booking.id, method: method)
                let outcome = try await StripePaymentProcessor.pay(intent)
                if case .cancelled = outcome { return }
                confirmed = try await app.backend.confirmPayment(bookingId: booking.id, method: method)
                await app.refreshBadges()
            } catch {
                self.error = error.userMessage
            }
        }
    }
}

struct BookingConfirmationView: View {
    @Environment(AppState.self) private var app
    let booking: Booking
    let onDone: () -> Void
    @State private var addedToCalendar = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: booking.status == .confirmed ? "checkmark.circle.fill" : "clock.badge.checkmark.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(booking.status == .confirmed ? Theme.positive : Theme.warning)
                    .padding(.top, 32)
                Text(LocalizedStringKey(booking.status == .confirmed ? "You're booked!" : "Request sent"))
                    .font(.largeTitle.bold())
                Text(booking.status == .confirmed
                     ? (booking.isCash
                        ? L10n.format("Pay %@ in cash at the studio. We'll remind you before your session.", Money.format(booking.price.total, currency: booking.price.currency))
                        : L10n.tr("We've sent a confirmation and receipt. We'll remind you before your session."))
                     : L10n.format("%@ will respond within 24 hours.", booking.studioName) + (booking.isCash ? "" : " " + L10n.tr("You're only charged if they accept.")))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    InfoRow(symbol: "number", title: "Reference", value: booking.reference)
                    InfoRow(symbol: "building.2", title: booking.studioName)
                    InfoRow(symbol: "calendar", title: booking.startsAt.formatted(date: .complete, time: .omitted))
                    InfoRow(symbol: "clock", title: "\(booking.startsAt.formatted(date: .omitted, time: .shortened)) – \(booking.endsAt.formatted(date: .omitted, time: .shortened))")
                    InfoRow(symbol: booking.isCash ? "banknote" : "creditcard", title: booking.paymentStatus.title, value: Money.format(booking.isCash ? booking.price.total : booking.price.dueNow, currency: booking.price.currency))
                }
                .card()

                Button {
                    Task {
                        do {
                            try await CalendarExporter.add(booking)
                            addedToCalendar = true
                        } catch { self.error = error.userMessage }
                    }
                } label: {
                    Label(LocalizedStringKey(addedToCalendar ? "Added to calendar" : "Add to calendar"), systemImage: addedToCalendar ? "checkmark" : "calendar.badge.plus")
                }
                .buttonStyle(.bordered)
                .disabled(addedToCalendar)

                Button("Done") {
                    app.selectedTab = .bookings
                    onDone()
                }
                .buttonStyle(.primary)
            }
            .padding()
        }
        .navigationBarBackButtonHidden()
        .onAppear { app.syncReminders(for: [booking]) }
        .errorAlert($error)
    }
}

enum CalendarExporter {
    static func add(_ booking: Booking) async throws {
        let store = EKEventStore()
        guard try await store.requestWriteOnlyAccessToEvents() else {
            throw BackendError.validation("Allow calendar access in Settings to add sessions.")
        }
        let event = EKEvent(eventStore: store)
        event.title = "\(booking.sessionTypeName) · \(booking.studioName)"
        event.startDate = booking.startsAt
        event.endDate = booking.endsAt
        event.notes = L10n.format("EasySesh booking %@", booking.reference)
        event.calendar = store.defaultCalendarForNewEvents
        event.addAlarm(EKAlarm(relativeOffset: -3600))
        try store.save(event, span: .thisEvent)
    }
}

/// The studio's live offers ("Mixing 50% off") on the booking screen.
struct StudioOffersSection: View {
    let studio: Studio
    let offers: [StudioOffer]

    var body: some View {
        let live = offers.filter(\.isLive)
        if !live.isEmpty {
            Section("Offers") {
                ForEach(live) { OfferRow(offer: $0, studio: studio) }
            }
        }
    }
}

struct OfferRow: View {
    let offer: StudioOffer
    let studio: Studio

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "percent")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(offer.title).font(.subheadline.weight(.semibold))
                Text(L10n.format("%lld%% off · %@", offer.percentOff, offer.targetName(in: studio))
                     + (offer.endsAt.map { " · " + L10n.format("Until %@", $0.formatted(date: .abbreviated, time: .omitted)) } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("−\(offer.percentOff)%")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.positive, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
