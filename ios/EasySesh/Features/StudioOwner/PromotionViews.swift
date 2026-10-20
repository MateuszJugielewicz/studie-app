import SwiftUI

/// A studio's promotion status: a "Promoted" tag and a place at the top of search for a period.
/// Promotions are bought on the website or given by the EasySesh team. The app only shows the status:
/// it doesn't sell promotions or point to where they're sold (App Store guideline 3.1.1 / 3.1.3).
struct PromotionView: View {
    @Environment(AppState.self) private var app
    let studio: Studio

    @State private var promotions: [StudioPromotion] = []
    @State private var error: String?

    private var active: StudioPromotion? { promotions.first { $0.status == .active } }
    private var history: [StudioPromotion] { promotions.filter { $0.status != .pending && $0.status != .active } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                if let active {
                    activeCard(active)
                } else {
                    Label("Your studio isn't promoted right now.", systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(padding: 16)
                }
                if !history.isEmpty {
                    GlowSectionHeader(title: "History", count: history.count)
                    ForEach(history) { historyRow($0) }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .auroraBackground(height: 380)
        .navigationTitle("Promote")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await Task { await load() }.value }
        .task { await load() }
        .errorAlert($error)
    }

    // MARK: Sections

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconTile(symbol: "megaphone.fill", size: 48, colors: TilePalette.signal)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Get seen first").font(.system(size: 26, weight: .heavy)).tracking(-0.5)
                    Text("Promoted studios are shown at the top of Discover and search, with a Promoted tag.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                PromotedTag()
                Image(systemName: "arrow.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Label("Top of results", systemImage: "arrow.up.to.line").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .glassCard(padding: 18, cornerRadius: 24)
        .padding(.top, 8)
    }

    private func activeCard(_ promotion: StudioPromotion) -> some View {
        HStack(spacing: 12) {
            PulseDot(color: Theme.positive, isActive: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your studio is promoted").font(.headline)
                if let end = promotion.endsAt ?? studio.promotedUntil {
                    Text("Until \(end.formatted(date: .abbreviated, time: .shortened))").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            PromotedTag()
        }
        .glassCard()
    }

    private func historyRow(_ promotion: StudioPromotion) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(localized: promotion.package.title).font(.subheadline.weight(.semibold))
                Text(promotion.createdAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.format(promotion.amount, currency: promotion.currency)).font(.subheadline).monospacedDigit()
            StatusPill(text: promotion.status.title, color: promotion.status == .expired ? Color.secondary : Color.red)
        }
        .glassCard(padding: 12)
    }

    private func load() async {
        do { promotions = try await app.backend.promotions(studioId: studio.id) }
        catch { self.error = error.userMessage }
    }
}

extension PromotionStatus {
    var title: String {
        switch self {
        case .pending: "Waiting for payment"
        case .active: "Active"
        case .expired: "Ended"
        case .cancelled: "Cancelled"
        }
    }
}

/// A studio shows its owner's artist profile on its page (and the studio appears on the artist
/// profile) once the artist confirms.
struct StudioArtistLinkView: View {
    @Environment(AppState.self) private var app
    let studio: Studio

    @State private var link: StudioArtistLink?
    @State private var linkedArtist: ArtistProfile?
    @State private var query = ""
    @State private var results: [ArtistSearchResult] = []
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    IconTile(symbol: "link", size: 48, colors: TilePalette.violet)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your artist profile").font(.system(size: 26, weight: .heavy)).tracking(-0.5)
                        Text("Are you an artist too? Connect your artist profile: it's shown on your studio page, and your studio on your artist profile.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)

                if let link {
                    current(link)
                } else {
                    search
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .auroraBackground(height: 340)
        .navigationTitle("Artist profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .errorAlert($error)
    }

    private func current(_ link: StudioArtistLink) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Avatar(url: linkedArtist?.avatarUrl, name: linkedArtist?.artistName ?? "?", size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(linkedArtist?.artistName ?? "…").font(.headline)
                    Text(link.isAccepted ? LocalizedStringKey("Connected") : LocalizedStringKey("Waiting for the artist to confirm in their profile"))
                        .font(.caption).foregroundStyle(link.isAccepted ? Theme.positive : Color.secondary)
                }
                Spacer()
            }
            if link.isAccepted {
                NavigationLink { ArtistPublicProfileView(artistId: link.artistId, initial: linkedArtist) } label: {
                    Label("View artist profile", systemImage: "person.crop.circle").font(.subheadline.weight(.semibold))
                }
            }
            Button(role: .destructive) { remove() } label: {
                Text(link.isAccepted ? LocalizedStringKey("Remove connection") : LocalizedStringKey("Cancel request"))
            }
            .buttonStyle(.secondary)
            .disabled(isWorking)
        }
        .glassCard()
    }

    @ViewBuilder private var search: some View {
        GlassField(symbol: "magnifyingglass", isFocused: false) {
            TextField("Search your artist name", text: $query)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { find() }
        }
        .onChange(of: query) { _, value in if value.count >= 2 { find() } else { results = [] } }
        Text("The artist has to confirm the connection from their profile, so only your own profile can be connected.")
            .font(.caption).foregroundStyle(.secondary)
        ForEach(results) { artist in
            HStack(spacing: 12) {
                Avatar(url: artist.avatarUrl, name: artist.artistName, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(artist.artistName).font(.subheadline.weight(.semibold))
                        if artist.isVerified { VerifiedBadge() }
                        if artist.hasAdminBadge == true { AdminBadge(compact: true) }
                                    if artist.isPromoted == true { PromotedTag() }
                    }
                    if !artist.city.isEmpty { Text(artist.city).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Button("Connect") { request(artist) }
                    .font(.subheadline.weight(.bold))
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(isWorking)
            }
            .glassCard(padding: 12)
        }
    }

    private func load() async {
        do {
            link = try await app.backend.studioArtistLink(studioId: studio.id)
            if let link { linkedArtist = try? await app.backend.artistProfile(id: link.artistId) }
        } catch { self.error = error.userMessage }
    }

    private func find() {
        let text = query
        Task {
            let found = (try? await app.backend.searchArtists(query: text)) ?? []
            if text == query { results = found }
        }
    }

    private func request(_ artist: ArtistSearchResult) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                link = try await app.backend.requestStudioArtistLink(artistId: artist.id)
                linkedArtist = try? await app.backend.artistProfile(id: artist.id)
            } catch { self.error = error.userMessage }
        }
    }

    private func remove() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await app.backend.removeStudioArtistLink(studioId: studio.id)
                link = nil
                linkedArtist = nil
            } catch { self.error = error.userMessage }
        }
    }
}

