import Foundation
import CoreLocation

enum StudioSort: String, CaseIterable, Identifiable {
    case nearest, cheapest, topRated, mostPopular

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nearest: "Nearest"
        case .cheapest: "Cheapest"
        case .topRated: "Top rated"
        case .mostPopular: "Most popular"
        }
    }
}

struct SearchFilters: Equatable {
    var query: String = ""
    var minPrice: Int?
    var maxPrice: Int?
    var maxDistanceKm: Double?
    var genres: Set<Genre> = []
    var facilities: Set<Facility> = []
    var equipmentQuery: String = ""
    var equipmentCategories: Set<EquipmentCategory> = []
    var minRating: Double?
    var availableOn: Date?
    var sessionHours: Int = 2
    var instantBookOnly = false
    var offersMixing = false
    var offersMastering = false
    var engineerIncluded = false

    var activeCount: Int {
        var count = 0
        if minPrice != nil || maxPrice != nil { count += 1 }
        if maxDistanceKm != nil { count += 1 }
        if !genres.isEmpty { count += 1 }
        if !facilities.isEmpty { count += 1 }
        if !equipmentQuery.isEmpty || !equipmentCategories.isEmpty { count += 1 }
        if minRating != nil { count += 1 }
        if availableOn != nil { count += 1 }
        if instantBookOnly { count += 1 }
        if offersMixing || offersMastering || engineerIncluded { count += 1 }
        return count
    }
}

struct StudioResult: Identifiable, Hashable {
    var studio: Studio
    /// Meters from the user, when location is known.
    var distance: Double?
    var id: UUID { studio.id }
}

struct AreaSummary: Hashable {
    var areaName: String
    var studioCount: Int
    var radiusKm: Double
    var priceFrom: Int?
    var currency: String
}

struct SearchEngine {
    var availability = AvailabilityEngine()

    func search(
        studios: [Studio],
        filters: SearchFilters,
        sort: StudioSort,
        origin: CLLocation?,
        busy: [UUID: [DateInterval]] = [:],
        now: Date = .now
    ) -> [StudioResult] {
        let query = filters.query.trimmingCharacters(in: .whitespaces).lowercased()
        let equipmentQuery = filters.equipmentQuery.trimmingCharacters(in: .whitespaces).lowercased()

        var results: [StudioResult] = studios.compactMap { studio in
            guard studio.isBookable else { return nil }
            let distance = origin.map { $0.distance(from: studio.location) }

            if !query.isEmpty {
                let haystack = [studio.name, studio.tagline, studio.address.city, studio.address.area, studio.description]
                    .joined(separator: " ").lowercased()
                guard haystack.contains(query) else { return nil }
            }
            if let min = filters.minPrice, studio.priceFrom < min { return nil }
            if let max = filters.maxPrice, studio.priceFrom > max { return nil }
            if let maxKm = filters.maxDistanceKm, let distance, distance > maxKm * 1000 { return nil }
            if !filters.genres.isEmpty, filters.genres.isDisjoint(with: studio.genres) { return nil }
            if !filters.facilities.isSubset(of: Set(studio.facilities)) { return nil }
            if !filters.equipmentCategories.isSubset(of: Set(studio.equipment.map(\.category))) { return nil }
            if !equipmentQuery.isEmpty,
               !studio.equipment.contains(where: { $0.name.lowercased().contains(equipmentQuery) }) { return nil }
            if let minRating = filters.minRating, studio.ratingAverage < minRating { return nil }
            if filters.instantBookOnly, !studio.bookingPolicy.instantBook { return nil }
            if filters.offersMixing, !studio.offersMixing { return nil }
            if filters.offersMastering, !studio.offersMastering { return nil }
            if filters.engineerIncluded, !studio.sessionTypes.contains(where: \.includesEngineer),
               !studio.addOns.contains(where: { $0.kind == .engineer }) { return nil }
            if let day = filters.availableOn,
               !availability.isAvailable(studio, on: day, hours: filters.sessionHours, busy: busy[studio.id] ?? [], now: now) {
                return nil
            }
            return StudioResult(studio: studio, distance: distance)
        }

        results.sort { lhs, rhs in
            switch sort {
            case .nearest:
                return (lhs.distance ?? .greatestFiniteMagnitude) < (rhs.distance ?? .greatestFiniteMagnitude)
            case .cheapest:
                return lhs.studio.priceFrom < rhs.studio.priceFrom
            case .topRated:
                if lhs.studio.ratingAverage != rhs.studio.ratingAverage {
                    return lhs.studio.ratingAverage > rhs.studio.ratingAverage
                }
                return lhs.studio.reviewCount > rhs.studio.reviewCount
            case .mostPopular:
                return lhs.studio.bookingCount > rhs.studio.bookingCount
            }
        }
        return results
    }

    /// "Athens · 12 studios within 5 km · from €15/hour"
    func areaSummary(results: [StudioResult], areaName: String, radiusKm: Double) -> AreaSummary {
        let inRadius = results.filter { ($0.distance ?? 0) <= radiusKm * 1000 }
        let cheapest = inRadius.min { $0.studio.priceFrom < $1.studio.priceFrom }
        return AreaSummary(
            areaName: areaName,
            studioCount: inRadius.count,
            radiusKm: radiusKm,
            priceFrom: cheapest?.studio.priceFrom,
            currency: cheapest?.studio.currency ?? "EUR"
        )
    }
}
