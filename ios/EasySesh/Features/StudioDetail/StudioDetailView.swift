import SwiftUI
import MapKit

struct StudioDetailView: View {
    @Environment(AppState.self) private var app
    let studioId: UUID
    @State var initial: Studio?

    @State private var studio: Studio?
    @State private var reviews: [Review] = []
    @State private var nextSlots: [TimeSlot] = []
    @State private var showBooking = false
    @State private var showReport = false
    @State private var conversation: Conversation?
    @State private var linkedArtist: ArtistProfile?
    @State private var error: String?

    var body: some View {
        Group {
            if let studio = studio ?? initial {
                content(studio)
            } else {
                ProgressView()
            }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .errorAlert($error)
    }

    private func content(_ studio: Studio) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Gallery(urls: studio.photoUrls)

                VStack(alignment: .leading, spacing: 24) {
                    header(studio)
                    if !nextSlots.isEmpty { availabilitySection(studio) }
                    pricingSection(studio)
                    textSection("About", studio.description)
                    if studio.videoUrl != nil || !studio.contact.website.isEmpty {
                        HStack(spacing: 10) {
                            if let video = studio.videoUrl, let url = SocialLink.resolve(video, platform: .youtube) {
                                Link(destination: url) { linkChip("Studio tour", symbol: "play.rectangle.fill") }
                            }
                            if let url = SocialLink.resolve(studio.contact.website, platform: .website) {
                                Link(destination: url) { linkChip("Website", symbol: "globe") }
                            }
                        }
                    }
                    facilitiesSection(studio)
                    equipmentSection(studio)
                    if !studio.engineers.isEmpty { peopleSection(studio) }
                    genresSection(studio)
                    hoursSection(studio)
                    rulesSection(studio)
                    locationSection(studio)
                    reviewsSection(studio)

                    Button { showReport = true } label: {
                        Label("Report this studio", systemImage: "flag")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 100)
        }
        .ignoresSafeArea(edges: .top)
        .safeAreaInset(edge: .bottom) { bookingBar(studio) }
        .sheet(isPresented: $showBooking) {
            BookingFlowView(studio: studio)
        }
        .sheet(isPresented: $showReport) {
            ReportSheet(target: .studio, targetId: studio.id)
        }
        .navigationDestination(item: $conversation) { conversation in
            ChatView(conversation: conversation)
        }
    }

