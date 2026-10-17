package com.easysesh.app.core

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNamingStrategy
import java.time.Instant
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter

/** Same rules as the iOS app's PostgresCoding: snake_case keys, Postgres timestamps. */
@OptIn(ExperimentalSerializationApi::class)
val PostgresJson = Json {
    namingStrategy = JsonNamingStrategy.SnakeCase
    ignoreUnknownKeys = true
    explicitNulls = false
    encodeDefaults = true
    coerceInputValues = true
    isLenient = true
}

/** Postgres/PostgREST timestamps ("2026-09-24 10:00:00.123456+00", "…+00:00", no zone, …). */
object PostgresDate {
    private val zone = Regex("""(Z|[+-]\d{2}(:?\d{2})?)$""")
    private val shortOffset = Regex("""[+-]\d{2}$""")

    fun parse(raw: String): Instant? {
        var value = raw.trim().replace(' ', 'T')
        if (!zone.containsMatchIn(value)) value += "Z"
        shortOffset.find(value)?.let { value = value.substring(0, it.range.first) + it.value + ":00" }
        return runCatching { OffsetDateTime.parse(value, DateTimeFormatter.ISO_OFFSET_DATE_TIME).toInstant() }.getOrNull()
            ?: runCatching { Instant.parse(value) }.getOrNull()
    }

    fun format(instant: Instant): String = DateTimeFormatter.ISO_INSTANT.format(instant)
}

object InstantSerializer : KSerializer<Instant> {
    override val descriptor = PrimitiveSerialDescriptor("PgInstant", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: Instant) = encoder.encodeString(PostgresDate.format(value))
    override fun deserialize(decoder: Decoder): Instant =
        PostgresDate.parse(decoder.decodeString()) ?: Instant.EPOCH
}

typealias PgInstant = @kotlinx.serialization.Serializable(with = InstantSerializer::class) Instant