// MARK: - Offers & promo codes

/// Studio offers ("Mixing 50% off", applied automatically) and the studio's own promo codes. Both
/// come off the studio's price; EasySesh's fee is calculated on the discounted price.
struct StudioOffersView: View {
    @Environment(AppState.self) private var app
    let studio: Studio
    @State private var offers: [StudioOffer] = []
    @State private var codes: [PromoCode] = []
    @State private var editingOffer: StudioOffer?
    @State private var editingCode: PromoCode?
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                ForEach(offers) { offer in
                    Button { editingOffer = offer } label: {
                        HStack {
                            OfferRow(offer: offer, studio: studio)
                            Toggle("", isOn: Binding(get: { offer.isActive }, set: { on in save { var o = offer; o.isActive = on; try await app.backend.saveOffer(o) } }))
                                .labelsHidden()
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions { Button("Delete", role: .destructive) { save { try await app.backend.removeOffer(id: offer.id) } } }
                }
                Button {
                    editingOffer = StudioOffer(id: UUID(), studioId: studio.id, title: "", percentOff: 20, appliesTo: "everything", targetId: nil, endsAt: nil, isActive: true)
                } label: { Label("New offer", systemImage: "plus") }
            } header: {
                Text("Offers")
            } footer: {
                Text("Offers are applied automatically when artists book, and shown on your studio page. If several match, the biggest one is used.")
            }

            Section {
                ForEach(codes) { code in
                    Button { editingCode = code } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(code.code) · −\(code.percentOff)%").font(.subheadline.weight(.semibold).monospaced())
                                Text(code.maxUses.map { L10n.format("Used %lld of %lld", code.uses ?? 0, $0) } ?? L10n.format("Used %lld times", code.uses ?? 0))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(get: { code.isActive }, set: { on in save { var c = code; c.isActive = on; try await app.backend.savePromoCode(c) } }))
                                .labelsHidden()
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions { Button("Delete", role: .destructive) { save { try await app.backend.removePromoCode(id: code.id) } } }
                }
                Button {
                    editingCode = PromoCode(id: UUID(), studioId: studio.id, code: "", percentOff: 10)
                } label: { Label("New promo code", systemImage: "plus") }
            } header: {
                Text("Promo codes")
            } footer: {
                Text("Give a code to artists (on social media, to regulars…). They type it in at checkout to get the discount.")
            }

            Section {
                Text("Discounts come off your price. EasySesh's platform fee is calculated on the discounted price.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .easyseshGrouped()
        .navigationTitle("Offers & promo codes")
        .task { await reload() }
        .sheet(item: $editingOffer) { offer in
            NavigationStack { OfferEditor(studio: studio, offer: offer) { await reload() } }
        }
        .sheet(item: $editingCode) { code in
            NavigationStack { PromoCodeEditor(code: code) { await reload() } }
        }
        .errorAlert($error)
    }

    private func reload() async {
        do {
            offers = try await app.backend.studioOffers(studioId: studio.id)
            codes = try await app.backend.promoCodes(studioId: studio.id)
        } catch { self.error = error.userMessage }
    }

    private func save(_ action: @escaping () async throws -> Void) {
        Task {
            do { try await action() } catch { self.error = error.userMessage }
            await reload()
        }
    }
}

private struct OfferEditor: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let studio: Studio
    @State var offer: StudioOffer
    let onSaved: () async -> Void
    @State private var hasEnd = false
    @State private var isSaving = false
    @State private var error: String?
    private let isNew: Bool

