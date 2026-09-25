import SwiftUI

/// Studios buy a promotion: a "Promoted" tag and a place at the top of search for a period.
/// With Stripe set up it's paid in the app; until then the order is a request that EasySesh
/// activates after payment by invoice.
struct PromotionView: View {
    @Environment(AppState.self) private var app
    let studio: Studio

    @State private var promotions: [StudioPromotion] = []
    @State private var selected: PromotionPackage = .twoWeeks
    @State private var isWorking = false
    @State private var error: String?
    @State private var info: String?

    private var cardAvailable: Bool { AppConfig.stripePublishableKey != nil }
    private var pending: StudioPromotion? { promotions.first { $0.status == .pending } }
    private var active: StudioPromotion? { promotions.first { $0.status == .active } }
    private var history: [StudioPromotion] { promotions.filter { $0.status != .pending && $0.status != .active } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                if let active { activeCard(active) }
                if let pending {
                    pendingCard(pending)
                } else {
                    packages
                    orderButton
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
        .alert("Order received", isPresented: Binding(get: { info != nil }, set: { if !$0 { info = nil } })) {
            Button("OK") { info = nil }
        } message: {
            Text(localized: info ?? "")
        }
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

    private var packages: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlowSectionHeader(title: "Choose a period")
            ForEach(PromotionPackage.purchasable) { package in
                let isSelected = package == selected
                let price = package.price(currency: studio.currency)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { selected = package }
                } label: {
                    HStack(spacing: 12) {
                        IconTile(symbol: package == .month ? "crown.fill" : package == .twoWeeks ? "star.fill" : "sparkle",
                                 size: 38, colors: isSelected ? TilePalette.signal : TilePalette.muted)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(localized: package.title).font(.headline).foregroundStyle(.primary)
                                if package == .twoWeeks {
                                    Text("Popular").font(.caption2.weight(.heavy)).textCase(.uppercase)
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(Theme.violet.opacity(0.15), in: Capsule())
                                        .foregroundStyle(Theme.violet)
                                }
                            }
                            Text("\(Money.format(price / max(package.days, 1), currency: studio.currency)) per day")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Money.format(price, currency: studio.currency)).font(.headline.weight(.heavy)).monospacedDigit().foregroundStyle(.primary)
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? Theme.accent : Color.secondary.opacity(0.5))
                    }
                    .padding(14)
                    .background(Theme.card.opacity(isSelected ? 0.95 : 0.7), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(isSelected ? AnyShapeStyle(Theme.neon) : AnyShapeStyle(Theme.glassEdge), lineWidth: isSelected ? 1.5 : 0.8))
                }
                .buttonStyle(.plain)
            }
            Text(active != nil
                 ? LocalizedStringKey("A new period starts when your current promotion ends.")
                 : LocalizedStringKey("Your promotion starts as soon as it's paid. Prices include no VAT; VAT is added where it applies."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var orderButton: some View {
        VStack(spacing: 8) {
            Button { order() } label: {
                Text(cardAvailable
                     ? LocalizedStringKey("Pay \(Money.format(selected.price(currency: studio.currency), currency: studio.currency))")
                     : LocalizedStringKey("Order promotion"))
            }
            .buttonStyle(.primary)
            .disabled(isWorking || studio.status != .approved)
            if studio.status != .approved {
                Text("Your studio must be approved before it can be promoted.").font(.caption).foregroundStyle(Theme.warning)
            } else if !cardAvailable {
                Text("In-app payment isn't available yet. EasySesh sends you an invoice and switches the promotion on once it's paid.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
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

    private func pendingCard(_ promotion: StudioPromotion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconTile(symbol: "hourglass", size: 38, colors: TilePalette.violet)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Order waiting for payment").font(.headline)
                    Text("\(Text(localized: promotion.package.title)) · \(Money.format(promotion.amount, currency: promotion.currency))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Text(cardAvailable
                 ? LocalizedStringKey("Pay now to start your promotion right away.")
                 : LocalizedStringKey("EasySesh sends you an invoice and switches the promotion on once it's paid."))
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Cancel order") { cancel(promotion) }.buttonStyle(.secondary)
                if cardAvailable {
                    Button("Pay now") { pay(promotion) }.buttonStyle(.primary)
                }
            }
            .disabled(isWorking)
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

    // MARK: Actions

    private func load() async {
        do { promotions = try await app.backend.promotions(studioId: studio.id) }
        catch { self.error = error.userMessage }
    }

    private func order() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let promotion = try await app.backend.requestPromotion(selected)
                if cardAvailable {
                    try await payNow(promotion)
                } else {
                    info = "We've received your order. You'll get an invoice by email, and the promotion starts once it's paid."
                }
                await load()
            } catch { self.error = error.userMessage }
        }
    }

    private func pay(_ promotion: StudioPromotion) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await payNow(promotion)
                await load()
            } catch { self.error = error.userMessage }
        }
    }

    private func payNow(_ promotion: StudioPromotion) async throws {
        let intent = try await app.backend.preparePromotionPayment(promotionId: promotion.id)
        let outcome = try await StripePaymentProcessor.pay(intent)
        guard case .completed = outcome else { return }
        try await app.backend.confirmPromotionPayment(promotionId: promotion.id)
        app.ownedStudio = (try? await app.backend.ownedStudio()) ?? app.ownedStudio
    }

    private func cancel(_ promotion: StudioPromotion) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await app.backend.cancelPromotionRequest(id: promotion.id)
                await load()
            } catch { self.error = error.userMessage }
        }
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