    private func header(_ studio: Studio) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if studio.isPromoted { PromotedTag() }
            HStack(alignment: .firstTextBaseline) {
                Text(studio.name).font(.display(32)).tracking(-0.5)
                if studio.isVerified { VerifiedBadge().font(.title2) }
                if studio.showsAdminBadge { AdminBadge() }
            }
            if !studio.specialTags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(studio.specialTags, id: \.self) { SpecialTagChip(title: $0) }
                }
            }
            if let linkedArtist {
                NavigationLink { ArtistPublicProfileView(artistId: linkedArtist.id, initial: linkedArtist) } label: {
                    HStack(spacing: 10) {
                        Avatar(url: linkedArtist.avatarUrl, name: linkedArtist.artistName, size: 34)
                            .overlay(Circle().strokeBorder(Theme.neon, lineWidth: 1.5))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Run by").font(.caption2.weight(.bold)).foregroundStyle(.secondary).textCase(.uppercase)
                            HStack(spacing: 4) {
                                Text(linkedArtist.artistName).font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                                if linkedArtist.hasAdminBadge == true { AdminBadge(compact: true) }
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                    }
                    .glassCard(padding: 10, cornerRadius: 18)
                }
                .buttonStyle(PressableCardStyle())
            }
            Text(studio.tagline).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                RatingLabel(rating: studio.ratingAverage, count: studio.reviewCount)
                Label(studio.address.publicArea, systemImage: "mappin")
                let distance = app.location.effectiveLocation.distance(from: studio.location)
                if app.location.isAuthorized {
                    Text(Distance.format(meters: distance)).foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            FlowLayout(spacing: 8) {
                if studio.bookingPolicy.instantBook { Chip(title: "Instant book", symbol: "bolt.fill") }
                Chip(title: "Up to \(studio.capacity) people", symbol: "person.2")
                Chip(title: "\(studio.bookingCount) sessions booked", symbol: "calendar")
            }
            .padding(.top, 4)
        }
    }

    private func availabilitySection(_ studio: Studio) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GlowSectionHeader(title: "Next available")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Array(nextSlots.prefix(8).enumerated()), id: \.element.id) { index, slot in
                        Button { showBooking = true } label: {
                            VStack(spacing: 2) {
                                Text(slot.start.formatted(.dateTime.weekday(.abbreviated).day())).font(.caption.weight(.semibold))
                                    .opacity(0.8)
                                Text(slot.start.formatted(date: .omitted, time: .shortened)).font(.subheadline.weight(.heavy))
                            }
                            .foregroundStyle(index == 0 ? Color.white : Color.primary)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background {
                                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                                if index == 0 {
                                    shape.fill(Theme.neon).neonGlow(Theme.magenta, radius: 8)
                                } else {
                                    shape.fill(Theme.card.opacity(0.78))
                                        .overlay(shape.strokeBorder(Color.primary.opacity(0.1)))
                                }
                            }
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                }
            }
        }
    }

    private func pricingSection(_ studio: Studio) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GlowSectionHeader(title: "Prices")
            ForEach(studio.sessionTypes) { type in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(type.name).fontWeight(.semibold)
                            if type.includesEngineer { Image(systemName: "person.wave.2").foregroundStyle(Theme.accent) }
                        }
                        if !type.details.isEmpty { Text(type.details).font(.footnote).foregroundStyle(.secondary) }
                        Text("Min. \(type.minimumHours)h").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Money.format(type.hourlyRate, currency: studio.currency))/h").bold()
                }
                .card()
            }
            if !studio.addOns.isEmpty {
                Text("Add-ons").font(.headline).padding(.top, 4)
                ForEach(studio.addOns) { addOn in
                    HStack {
                        Text(addOn.name)
                        Spacer()
                        Text("\(Money.format(addOn.price, currency: studio.currency)) \(addOn.unit.suffix)").foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
            if studio.bookingPolicy.depositPercent > 0 {
                Label("\(studio.bookingPolicy.depositPercent)% deposit at booking, the rest is charged after your session.", systemImage: "creditcard")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func linkChip(_ title: LocalizedStringKey, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Theme.card.opacity(0.78), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.glassEdge, lineWidth: 0.8))
    }

    private func textSection(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GlowSectionHeader(title: title)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private func facilitiesSection(_ studio: Studio) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GlowSectionHeader(title: "Facilities")
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 10) {
                ForEach(studio.facilities) { facility in
                    Label(facility.title, systemImage: facility.symbol).font(.subheadline)
                }
            }
        }
    }

    private func equipmentSection(_ studio: Studio) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GlowSectionHeader(title: "Equipment")
            ForEach(EquipmentCategory.allCases) { category in
                let items = studio.equipment.filter { $0.category == category }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.title).font(.subheadline.bold())
                        ForEach(items) { Text("• \($0.name)").font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }

    private func peopleSection(_ studio: Studio) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GlowSectionHeader(title: "Engineers & producers")
            ForEach(studio.engineers) { person in
                HStack(spacing: 12) {
                    Avatar(url: nil, name: person.name, size: 40)
                    VStack(alignment: .leading) {
                        Text(person.name).fontWeight(.semibold)
                        Text(person.role).font(.caption).foregroundStyle(Theme.accent)
                        if !person.bio.isEmpty { Text(person.bio).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }

    private func genresSection(_ studio: Studio) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GlowSectionHeader(title: "Genres")
            FlowLayout { ForEach(studio.genres) { Chip(title: $0.title) } }
        }
    }

    private func hoursSection(_ studio: Studio) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GlowSectionHeader(title: "Opening hours")
            ForEach(OpeningHours.displayOrder, id: \.self) { weekday in
                if let hours = studio.hours(for: weekday) {
                    HStack {
                        Text(hours.weekdayName)
                        Spacer()
                        Text(hours.label).foregroundStyle(hours.isClosed ? Color.secondary : Color.primary)
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private func rulesSection(_ studio: Studio) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GlowSectionHeader(title: "Rules & terms")
            ForEach(studio.rules, id: \.self) { rule in
                Label(rule, systemImage: "checkmark.circle").font(.subheadline)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Cancellation: \(studio.bookingPolicy.cancellationPolicy.title)").font(.subheadline.bold())
                Text(studio.bookingPolicy.cancellationPolicy.summary).font(.footnote).foregroundStyle(.secondary)
                if !studio.bookingPolicy.terms.isEmpty {
                    Text(studio.bookingPolicy.terms).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }

    private func locationSection(_ studio: Studio) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GlowSectionHeader(title: "Location")
            Map(initialPosition: .region(MKCoordinateRegion(center: studio.coordinate, latitudinalMeters: 1200, longitudinalMeters: 1200))) {
                Marker(studio.name, systemImage: "waveform", coordinate: studio.coordinate).tint(Theme.accent)
                UserAnnotation()
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
            .allowsHitTesting(false)
            Text(studio.address.publicArea).font(.subheadline)
            Text("The exact address is shared after booking.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button { LocationService.openDirections(to: studio) } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                }
                .buttonStyle(.borderedProminent)
                Button { LocationService.openDirections(to: studio, preferGoogle: true) } label: {
                    Label("Google Maps", systemImage: "map")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func reviewsSection(_ studio: Studio) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            GlowSectionHeader(title: "Reviews")
            ReviewSummaryView(studio: studio, reviews: reviews)
            ForEach(reviews.prefix(3)) { ReviewRow(review: $0, canReply: false) }
            if reviews.count > 3 {
                NavigationLink("See all \(reviews.count) reviews") {
                    ReviewsListView(studio: studio, reviews: reviews, canReply: false)
                }
            }
        }
    }

    private func bookingBar(_ studio: Studio) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading) {
                Text("From \(Money.format(studio.priceFrom, currency: studio.currency))/h").font(.headline)
                Text(studio.bookingPolicy.instantBook ? "Instant confirmation" : "Studio confirms within 24h").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if app.role == .artist {
                Button {
                    Task {
                        do { conversation = try await app.backend.conversation(studioId: studio.id, bookingId: nil) }
                        catch { self.error = error.userMessage }
                    }
                } label: {
                    GlassIcon(symbol: "bubble.left.fill")
                }
                .accessibilityLabel("Message studio")
                Button("Book") { showBooking = true }
                    .buttonStyle(.primary)
                    .frame(width: 120)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private func load() async {
        do {
            let loaded = try await app.backend.studio(id: studioId)
            studio = loaded
            if let link = try? await app.backend.studioArtistLink(studioId: studioId), link.isAccepted {
                linkedArtist = try? await app.backend.artistProfile(id: link.artistId)
            }
            reviews = try await app.backend.reviews(studioId: studioId)
            nextSlots = await Self.nextSlots(for: loaded, backend: app.backend)
        } catch { self.error = error.userMessage }
    }

    static func nextSlots(for studio: Studio, backend: Backend, days: Int = 7) async -> [TimeSlot] {
        let start = Date.now.startOfDay
        let busy = (try? await backend.busyIntervals(studioIds: [studio.id], from: start, to: start.adding(days: days + 1)))?[studio.id] ?? []
        let hours = studio.sessionTypes.map(\.minimumHours).min() ?? 1
        let engine = AvailabilityEngine()
        var slots: [TimeSlot] = []
        for offset in 0..<days {
            slots += engine.availableSlots(for: studio, on: start.adding(days: offset), hours: hours, busy: busy).prefix(2)
        }
        return slots
    }
}

struct Gallery: View {
    let urls: [String]

    var body: some View {
        TabView {
            if urls.isEmpty {
                RemoteImage(url: nil)
            }
            ForEach(urls, id: \.self) { url in
                RemoteImage(url: url)
            }
        }
        .tabViewStyle(.page)
        .frame(height: 320)
        .clipped()
    }
}