    init(studio: Studio, offer: StudioOffer, onSaved: @escaping () async -> Void) {
        self.studio = studio
        isNew = offer.title.isEmpty
        _offer = State(initialValue: offer)
        _hasEnd = State(initialValue: offer.endsAt != nil)
        self.onSaved = onSaved
    }

    private var needsTarget: Bool { offer.appliesTo == "session_type" || offer.appliesTo == "add_on" }
    private var valid: Bool { offer.title.trimmingCharacters(in: .whitespaces).count >= 2 && (!needsTarget || offer.targetId != nil) }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $offer.title)
                Stepper(value: $offer.percentOff, in: 5...90, step: 5) {
                    Label("\(offer.percentOff)%", systemImage: "tag")
                }
            } header: {
                Text("Offer")
            } footer: {
                Text("Shown to artists, e.g. “Mixing half price” or “Weekday deal”.")
            }
            Section("Applies to") {
                Picker("Discount on", selection: Binding(get: { offer.appliesTo }, set: { offer.appliesTo = $0; offer.targetId = nil })) {
                    Text("Everything").tag("everything")
                    Text("All sessions").tag("sessions")
                    Text("All extras").tag("add_ons")
                    Text("One session type").tag("session_type")
                    Text("One extra").tag("add_on")
                }
                if offer.appliesTo == "session_type" {
                    Picker("Session type", selection: $offer.targetId) {
                        Text("Choose…").tag(String?.none)
                        ForEach(studio.sessionTypes) { Text($0.name).tag(Optional($0.id)) }
                    }
                } else if offer.appliesTo == "add_on" {
                    Picker("Extra", selection: $offer.targetId) {
                        Text("Choose…").tag(String?.none)
                        ForEach(studio.addOns) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
            }
            Section {
                Toggle("Last day", isOn: Binding(get: { hasEnd }, set: { hasEnd = $0; offer.endsAt = $0 ? (offer.endsAt ?? .now.adding(days: 30)) : nil }))
                if hasEnd, let end = offer.endsAt {
                    DatePicker("Last day", selection: Binding(get: { end }, set: { offer.endsAt = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: $0) }), in: Date.now..., displayedComponents: .date)
                }
            } header: {
                Text("Ends")
            } footer: {
                Text("Leave empty to keep the offer until you turn it off.")
            }
        }
        .easyseshGrouped()
        .navigationTitle(LocalizedStringKey(isNew ? "New offer" : "Edit offer"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving { ProgressView() } else {
                    Button("Save") {
                        isSaving = true
                        Task {
                            defer { isSaving = false }
                            do {
                                offer.title = offer.title.trimmingCharacters(in: .whitespaces)
                                try await app.backend.saveOffer(offer)
                                await onSaved()
                                dismiss()
                            } catch { self.error = error.userMessage }
                        }
                    }
                    .disabled(!valid)
                }
            }
        }
        .errorAlert($error)
    }
}

private struct PromoCodeEditor: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State var code: PromoCode
    let onSaved: () async -> Void
    @State private var isSaving = false
    @State private var error: String?

    init(code: PromoCode, onSaved: @escaping () async -> Void) {
        _code = State(initialValue: code)
        self.onSaved = onSaved
    }

    private var valid: Bool { code.code.range(of: "^[A-Z0-9]{3,20}$", options: .regularExpression) != nil }

    var body: some View {
        Form {
            Section {
                TextField("SUMMER20", text: Binding(get: { code.code }, set: { code.code = String($0.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(20)) }))
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Stepper(value: $code.percentOff, in: 1...90) { Label("\(code.percentOff)%", systemImage: "tag") }
                TextField("Note for artists (optional)", text: $code.description)
            } header: {
                Text("Code")
            } footer: {
                Text("3–20 letters or digits, e.g. SUMMER20.")
            }
            Section("Limits") {
                Stepper(value: Binding(get: { code.maxUses ?? 0 }, set: { code.maxUses = $0 == 0 ? nil : $0 }), in: 0...1000) {
                    LabeledContent("Uses in total", value: code.maxUses.map(String.init) ?? L10n.tr("No limit"))
                }
                Stepper(value: $code.maxUsesPerUser, in: 1...100) {
                    LabeledContent("Uses per artist", value: "\(code.maxUsesPerUser)")
                }
                Toggle("Last day", isOn: Binding(get: { code.endsAt != nil }, set: { code.endsAt = $0 ? .now.adding(days: 30) : nil }))
                if let end = code.endsAt {
                    DatePicker("Last day", selection: Binding(get: { end }, set: { code.endsAt = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: $0) }), in: Date.now..., displayedComponents: .date)
                }
            }
        }
        .easyseshGrouped()
        .navigationTitle(LocalizedStringKey(code.uses == nil ? "New promo code" : "Edit promo code"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving { ProgressView() } else {
                    Button("Save") {
                        isSaving = true
                        Task {
                            defer { isSaving = false }
                            do {
                                code.description = code.description.trimmingCharacters(in: .whitespaces)
                                try await app.backend.savePromoCode(code)
                                await onSaved()
                                dismiss()
                            } catch { self.error = error.userMessage }
                        }
                    }
                    .disabled(!valid)
                }
            }
        }
        .errorAlert($error)
    }
}
