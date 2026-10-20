import SwiftUI
import PhotosUI
import MapKit

@MainActor
@Observable
final class DiscoverModel {
    var studios: [Studio] = []
    var busy: [UUID: [DateInterval]] = [:]
    var filters = SearchFilters()
    var sort: StudioSort = .nearest
    var isLoading = false
    var error: String?

    private let engine = SearchEngine()

    func load(_ backend: Backend) async {
        isLoading = studios.isEmpty
        defer { isLoading = false }
        do {
            studios = try await backend.publishedStudios()
            error = nil
            await loadAvailability(backend)
        } catch where error.isCancellation {
            // Try again once: a cancelled first load would otherwise leave the list empty.
            if studios.isEmpty, let loaded = try? await backend.publishedStudios() { studios = loaded }
        } catch { self.error = error.userMessage }
    }

    /// Availability filtering needs bookings/blocks for the chosen day.
    func loadAvailability(_ backend: Backend) async {
        guard let day = filters.availableOn else { busy = [:]; return }
        busy = (try? await backend.busyIntervals(studioIds: studios.map(\.id), from: day.startOfDay, to: day.startOfDay.adding(days: 2))) ?? [:]
    }

    func results(origin: CLLocation?) -> [StudioResult] {
        engine.search(studios: studios, filters: filters, sort: sort, origin: origin, busy: busy)
    }

    func summary(origin: CLLocation, areaName: String, radiusKm: Double) -> AreaSummary {
        engine.areaSummary(results: engine.search(studios: studios, filters: SearchFilters(), sort: .nearest, origin: origin), areaName: areaName, radiusKm: radiusKm)
    }
}

struct DiscoverView: View {
    @Environment(AppState.self) private var app
    @State private var model = DiscoverModel()
    @State private var showMap = false
    @State private var showFilters = false
    @State private var path = NavigationPath()

    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            let origin = app.location.effectiveLocation
            let results = model.results(origin: origin)
            let metric = app.account?.settings.useMetricUnits ?? true

