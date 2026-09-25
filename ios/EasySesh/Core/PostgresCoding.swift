import Foundation

/// JSON coding that matches Postgres/PostgREST: snake_case keys and timestamptz strings.
enum PostgresCoding {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = PostgresDate.parse(raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date: \(raw)")
        }
        return decoder
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

/// Postgres/PostgREST timestamp handling ("2026-09-24T10:00:00.123456+00:00" and variants).
enum PostgresDate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ raw: String) -> Date? {
        var value = raw.replacingOccurrences(of: " ", with: "T")
        // Add a timezone when missing (realtime payloads for `timestamp` columns).
        if value.range(of: #"(Z|[+-]\d{2}(:?\d{2})?)$"#, options: .regularExpression) == nil { value += "Z" }
        // Normalise "+00" to "+00:00".
        if let range = value.range(of: #"[+-]\d{2}$"#, options: .regularExpression) {
            let offset = String(value[range]) + ":00"
            value.replaceSubrange(range, with: offset)
        }
        // ISO8601DateFormatter supports at most millisecond precision; trim microseconds.
        if let range = value.range(of: #"\.\d+"#, options: .regularExpression) {
            let digits = String(value[range].dropFirst().prefix(3))
            let fraction = "." + digits.padding(toLength: 3, withPad: "0", startingAt: 0)
            value.replaceSubrange(range, with: fraction)
        }
        return withFraction.date(from: value) ?? plain.date(from: value)
    }

    static func format(_ date: Date) -> String {
        withFraction.string(from: date)
    }
}
