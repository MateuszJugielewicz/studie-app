package com.easysesh.app.core

import com.easysesh.app.model.AddOnKind
import com.easysesh.app.model.EquipmentCategory
import com.easysesh.app.model.Facility
import com.easysesh.app.model.Genre
import com.easysesh.app.model.Interval
import com.easysesh.app.model.Studio
import java.text.Normalizer
import java.time.Instant
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

enum class StudioSort(val title: String) {
    Nearest("Nearest"), Cheapest("Cheapest"), TopRated("Top rated"), MostPopular("Most popular"),
}

data class SearchFilters(
    val query: String = "",
    val minPrice: Int? = null,
    val maxPrice: Int? = null,
    val maxDistanceKm: Double? = null,
    val genres: Set<Genre> = emptySet(),
    val facilities: Set<Facility> = emptySet(),
    val equipmentQuery: String = "",
    val equipmentCategories: Set<EquipmentCategory> = emptySet(),
    val minRating: Double? = null,
    val availableOn: Instant? = null,
    val sessionHours: Int = 2,
    val instantBookOnly: Boolean = false,
    val offersMixing: Boolean = false,
    val offersMastering: Boolean = false,
    val engineerIncluded: Boolean = false,
) {
    val activeCount: Int
        get() {
            var count = 0
            if (minPrice != null || maxPrice != null) count++
            if (maxDistanceKm != null) count++
            if (genres.isNotEmpty()) count++
            if (facilities.isNotEmpty()) count++
            if (equipmentQuery.isNotEmpty() || equipmentCategories.isNotEmpty()) count++
            if (minRating != null) count++
            if (availableOn != null) count++
            if (instantBookOnly) count++
            if (offersMixing || offersMastering || engineerIncluded) count++
            return count
        }
}

data class StudioResult(val studio: Studio, /** Meters from the user, when location is known. */ val distance: Double?) {
    val id get() = studio.id
}

data class AreaSummary(val areaName: String, val studioCount: Int, val radiusKm: Double, val priceFrom: Int?, val currency: String)

class SearchEngine(private val availability: AvailabilityEngine = AvailabilityEngine()) {
    fun search(
        studios: List<Studio>,
        filters: SearchFilters,
        sort: StudioSort,
        origin: GeoPoint?,
        busy: Map<String, List<Interval>> = emptyMap(),
        now: Instant = Instant.now(),
    ): List<StudioResult> {
        val query = filters.query.trim()
        val equipmentQuery = filters.equipmentQuery.trim().lowercase()
        val results = studios.mapNotNull { studio ->
            if (!studio.isBookable) return@mapNotNull null
            val distance = origin?.distanceTo(GeoPoint(studio.latitude, studio.longitude))
            if (query.isNotEmpty()) {
                // Every word must match somewhere: name, place, country (in any app language), gear or genre.
                val haystack = SearchText.normalize(SearchText.haystack(studio))
                val words = SearchText.normalize(query).split(" ").filter { it.isNotEmpty() }
                if (!words.all { haystack.contains(it) }) return@mapNotNull null
            }
            filters.minPrice?.let { if (studio.priceFrom < it) return@mapNotNull null }
            filters.maxPrice?.let { if (studio.priceFrom > it) return@mapNotNull null }
            val maxKm = filters.maxDistanceKm
            if (maxKm != null && distance != null && distance > maxKm * 1000) return@mapNotNull null
            if (filters.genres.isNotEmpty() && filters.genres.intersect(studio.genres.toSet()).isEmpty()) return@mapNotNull null
            if (!studio.facilities.toSet().containsAll(filters.facilities)) return@mapNotNull null
            if (!studio.equipment.map { it.category }.toSet().containsAll(filters.equipmentCategories)) return@mapNotNull null
            if (equipmentQuery.isNotEmpty() && studio.equipment.none { it.name.lowercase().contains(equipmentQuery) }) return@mapNotNull null
            filters.minRating?.let { if (studio.ratingAverage < it) return@mapNotNull null }
            if (filters.instantBookOnly && !studio.bookingPolicy.instantBook) return@mapNotNull null
            if (filters.offersMixing && !studio.offersMixing) return@mapNotNull null
            if (filters.offersMastering && !studio.offersMastering) return@mapNotNull null
            if (filters.engineerIncluded && studio.sessionTypes.none { it.includesEngineer } &&
                studio.addOns.none { it.kind == AddOnKind.Engineer }) return@mapNotNull null
            val day = filters.availableOn
            if (day != null && !availability.isAvailable(studio, day, filters.sessionHours, busy[studio.id] ?: emptyList(), now)) return@mapNotNull null
            StudioResult(studio, distance)
        }
        val sorted = when (sort) {
            StudioSort.Nearest -> results.sortedBy { it.distance ?: Double.MAX_VALUE }
            StudioSort.Cheapest -> results.sortedBy { it.studio.priceFrom }
            StudioSort.TopRated -> results.sortedWith(compareByDescending<StudioResult> { it.studio.ratingAverage }.thenByDescending { it.studio.reviewCount })
            StudioSort.MostPopular -> results.sortedByDescending { it.studio.bookingCount }
        }
        // Promoted studios are shown first; the chosen sort applies within each group.
        return sorted.filter { it.studio.isPromoted } + sorted.filter { !it.studio.isPromoted }
    }