            Group {
                if showMap {
                    StudioMapView(results: results, metric: metric) { path.append($0.studio) }
                        .safeAreaInset(edge: .top) {
                            VStack(spacing: 10) {
                                HStack(spacing: 10) {
                                    searchField
                                    GlassIconButton(symbol: "list.bullet", label: "Show list") {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showMap = false }
                                    }
                                }
                                controlsRow(count: results.count)
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                        }
                        .toolbar(.hidden, for: .navigationBar)
                        .transition(.opacity)
                } else {
                    EasySeshScreen("Find a studio", eyebrow: app.location.cityName ?? Date.now.greeting,
                                 refresh: { await model.load(app.backend) }) {
                        GlassIconButton(symbol: "map", label: "Show map") {
                            searchFocused = false
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showMap = true }
                        }
                    } content: {
                        StoryBar()
                        searchField
                        controlsRow(count: results.count)
                        AreaSummaryCard(summary: model.summary(origin: origin, areaName: app.location.cityName ?? L10n.tr("Your area"), radiusKm: app.account?.settings.searchRadiusKm ?? 5),
                                        totalCount: results.count, isSearching: !model.filters.query.isEmpty)
                        if model.isLoading {
                            ProgressView().frame(maxWidth: .infinity).padding(40)
                        } else if results.isEmpty {
                            GlassEmptyState(title: "No studios found", symbol: "waveform.slash", message: "Try widening your filters or search area.")
                            if model.filters.activeCount > 0 {
                                Button("Clear filters") { withAnimation(.snappy) { model.filters = SearchFilters() } }
                                    .buttonStyle(.secondary)
                            }
                        }
                        LazyVStack(spacing: 24) {
                            ForEach(results) { result in
                                NavigationLink(value: result.studio) {
                                    StudioCard(result: result, metric: metric)
                                }
                                .buttonStyle(PressableCardStyle())
                                .scrollReveal()
                            }
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .transition(.opacity)
                }
            }
            .navigationDestination(for: Studio.self) { studio in
                StudioDetailView(studioId: studio.id, initial: studio)
            }
            .sheet(isPresented: $showFilters) {
                FilterSheet(filters: $model.filters)
                    .presentationDetents([.large])
            }
            .onChange(of: model.filters.availableOn) {
                Task { await model.loadAvailability(app.backend) }
            }
            .onChange(of: model.filters.sessionHours) {
                Task { await model.loadAvailability(app.backend) }
            }
            .task {
                app.location.requestPermission()
                await Task { await model.load(app.backend) }.value
            }
            .errorAlert($model.error)
        }
    }

    private var searchField: some View {
        GlassField(symbol: "magnifyingglass", isFocused: searchFocused) {
            TextField("Studio, area or city", text: $model.filters.query)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { searchFocused = false }
            if !model.filters.query.isEmpty {
                Button {
                    withAnimation(.snappy) { model.filters.query = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Clear search")
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: searchFocused)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.filters.query.isEmpty)
    }

    private func controlsRow(count: Int) -> some View {
        HStack(spacing: 8) {
            Button { showFilters = true } label: {
                FilterPill(title: model.filters.activeCount > 0 ? L10n.format("Filters · %lld", model.filters.activeCount) : L10n.tr("Filters"),
                           symbol: "slider.horizontal.3", isActive: model.filters.activeCount > 0)
            }
            .buttonStyle(PressableCardStyle())
            Menu {
                Picker("Sort", selection: $model.sort) {
                    ForEach(StudioSort.allCases) { Text(localized: $0.title).tag($0) }
                }
            } label: {
                FilterPill(title: model.sort.title, symbol: "arrow.up.arrow.down", isActive: false)
            }
            Spacer(minLength: 4)
            HStack(spacing: 5) {
                Circle().fill(Theme.neon).frame(width: 7, height: 7).neonGlow(Theme.magenta, radius: 4)
                Text("\(count) studios")
                    .font(.footnote.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.card.opacity(0.78), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.glassEdge, lineWidth: 0.8))
            .animation(.snappy, value: count)
        }
        .haptic(.selection, trigger: model.sort)
    }
}

/// Pill used for Filters / Sort: glass when idle, neon when a filter is active.
struct FilterPill: View {
    let title: String
    let symbol: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isActive ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.neon))
            Text(localized: title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(isActive ? Color.white : Color.primary)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background {
            if isActive {
                Capsule().fill(Theme.neon).neonGlow(Theme.magenta, radius: 8)
            } else {
                Capsule().fill(Theme.card.opacity(0.78))
                    .overlay(Capsule().strokeBorder(Theme.glassEdge, lineWidth: 0.8))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
    }
}

struct AreaSummaryCard: View {
    let summary: AreaSummary
    var totalCount = 0
    var isSearching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(isSearching ? "Results" : "Near you")).eyebrow()
            Text(isSearching ? L10n.format("%lld studios", totalCount) : summary.areaName)
                .font(.display(30))
                .tracking(-0.5)
                .contentTransition(.numericText())
            Group {
                if isSearching {
                    Text("Searching everywhere, sorted by distance.")
                } else if summary.studioCount == 0 && totalCount > 0 {
                    Text("No studios within \(Int(summary.radiusKm)) km yet – \(totalCount) elsewhere. Search a city or country to find them.")
                } else {
                    HStack(spacing: 6) {
                        Text("\(summary.studioCount) studios within \(Int(summary.radiusKm)) km")
                        if let price = summary.priceFrom {
                            Text("·")
                            Text("from \(Money.format(price, currency: summary.currency))/h")
                        }
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }
}

/// Photo-first listing card: image on top, facts underneath, no chrome.
struct StudioCard: View {
    let result: StudioResult
    var metric = true

    var body: some View {
        let studio = result.studio
        VStack(alignment: .leading, spacing: 10) {
            Color.clear
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay { RemoteImage(url: studio.photoUrls.first) }
                .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if studio.bookingPolicy.instantBook {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill").foregroundStyle(Theme.neon)
                            Text("Instant book")
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.glassEdge, lineWidth: 0.8))
                        .foregroundStyle(.primary)
                        .padding(10)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if studio.isPromoted { PromotedTag().padding(10) }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                        .strokeBorder(studio.isPromoted ? AnyShapeStyle(Theme.neon) : AnyShapeStyle(Theme.glassEdge),
                                      lineWidth: studio.isPromoted ? 1.5 : 0.8)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(studio.name).font(.headline).lineLimit(1)
                    if studio.isVerified { VerifiedBadge() }
                    if studio.showsAdminBadge { AdminBadge(compact: true) }
                    Spacer(minLength: 8)
                    RatingLabel(rating: studio.ratingAverage, count: studio.reviewCount, compact: true)
                }
                Text(areaLine(studio)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                (Text(Money.format(studio.priceFrom, currency: studio.currency)).fontWeight(.semibold) + Text(" / hour").foregroundColor(.secondary))
                    .font(.subheadline)
                    .padding(.top, 2)
                if !studio.specialTags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(studio.specialTags.prefix(2), id: \.self) { SpecialTagChip(title: $0) }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func areaLine(_ studio: Studio) -> String {
        var parts = [studio.address.publicArea]
        if let distance = result.distance { parts.append(Distance.format(meters: distance, metric: metric)) }
        return parts.joined(separator: " · ")
    }
}

struct StudioMapView: View {
    let results: [StudioResult]
    let metric: Bool
    let onOpen: (StudioResult) -> Void

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedId: UUID?

    /// Region that contains every studio in the results (the user's own position is not included,
    /// so a studio in Denmark is shown even when you are browsing from far away).
    private static func region(fitting results: [StudioResult]) -> MKCoordinateRegion? {
        let coordinates = results.map(\.studio.coordinate)
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude, minLon = first.longitude, maxLon = first.longitude
        for c in coordinates {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: min(max((maxLat - minLat) * 1.5, 0.05), 170),
                                    longitudeDelta: min(max((maxLon - minLon) * 1.5, 0.05), 350))
        return MKCoordinateRegion(center: center, span: span)
    }

    private func showAll(animated: Bool = true) {
        guard let region = Self.region(fitting: results) else { return }
        if animated {
            withAnimation(.smooth(duration: 0.8)) { position = .region(region) }
        } else {
            position = .region(region)
        }
    }

    var body: some View {
        Map(position: $position, selection: $selectedId) {
            UserAnnotation()
            ForEach(results) { result in
                Annotation(result.studio.name, coordinate: result.studio.coordinate, anchor: .bottom) {
                    Text(Money.format(result.studio.priceFrom, currency: result.studio.currency))
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background {
                            if selectedId == result.id {
                                Capsule().fill(Theme.neon)
                            } else {
                                Capsule().fill(.regularMaterial)
                            }
                        }
                        .foregroundStyle(selectedId == result.id ? Theme.onAccent : Color.primary)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.8))
                        .neonGlow(selectedId == result.id ? Theme.magenta : Color.black, radius: selectedId == result.id ? 10 : 4)
                        .scaleEffect(selectedId == result.id ? 1.12 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedId)
                }
                .tag(result.id)
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .bottom) {
            if let selected = results.first(where: { $0.id == selectedId }) {
                Button { onOpen(selected) } label: {
                    StudioCard(result: selected, metric: metric).card(padding: 10)
                }
                .buttonStyle(.plain)
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) {
            if !results.isEmpty {
                Button { showAll() } label: {
                    Label("All studios · \(results.count)", systemImage: "scope")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.glassEdge, lineWidth: 0.8))
                }
                .buttonStyle(PressableCardStyle())
                .padding(.top, 8)
            }
        }
        .onAppear { showAll(animated: false) }
        .onChange(of: results.map(\.id)) { showAll() }
        .animation(.spring, value: selectedId)
    }
}

struct FilterSheet: View {
    @Binding var filters: SearchFilters
    @Environment(\.dismiss) private var dismiss
    @State private var draft = SearchFilters()

    private let priceSteps: [Int?] = [nil, 1500, 2500, 4000, 6000]
    private let distanceSteps: [Double?] = [nil, 2, 5, 10, 25]

    var body: some View {
        NavigationStack {
            Form {
                Section("Max price per hour") {
                    Picker("Max price", selection: $draft.maxPrice) {
                        ForEach(priceSteps, id: \.self) { value in
                            Text(value.map { Money.format($0, currency: "EUR") } ?? "Any").tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Distance") {
                    Picker("Distance", selection: $draft.maxDistanceKm) {
                        ForEach(distanceSteps, id: \.self) { value in
                            Text(value.map { L10n.format("%lld km", Int($0)) } ?? L10n.tr("Any")).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Availability") {
                    Toggle("Available on a specific day", isOn: Binding(
                        get: { draft.availableOn != nil },
                        set: { draft.availableOn = $0 ? Date.now.adding(days: 1).startOfDay : nil }
                    ))
                    if let day = draft.availableOn {
                        DatePicker("Day", selection: Binding(get: { day }, set: { draft.availableOn = $0.startOfDay }), in: Date.now.startOfDay..., displayedComponents: .date)
                        Stepper("For at least \(draft.sessionHours) hours", value: $draft.sessionHours, in: 1...PlatformConfig.maxSessionHours)
                    }
                    Toggle("Instant book only", isOn: $draft.instantBookOnly)
                }

                Section("Rating") {
                    Picker("Minimum rating", selection: $draft.minRating) {
                        Text("Any").tag(Double?.none)
                        Text("4.0+").tag(Double?.some(4.0))
                        Text("4.5+").tag(Double?.some(4.5))
                        Text("4.8+").tag(Double?.some(4.8))
                    }
                    .pickerStyle(.segmented)
                }

                Section("Genres") {
                    ChipPicker(items: Genre.allCases, selection: $draft.genres, title: { $0.title })
                        .padding(.vertical, 4)
                }

                Section("Facilities") {
                    ChipPicker(items: Facility.allCases, selection: $draft.facilities, title: { $0.title }, symbol: { $0.symbol })
                        .padding(.vertical, 4)
                }

                Section("Services") {
                    Toggle("Engineer available", isOn: $draft.engineerIncluded)
                    Toggle("Mixing", isOn: $draft.offersMixing)
                    Toggle("Mastering", isOn: $draft.offersMastering)
                }

                Section {
                    TextField("e.g. U87, SM7B, Neve", text: $draft.equipmentQuery)
                        .autocorrectionDisabled()
                    ChipPicker(items: EquipmentCategory.allCases, selection: $draft.equipmentCategories, title: { $0.title })
                        .padding(.vertical, 4)
                } header: {
                    Text("Equipment")
                }
            }
            .easyseshGrouped()
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { draft = SearchFilters(query: filters.query) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Show results") {
                        filters = draft
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear { draft = filters }
        }
    }
}

// MARK: - Find artists (studios)

extension DiscoveredArtist {
    var searchResult: ArtistSearchResult {
        ArtistSearchResult(id: id, artistName: artistName, city: city, genres: genres, avatarUrl: avatarUrl, isVerified: isVerified,
                           hasBooked: hasBooked, hasAdminBadge: hasAdminBadge, isPromoted: isPromoted)
    }
}

/// Studios find artists the way artists find studios: search, filters and sorting over every artist,
/// promoted artists first with a Promoted tag. "Message" writes to them (a message request unless they
/// booked the studio before).
struct FindArtistsView: View {
    @Environment(AppState.self) private var app
    @State private var artists: [DiscoveredArtist] = []
    @State private var filters = ArtistFilters()
    @State private var sort: ArtistSort = .recommended
    @State private var isLoading = true
    @State private var showFilters = false
    @State private var messaging: DiscoveredArtist?
    @State private var error: String?
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            let results = ArtistSearch.search(artists, filters: filters, sort: sort)
            EasySeshScreen("Find artists", eyebrow: L10n.tr("For your studio"), refresh: { await load() }) {
                VStack(alignment: .leading, spacing: 14) {
                    GlassField(symbol: "magnifyingglass", isFocused: searchFocused) {
                        TextField("Artist, genre or city", text: $filters.query)
                            .focused($searchFocused)
                            .submitLabel(.search)
                            .autocorrectionDisabled()
                            .onSubmit { searchFocused = false }
                        if !filters.query.isEmpty {
                            Button { filters.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear search")
                        }
                    }
                    HStack(spacing: 8) {
                        Button { showFilters = true } label: {
                            FilterPill(title: filters.activeCount > 0 ? L10n.format("Filters · %lld", filters.activeCount) : L10n.tr("Filters"),
                                       symbol: "slider.horizontal.3", isActive: filters.activeCount > 0)
                        }
                        .buttonStyle(PressableCardStyle())
                        Menu {
                            Picker("Sort", selection: $sort) {
                                ForEach(ArtistSort.allCases) { Text(localized: $0.title).tag($0) }
                            }
                        } label: {
                            FilterPill(title: sort.title, symbol: "arrow.up.arrow.down", isActive: false)
                        }
                        Spacer(minLength: 4)
                        Text(L10n.format("%lld artists", results.count)).font(.footnote.weight(.bold)).monospacedDigit()
                    }
                    if results.contains(where: \.isPromoted) {
                        Text("Promoted artists are shown first.").font(.caption).foregroundStyle(.secondary)
                    }
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(40)
                    } else if results.isEmpty {
                        GlassEmptyState(title: "No artists found", symbol: "music.mic", message: "Try another search or fewer filters.")
                        if filters.activeCount > 0 {
                            Button("Clear filters") { filters = ArtistFilters(query: filters.query) }.buttonStyle(.secondary)
                        }
                    }
                    LazyVStack(spacing: 14) {
                        ForEach(results) { artist in
                            ArtistDiscoveryCard(artist: artist) { messaging = artist }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationDestination(for: DiscoveredArtist.self) { artist in
                ArtistPublicProfileView(artistId: artist.id, initial: nil)
            }
            .sheet(isPresented: $showFilters) {
                ArtistFilterSheet(filters: $filters).presentationDetents([.medium, .large])
            }
            .sheet(item: $messaging) { artist in
                NavigationStack {
                    NewMessageSheet(initial: artist.searchResult) { conversation in app.open(.conversation(conversation.id)) }
                }
            }
            .task { await load() }
            .errorAlert($error)
        }
    }

    private func load() async {
        defer { isLoading = false }
        do { artists = try await app.backend.discoverArtists() } catch { self.error = error.userMessage }
    }
}

private struct ArtistDiscoveryCard: View {
    let artist: DiscoveredArtist
    var onMessage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: artist) {
                HStack(alignment: .top, spacing: 12) {
                    Avatar(url: artist.avatarUrl, name: artist.artistName, size: 58)
                        .overlay(Circle().strokeBorder(artist.isPromoted ? AnyShapeStyle(Theme.neon) : AnyShapeStyle(Color.clear), lineWidth: 2))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(artist.artistName).font(.headline).foregroundStyle(.primary).lineLimit(1)
                            if artist.isVerified { VerifiedBadge() }
                            if artist.hasAdminBadge { AdminBadge(compact: true) }
                        }
                        Text([artist.city, artist.hasBooked ? L10n.tr("Booked you before") : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        HStack(spacing: 10) {
                            if artist.reviewCount > 0 { RatingLabel(rating: artist.ratingAverage, count: artist.reviewCount, compact: true) }
                            if artist.sessionCount > 0 { Text(L10n.format("%lld sessions", artist.sessionCount)).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    Spacer(minLength: 0)
                    if artist.isPromoted { PromotedTag() }
                }
            }
            .buttonStyle(.plain)
            if !artist.bio.isEmpty {
                Text(artist.bio).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            if !artist.genres.isEmpty {
                Text(artist.genres.prefix(4).map { Genre(rawValue: $0).map { L10n.tr($0.title) } ?? $0 }.joined(separator: " · "))
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            }
            Button(action: onMessage) { Label("Message", systemImage: "bubble.left") }
                .buttonStyle(.secondary)
        }
        .glassCard()
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(artist.isPromoted ? AnyShapeStyle(Theme.neon) : AnyShapeStyle(Color.clear), lineWidth: 1.5))
    }
}

private struct ArtistFilterSheet: View {
    @Binding var filters: ArtistFilters
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ArtistFilters()

    var body: some View {
        NavigationStack {
            Form {
                Section("Rating") {
                    Picker("Minimum rating", selection: $draft.minRating) {
                        Text("Any").tag(Double?.none)
                        Text("4.0+").tag(Double?.some(4.0))
                        Text("4.5+").tag(Double?.some(4.5))
                        Text("4.8+").tag(Double?.some(4.8))
                    }
                    .pickerStyle(.segmented)
                }
                Section("Artists") {
                    Toggle("Verified artists only", isOn: $draft.verifiedOnly)
                    Toggle("Booked your studio before", isOn: $draft.bookedBefore)
                }
                Section("Genres") {
                    ChipPicker(items: Genre.allCases, selection: $draft.genres, title: { $0.title })
                        .padding(.vertical, 4)
                }
            }
            .easyseshGrouped()
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Show results") { filters = draft; dismiss() }.bold()
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Reset") { draft = ArtistFilters(query: filters.query) }
                }
            }
            .onAppear { draft = filters }
        }
    }
}

// MARK: - Stories

/// A row of circles for everyone with a live story (like Instagram), plus "Your story" to post one.
/// Shown at the top of Discover and the studio dashboard.
struct StoryBar: View {
    @Environment(AppState.self) private var app
    @State private var authors: [StoryAuthor]?
    @State private var viewing: StoryViewerStart?
    @State private var composing = false

    private var canPost: Bool {
        guard let account = app.account, account.emailVerifiedAt != nil else { return false }
        switch account.role {
        case .artist: return !(app.artistProfile?.artistName.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        case .studioOwner: return app.ownedStudio?.status == .approved
        default: return false
        }
    }

    var body: some View {
        Group {
            if let authors, app.account != nil, canPost || authors.contains(where: { !$0.isOwn }) {
                let own = authors.first { $0.isOwn }
                let ordered = (own.map { [$0] } ?? []) + authors.filter { !$0.isOwn }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        if canPost && own == nil {
                            circle(name: L10n.tr("Your story"), avatar: myAvatar, ring: .add) { composing = true }
                        }
                        ForEach(Array(ordered.enumerated()), id: \.element.userId) { index, author in
                            circle(name: author.isOwn ? L10n.tr("Your story") : author.name, avatar: author.avatarUrl,
                                   ring: author.allSeen ? .seen : .new, showsPlus: author.isOwn && canPost, onPlus: { composing = true }) {
                                viewing = StoryViewerStart(authors: ordered, index: index)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }
            }
        }
        .task { await load() }
        .fullScreenCover(item: $viewing, onDismiss: { Task { await load() } }) { start in
            StoryViewer(authors: start.authors, startIndex: start.index)
        }
        .sheet(isPresented: $composing) {
            NavigationStack { StoryComposer { Task { await load() } } }
        }
    }

    private var myAvatar: String? {
        app.role == .studioOwner ? app.ownedStudio?.photoUrls.first : app.artistProfile?.avatarUrl
    }

    private enum Ring { case new, seen, add }

    private func circle(name: String, avatar: String?, ring: Ring, showsPlus: Bool = false, onPlus: @escaping () -> Void = {}, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack(alignment: .bottomTrailing) {
                    Avatar(url: avatar, name: name, size: 58)
                        .padding(3)
                        .overlay(Circle().strokeBorder(ring == .new ? AnyShapeStyle(Theme.neon) : AnyShapeStyle(Color.secondary.opacity(0.35)),
                                                       style: StrokeStyle(lineWidth: ring == .new ? 3 : 1.5, dash: ring == .add ? [4, 3] : [])))
                    if ring == .add || showsPlus {
                        Image(systemName: "plus").font(.caption.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(Theme.neon, in: Circle())
                            .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                            .onTapGesture { ring == .add ? action() : onPlus() }
                    }
                }
                Text(name).font(.caption2).lineLimit(1).frame(width: 72).foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        guard app.account != nil else { return }
        authors = (try? await app.backend.storyFeed()) ?? authors ?? []
    }
}

struct StoryViewerStart: Identifiable {
    let id = UUID()
    let authors: [StoryAuthor]
    let index: Int
}

/// Full-screen story player: tap right/left for next/previous, hold to pause, like or reply at the
/// bottom. The poster sees views, likes and replies instead, and can remove the story.
struct StoryViewer: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let authors: [StoryAuthor]
    @State var authorIndex: Int
    @State private var stories: [Story]?
    @State private var index = 0
    @State private var progress: Double = 0
    @State private var isHolding = false
    @State private var reply = ""
    @State private var showActivity = false
    @State private var confirmRemove = false
    @State private var reporting = false
    @State private var info: String?
    @State private var error: String?
    @FocusState private var replyFocused: Bool

    private static let seconds = 6.0
    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    init(authors: [StoryAuthor], startIndex: Int) {
        self.authors = authors
        _authorIndex = State(initialValue: startIndex)
    }

    private var author: StoryAuthor { authors[authorIndex] }
    private var story: Story? { stories.flatMap { $0.indices.contains(index) ? $0[index] : nil } }
    private var isPaused: Bool { isHolding || showActivity || confirmRemove || reporting || replyFocused || !reply.isEmpty }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let story {
                RemoteImage(url: story.mediaUrl, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(story.id)
            } else {
                ProgressView().tint(.white)
            }
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle()).onTapGesture { previous() }.frame(maxWidth: .infinity)
                Color.clear.contentShape(Rectangle()).onTapGesture { next() }.frame(maxWidth: .infinity).layoutPriority(1.8)
            }
            .simultaneousGesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in isHolding = true }
                .onEnded { value in
                    isHolding = false
                    if value.translation.height > 120 { dismiss() }
                })
            VStack(spacing: 0) {
                header
                Spacer()
                footer
            }
        }
        .foregroundStyle(.white)
        .statusBarHidden()
        .task(id: authorIndex) { await loadStories() }
        .onReceive(tick) { _ in
            guard story != nil, !isPaused else { return }
            progress += 0.05 / Self.seconds
            if progress >= 1 { next() }
        }
        .onChange(of: story?.id) {
            guard let story, !author.isOwn, !story.seen else { return }
            Task { try? await app.backend.markStoryViewed(id: story.id) }
        }
        .sheet(isPresented: $showActivity) {
            if let story { NavigationStack { StoryActivityView(storyId: story.id) } }
        }
        .sheet(isPresented: $reporting) {
            ReportSheet(target: author.studioId == nil ? .user : .studio, targetId: author.studioId ?? author.userId)
        }
        .confirmationDialog("Remove this story?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { remove() }
        } message: {
            Text("It disappears for everyone right away.")
        }
        .alert(Text(localized: info ?? ""), isPresented: Binding(get: { info != nil }, set: { if !$0 { info = nil } })) {
            Button("OK") { info = nil }
        }
        .errorAlert($error)
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(Array((stories ?? []).enumerated()), id: \.element.id) { i, _ in
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.35))
                            Capsule().fill(.white).frame(width: geo.size.width * (i < index ? 1 : i == index ? min(progress, 1) : 0))
                        }
                    }
                    .frame(height: 2.5)
                }
            }
            HStack(spacing: 8) {
                Avatar(url: author.avatarUrl, name: author.name, size: 34)
                Text(author.name).font(.subheadline.weight(.bold)).lineLimit(1)
                if author.isVerified { VerifiedBadge() }
                if author.isPromoted { PromotedTag() }
                if let story {
                    Text(story.createdAt.formatted(.relative(presentation: .named))).font(.caption).opacity(0.75)
                }
                Spacer()
                if story != nil {
                    if author.isOwn {
                        Button { confirmRemove = true } label: { Image(systemName: "trash") }.accessibilityLabel("Remove story")
                    } else {
                        Button { reporting = true } label: { Image(systemName: "flag") }.accessibilityLabel("Report")
                    }
                }
                Button { dismiss() } label: { Image(systemName: "xmark").font(.title3.weight(.semibold)) }.accessibilityLabel("Close")
            }
            .font(.headline)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 24)
        .background(LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom))
    }

    @ViewBuilder private var footer: some View {
        if let story {
            VStack(alignment: .leading, spacing: 10) {
                if !story.caption.isEmpty {
                    Text(story.caption).font(.body.weight(.semibold)).shadow(radius: 3)
                }
                if author.isOwn {
                    Button { showActivity = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "eye"); Text(L10n.format("%lld views", story.viewCount ?? 0))
                            Image(systemName: "heart"); Text("\(story.likeCount)")
                            Image(systemName: "bubble.left"); Text("\(story.replyCount ?? 0)")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.black.opacity(0.35), in: Capsule())
                    }
                } else {
                    HStack(spacing: 10) {
                        TextField("", text: $reply, prompt: Text(L10n.format("Reply to %@…", author.name)).foregroundStyle(.white.opacity(0.75)))
                            .focused($replyFocused)
                            .submitLabel(.send)
                            .onSubmit { sendReply() }
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .overlay(Capsule().strokeBorder(.white.opacity(0.55)))
                        if reply.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button { toggleLike() } label: {
                                Image(systemName: story.likedByMe ? "heart.fill" : "heart").font(.title2)
                                    .foregroundStyle(story.likedByMe ? Color(red: 1, green: 0.24, blue: 0.43) : .white)
                            }
                            .accessibilityLabel(story.likedByMe ? "Unlike" : "Like")
                            .sensoryFeedback(.impact, trigger: story.likedByMe)
                        } else {
                            Button { sendReply() } label: { Image(systemName: "paperplane.fill").font(.title3) }.accessibilityLabel("Send")
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 30)
            .padding(.bottom, 12)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
        }
    }

    private func loadStories() async {
        stories = nil
        progress = 0
        do {
            let list = try await app.backend.userStories(userId: author.userId)
            guard !list.isEmpty else { next(); return }
            stories = list
            let firstNew = list.firstIndex { !$0.seen } ?? 0
            index = author.isOwn ? 0 : firstNew
        } catch {
            self.error = error.userMessage
        }
    }

    private func next() {
        progress = 0
        if let stories, index < stories.count - 1 { index += 1 }
        else if authorIndex < authors.count - 1 { authorIndex += 1 }
        else { dismiss() }
    }

    private func previous() {
        progress = 0
        if index > 0 { index -= 1 } else if authorIndex > 0 { authorIndex -= 1 }
    }

    private func toggleLike() {
        guard let story, var list = stories, let i = list.firstIndex(where: { $0.id == story.id }) else { return }
        let like = !story.likedByMe
        list[i].likedByMe = like
        list[i].likeCount += like ? 1 : -1
        stories = list
        Task { do { _ = try await app.backend.likeStory(id: story.id, like: like) } catch { self.error = error.userMessage } }
    }

    private func sendReply() {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let story, !text.isEmpty else { return }
        Task {
            do {
                try await app.backend.replyToStory(id: story.id, body: text)
                reply = ""
                replyFocused = false
                info = "Reply sent."
            } catch { self.error = error.userMessage }
        }
    }

    private func remove() {
        guard let story else { return }
        Task {
            do {
                try await app.backend.removeStory(id: story.id)
                let rest = (stories ?? []).filter { $0.id != story.id }
                if rest.isEmpty { dismiss() } else { stories = rest; index = min(index, rest.count - 1); progress = 0 }
            } catch { self.error = error.userMessage }
        }
    }
}

