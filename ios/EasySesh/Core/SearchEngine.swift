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
        let query = filters.query.trimmingCharacters(in: .whitespaces)
        let equipmentQuery = filters.equipmentQuery.trimmingCharacters(in: .whitespaces).lowercased()

        var results: [StudioResult] = studios.compactMap { studio in
            guard studio.isBookable else { return nil }
            let distance = origin.map { $0.distance(from: studio.location) }

            if !query.isEmpty {
                // Every word must match somewhere: name, place, country (in any app language), gear or genre.
                let haystack = SearchText.normalize(SearchText.haystack(for: studio))
                let words = SearchText.normalize(query).split(separator: " ")
                guard words.allSatisfy({ haystack.contains($0) }) else { return nil }
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
        // Promoted studios (paid ads) are shown first; the chosen sort applies within each group.
        return results.filter(\.studio.isPromoted) + results.filter { !$0.studio.isPromoted }
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

/// Text matching that ignores case, accents and Nordic letters, and knows common city/country names.
enum SearchText {
    /// Languages the app ships in: country names are searchable in all of them.
    static let languages = ["en", "da", "de", "pl", "el", "fr", "es", "it", "sv", "nl"]

    /// English names for cities often written in the local language.
    static let cityAliases: [String: String] = [
        "københavn": "copenhagen", "kobenhavn": "copenhagen", "århus": "aarhus", "aarhus": "aarhus",
        "athína": "athens", "athina": "athens", "αθήνα": "athens", "θεσσαλονίκη": "thessaloniki",
        "warszawa": "warsaw", "kraków": "krakow", "wrocław": "wroclaw", "gdańsk": "gdansk",
        "münchen": "munich", "köln": "cologne", "wien": "vienna", "roma": "rome", "milano": "milan",
        "napoli": "naples", "firenze": "florence", "lisboa": "lisbon", "praha": "prague",
        "göteborg": "gothenburg", "den haag": "the hague", "bruxelles": "brussels", "brussel": "brussels",
    ]

    static func haystack(for studio: Studio) -> String {
        let address = studio.address
        var parts = [studio.name, studio.tagline, address.city, address.area, address.street, address.postalCode,
                     address.country, studio.description]
        parts += countryNames(address.country)
        if let alias = cityAliases[address.city.lowercased()] { parts.append(alias) }
        parts += studio.genres.map(\.title)
        parts += studio.specialTags
        parts += studio.equipment.map(\.name)
        return parts.joined(separator: " ")
    }

    private static var countryCache: [String: [String]] = [:]
    private static let cacheLock = NSLock()

    /// "DK" or "Denmark" → Denmark, Danmark, Dänemark, Dania, Δανία, Danemark, Dinamarca… (cached)
    static func countryNames(_ country: String) -> [String] {
        let trimmed = country.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        cacheLock.lock()
        let cached = countryCache[trimmed]
        cacheLock.unlock()
        if let cached { return cached }
        let names = lookUpCountryNames(trimmed)
        cacheLock.lock()
        countryCache[trimmed] = names
        cacheLock.unlock()
        return names
    }

    private static func lookUpCountryNames(_ trimmed: String) -> [String] {
        var code: String?
        if trimmed.count == 2 {
            code = trimmed.uppercased()
        } else {
            let needle = normalize(trimmed)
            code = Locale.isoRegionCodes.first { candidate in
                languages.contains { language in
                    Locale(identifier: language).localizedString(forRegionCode: candidate).map(normalize) == needle
                }
            }
        }
        guard let code else { return [] }
        return [code] + languages.compactMap { Locale(identifier: $0).localizedString(forRegionCode: code) }
    }

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "ø", with: "o")
            .replacingOccurrences(of: "æ", with: "ae")
            .replacingOccurrences(of: "å", with: "a")
            .replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "ł", with: "l")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}
