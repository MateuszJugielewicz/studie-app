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
            await loadAvailability(backend)
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

    var body: some View {
        NavigationStack(path: $path) {
            let origin = app.location.effectiveLocation
            let results = model.results(origin: origin)
            let metric = app.account?.settings.useMetricUnits ?? true

            Group {
                if showMap {
                    StudioMapView(results: results, metric: metric) { path.append($0.studio) }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            AreaSummaryCard(summary: model.summary(origin: origin, areaName: app.location.cityName ?? "Athens", radiusKm: app.account?.settings.searchRadiusKm ?? 5))
                            if model.isLoading {
                                ProgressView().padding(40)
                            } else if results.isEmpty {
                                ContentUnavailableView("No studios found", systemImage: "waveform.slash", description: Text("Try widening your filters or search area."))
                                if model.filters.activeCount > 0 {
                                    Button("Clear filters") { model.filters = SearchFilters() }
                                }
                            }
                            ForEach(results) { result in
                                NavigationLink(value: result.studio) {
                                    StudioCard(result: result, metric: metric)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                    .refreshable { await model.load(app.backend) }
                }
            }
            .background(Theme.background)
            .navigationTitle("Find a studio")
            .searchable(text: $model.filters.query, prompt: "Studio, area or city")
            .safeAreaInset(edge: .top) { toolbarRow(count: results.count) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { showMap.toggle() }
                    } label: {
                        Image(systemName: showMap ? "list.bullet" : "map")
                    }
                    .accessibilityLabel(showMap ? "Show list" : "Show map")
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
                await model.load(app.backend)
            }
            .errorAlert($model.error)
        }
    }

    private func toolbarRow(count: Int) -> some View {
        HStack(spacing: 8) {
            Button { showFilters = true } label: {
                Chip(title: model.filters.activeCount > 0 ? "Filters · \(model.filters.activeCount)" : "Filters", symbol: "line.3.horizontal.decrease", isSelected: model.filters.activeCount > 0)
            }
            Menu {
                Picker("Sort", selection: $model.sort) {
                    ForEach(StudioSort.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Chip(title: model.sort.title, symbol: "arrow.up.arrow.down")
            }
            Spacer()
            Text("\(count) studios").font(.footnote).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct AreaSummaryCard: View {
    let summary: AreaSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(summary.areaName, systemImage: "mappin.circle.fill").font(.headline)
            Label("\(summary.studioCount) studios within \(Int(summary.radiusKm)) km", systemImage: "slider.vertical.3")
            if let price = summary.priceFrom {
                Label("From \(Money.format(price, currency: summary.currency))/hour", systemImage: "eurosign.circle")
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.gradient.opacity(0.25), in: RoundedRectangle(cornerRadius: Theme.corner))
    }
}

struct StudioCard: View {
    let result: StudioResult
    var metric = true

    var body: some View {
        let studio = result.studio
        VStack(alignment: .leading, spacing: 0) {
            RemoteImage(url: studio.photoUrls.first)
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .topLeading) {
                    if studio.bookingPolicy.instantBook {
                        Label("Instant book", systemImage: "bolt.fill")
                            .font(.caption.bold())
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(10)
                    }
                }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(studio.name).font(.headline)
                    if studio.isVerified { VerifiedBadge() }
                    Spacer()
                    RatingLabel(rating: studio.ratingAverage, count: studio.reviewCount, compact: true)
                }
                Text(studio.tagline).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                HStack {
                    Label(studio.address.publicArea, systemImage: "mappin")
                    if let distance = result.distance {
                        Text("· \(Distance.format(meters: distance, metric: metric))")
                    }
                    Spacer()
                    Text("From ").foregroundColor(.secondary) + Text(Money.format(studio.priceFrom, currency: studio.currency)).bold() + Text("/h").foregroundColor(.secondary)
                }
                .font(.footnote)
            }
            .padding(12)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.stroke))
    }
}

struct StudioMapView: View {
    let results: [StudioResult]
    let metric: Bool
    let onOpen: (StudioResult) -> Void

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedId: UUID?

    var body: some View {
        Map(position: $position, selection: $selectedId) {
            UserAnnotation()
            ForEach(results) { result in
                Annotation(result.studio.name, coordinate: result.studio.coordinate, anchor: .bottom) {
                    Text(Money.format(result.studio.priceFrom, currency: result.studio.currency))
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(selectedId == result.id ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.black.opacity(0.8)), in: Capsule())
                        .foregroundStyle(.white)
                        .overlay(Capsule().stroke(.white.opacity(0.3)))
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
                    StudioCard(result: selected, metric: metric)
                }
                .buttonStyle(.plain)
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
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