    /** "Athens · 12 studios within 5 km · from €15/hour" */
    fun areaSummary(results: List<StudioResult>, areaName: String, radiusKm: Double): AreaSummary {
        val inRadius = results.filter { (it.distance ?: 0.0) <= radiusKm * 1000 }
        val cheapest = inRadius.minByOrNull { it.studio.priceFrom }
        return AreaSummary(areaName, inRadius.size, radiusKm, cheapest?.studio?.priceFrom, cheapest?.studio?.currency ?: "EUR")
    }
}

/** Text matching that ignores case, accents and Nordic letters, and knows common city/country names. */
object SearchText {
    /** Languages the app ships in: country names are searchable in all of them. */
    val languages = listOf("en", "da", "de", "pl", "el", "fr", "es", "it", "sv", "nl")

    /** English names for cities often written in the local language. */
    private val cityAliases = mapOf(
        "københavn" to "copenhagen", "kobenhavn" to "copenhagen", "århus" to "aarhus", "aarhus" to "aarhus",
        "athína" to "athens", "athina" to "athens", "αθήνα" to "athens", "θεσσαλονίκη" to "thessaloniki",
        "warszawa" to "warsaw", "kraków" to "krakow", "wrocław" to "wroclaw", "gdańsk" to "gdansk",
        "münchen" to "munich", "köln" to "cologne", "wien" to "vienna", "roma" to "rome", "milano" to "milan",
        "napoli" to "naples", "firenze" to "florence", "lisboa" to "lisbon", "praha" to "prague",
        "göteborg" to "gothenburg", "den haag" to "the hague", "bruxelles" to "brussels", "brussel" to "brussels",
    )

    fun haystack(studio: Studio): String {
        val a = studio.address
        val parts = mutableListOf(studio.name, studio.tagline, a.city, a.area, a.street, a.postalCode, a.country, studio.description)
        parts += countryNames(a.country)
        cityAliases[a.city.lowercase()]?.let { parts += it }
        parts += studio.genres.map { it.title }
        parts += studio.specialTags
        parts += studio.equipment.map { it.name }
        return parts.joinToString(" ")
    }

    private val countryCache = ConcurrentHashMap<String, List<String>>()

    /** "DK" or "Denmark" → Denmark, Danmark, Dänemark, Dania, Δανία, Danemark, Dinamarca… (cached) */
    fun countryNames(country: String): List<String> {
        val trimmed = country.trim()
        if (trimmed.isEmpty()) return emptyList()
        return countryCache.getOrPut(trimmed) { lookUp(trimmed) }
    }

    private fun lookUp(trimmed: String): List<String> {
        val code = if (trimmed.length == 2) trimmed.uppercase() else {
            val needle = normalize(trimmed)
            Locale.getISOCountries().firstOrNull { candidate ->
                languages.any { lang -> normalize(Locale("", candidate).getDisplayCountry(Locale(lang))) == needle }
            }
        } ?: return emptyList()
        return listOf(code) + languages.map { Locale("", code).getDisplayCountry(Locale(it)) }
    }

    private val marks = Regex("\\p{Mn}+")

    fun normalize(text: String): String {
        val lowered = text.lowercase()
            .replace("ø", "o").replace("æ", "ae").replace("å", "a").replace("ß", "ss").replace("ł", "l")
        return marks.replace(Normalizer.normalize(lowered, Normalizer.Form.NFD), "")
    }
}
