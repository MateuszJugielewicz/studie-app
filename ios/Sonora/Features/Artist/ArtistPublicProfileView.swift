import SwiftUI

/// An artist's public profile: seen by studios (from a chat, booking or studio page) and by the
/// artist themself, who can also dispute ratings and confirm studio connections here.
struct ArtistPublicProfileView: View {
    @Environment(AppState.self) private var app
    let artistId: UUID
    @State var initial: ArtistProfile?

    @State private var profile: ArtistProfile?
    @State private var reviews: [ArtistReview] = []
    @State private var links: [StudioArtistLink] = []
    @State private var studios: [UUID: Studio] = [:]
    @State private var disputing: ArtistReview?
    @State private var disputed: Set<UUID> = []
    @State private var error: String?

    private var isOwn: Bool { app.account?.id == artistId }
    private var shown: ArtistProfile? { profile ?? initial }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let shown {
                    hero(shown)
                    if !shown.links.isEmpty { linkChips(shown) }
                }
                studioSection
                ratingsSection
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .auroraBackground(height: 420)
        .navigationTitle(shown?.artistName ?? String(localized: "Artist"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await Task { await load() }.value }
        .task { await load() }
        .sheet(item: $disputing) { review in
            DisputeRatingSheet(kind: .artistReview, reviewId: review.id) { disputed.insert(review.id) }
        }
        .errorAlert($error)
    }

    private func load() async {
        do {
            profile = try await app.backend.artistProfile(id: artistId) ?? profile
            reviews = try await app.backend.artistReviews(artistId: artistId)
            links = try await app.backend.artistStudioLinks(artistId: artistId)
            for link in links where studios[link.studioId] == nil {
                studios[link.studioId] = try? await app.backend.studio(id: link.studioId)
            }
        } catch { self.error = error.userMessage }
    }

    // MARK: Sections