/// For the poster: who viewed, liked and replied to a story.
struct StoryActivityView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let storyId: UUID
    @State private var people: [StoryActivity]?

    var body: some View {
        List {
            if let people {
                if people.isEmpty {
                    Text("No one has seen this story yet.").foregroundStyle(.secondary)
                }
                ForEach(people) { person in
                    HStack(alignment: .top, spacing: 10) {
                        Avatar(url: person.avatarUrl, name: person.name, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(person.name).font(.subheadline.weight(.semibold))
                                if person.liked { Image(systemName: "heart.fill").font(.caption).foregroundStyle(.red) }
                            }
                            if let reply = person.reply {
                                Text(reply).font(.footnote)
                            } else if let viewed = person.viewedAt {
                                Text(viewed.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { people = (try? await app.backend.storyActivity(storyId: storyId)) ?? [] }
    }
}

/// Pick a photo, add an optional caption, share it as a 24-hour story.
struct StoryComposer: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    var onPosted: () -> Void
    @State private var item: PhotosPickerItem?
    @State private var photo: Data?
    @State private var caption = ""
    @State private var isPosting = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                PhotosPicker(selection: $item, matching: .images) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .background(Theme.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        if let photo, let image = UIImage(data: photo) {
                            Image(uiImage: image).resizable().scaledToFill()
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "photo.badge.plus").font(.largeTitle)
                                Text("Choose a photo").font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .aspectRatio(9.0 / 14.0, contentMode: .fit)
                    .frame(maxHeight: 420)
                }
                .onChange(of: item) { load(item) }
                GlassField(symbol: "text.bubble", isFocused: false) {
                    TextField("Add a caption (optional)", text: $caption)
                        .onChange(of: caption) { if caption.count > 200 { caption = String(caption.prefix(200)) } }
                }
                Text("Stories are shown to people on EasySesh for 24 hours. Keep it about your music or studio – the community guidelines apply.")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                Button { post() } label: { Text(isPosting ? LocalizedStringKey("Posting…") : LocalizedStringKey("Share story")) }
                    .buttonStyle(.primary)
                    .disabled(photo == nil || isPosting)
            }
            .padding()
        }
        .navigationTitle("New story")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .errorAlert($error)
    }

    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            photo = ImageCompressor.jpeg(from: data, maxDimension: 1440)
        }
    }

    private func post() {
        guard let photo else { return }
        isPosting = true
        Task {
            defer { isPosting = false }
            do {
                _ = try await app.backend.postStory(photo: photo, caption: caption.trimmingCharacters(in: .whitespacesAndNewlines))
                onPosted()
                dismiss()
            } catch { self.error = error.userMessage }
        }
    }
}
