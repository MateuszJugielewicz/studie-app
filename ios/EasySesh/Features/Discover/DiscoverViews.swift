import SwiftUI
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
                        searchField
                        controlsRow(count: results.count)
                        AreaSummaryCard(summary: model.summary(origin: origin, areaName: app.location.cityName ?? String(localized: "Your area"), radiusKm: app.account?.settings.searchRadiusKm ?? 5),
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
                FilterPill(title: model.filters.activeCount > 0 ? String(localized: "Filters · \(model.filters.activeCount)") : String(localized: "Filters"),
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
            Text(isSearching ? "Results" : "Near you").eyebrow()
            Text(isSearching ? String(localized: "\(totalCount) studios") : summary.areaName)
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
                            Text(value.map { "\(Int($0)) km" } ?? "Any").tag(value)
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