    private func hero(_ profile: ArtistProfile) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.neon).frame(width: 124, height: 124).blur(radius: 18).opacity(0.5)
                Avatar(url: profile.avatarUrl, name: profile.artistName, size: 104)
                    .padding(4)
                    .overlay(Circle().strokeBorder(Theme.neon, lineWidth: 3))
            }
            HStack(spacing: 6) {
                Text(profile.artistName).font(.system(size: 26, weight: .heavy)).tracking(-0.5)
                if profile.isVerified { VerifiedBadge() }
                if profile.hasAdminBadge == true { AdminBadge() }
            }
            HStack(spacing: 8) {
                if !profile.city.isEmpty {
                    Label(profile.city, systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.card.opacity(0.78), in: Capsule())
                }
                RatingPill(average: profile.ratingAverage ?? 0, count: profile.reviewCount ?? 0)
            }
            if !profile.genres.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(profile.genres) { genre in
                        Text(localized: genre.title)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Theme.violet.opacity(0.14), in: Capsule())
                            .foregroundStyle(Theme.violet)
                    }
                }
            }
            if !profile.bio.isEmpty {
                Text(profile.bio).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 20, cornerRadius: 26)
    }

    private func linkChips(_ profile: ArtistProfile) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(profile.links) { link in
                    if let url = link.resolvedURL {
                        Link(destination: url) {
                            HStack(spacing: 8) {
                                IconTile(symbol: link.platform.symbol, size: 26, colors: link.platform.brandColors)
                                Text(localized: link.platform.title).font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(.primary)
                            .padding(.leading, 6).padding(.trailing, 14).padding(.vertical, 6)
                            .background(Theme.card.opacity(0.78), in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.glassEdge, lineWidth: 0.8))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var studioSection: some View {
        let accepted = links.filter(\.isAccepted)
        let pending = links.filter { !$0.isAccepted }
        if isOwn && !pending.isEmpty {
            ForEach(pending, id: \.studioId) { link in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        IconTile(symbol: "link", size: 36, colors: TilePalette.violet)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connect your studio?").font(.subheadline.weight(.bold))
                            Text("\(studios[link.studioId]?.name ?? String(localized: "A studio")) wants to show your artist profile on its page, and the studio on your profile.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 10) {
                        Button("Decline") { respond(link, accept: false) }.buttonStyle(.secondary)
                        Button("Connect") { respond(link, accept: true) }.buttonStyle(.primary)
                    }
                }
                .glassCard()
            }
        }
        if !accepted.isEmpty {
            GlowSectionHeader(title: String(localized: "Studio"))
            ForEach(accepted, id: \.studioId) { link in
                if let studio = studios[link.studioId] {
                    NavigationLink { StudioDetailView(studioId: studio.id, initial: studio) } label: {
                        HStack(spacing: 12) {
                            RemoteImage(url: studio.photoUrls.first)
                                .frame(width: 54, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(studio.name).font(.headline).foregroundStyle(.primary)
                                Text(studio.address.publicArea).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isOwn {
                                Button {
                                    Task {
                                        try? await app.backend.removeStudioArtistLink(studioId: studio.id)
                                        await load()
                                    }
                                } label: { Image(systemName: "link.badge.plus").rotationEffect(.degrees(45)) }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Remove connection")
                            }
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                        }
                        .glassCard(padding: 12)
                    }
                    .buttonStyle(PressableCardStyle())
                }
            }
        }
    }

    @ViewBuilder private var ratingsSection: some View {
        let visible = reviews
        GlowSectionHeader(title: String(localized: "Ratings from studios"), count: visible.count)
        if visible.isEmpty {
            GlassEmptyState(title: "No ratings yet", symbol: "star.bubble.fill", message: "Studios can rate artists after a completed session.")
        }
        ForEach(visible) { review in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(review.studioName).font(.subheadline.weight(.bold))
                    Spacer()
                    StarsView(rating: review.rating, size: 13)
                }
                if !review.text.isEmpty {
                    Text(review.text).font(.subheadline).foregroundStyle(.secondary)
                }
                HStack {
                    Text(review.createdAt.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    if isOwn {
                        if disputed.contains(review.id) {
                            Label("Dispute sent", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.positive)
                        } else {
                            Button { disputing = review } label: {
                                Label("Dispute", systemImage: "flag.fill").font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            .glassCard(padding: 14)
            .scrollReveal()
        }
    }

    private func respond(_ link: StudioArtistLink, accept: Bool) {
        Task {
            do {
                try await app.backend.respondStudioArtistLink(studioId: link.studioId, accept: accept)
                await load()
            } catch { self.error = error.userMessage }
        }
    }
}

/// Ask EasySesh to look at a rating you think is unfair.
struct DisputeRatingSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let kind: RatingKind
    let reviewId: UUID
    var onSent: () -> Void = {}

    @State private var reason = ""
    @State private var isSending = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        IconTile(symbol: "scale.3d", size: 44, colors: TilePalette.violet)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Dispute this rating").font(.title3.weight(.heavy))
                            Text("Our team checks the booking and the rating. If it breaks our guidelines or isn't about a real session, we remove it.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    TextField("Why is this rating unfair?", text: $reason, axis: .vertical)
                        .lineLimit(5...10)
                        .padding(14)
                        .background(Theme.card.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
                    Button {
                        send()
                    } label: {
                        Text(isSending ? LocalizedStringKey("Sending…") : LocalizedStringKey("Send dispute"))
                    }
                    .buttonStyle(.primary)
                    .disabled(isSending || reason.trimmingCharacters(in: .whitespaces).count < 10)
                }
                .padding(20)
            }
            .auroraBackground(height: 300)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .errorAlert($error)
        }
        .presentationDetents([.medium, .large])
    }

    private func send() {
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await app.backend.disputeRating(kind: kind, reviewId: reviewId, reason: reason)
                onSent()
                dismiss()
            } catch { self.error = error.userMessage }
        }
    }
}
