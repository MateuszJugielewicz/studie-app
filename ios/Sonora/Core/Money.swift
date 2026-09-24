import Foundation

enum Money {
    /// Formats minor units, e.g. 1500 EUR -> "€15", 1550 -> "€15.50".
    static func format(_ minorUnits: Int, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = Locale.current
        let isWhole = minorUnits % 100 == 0
        formatter.minimumFractionDigits = isWhole ? 0 : 2
        formatter.maximumFractionDigits = isWhole ? 0 : 2
        let value = Decimal(minorUnits) / 100
        return formatter.string(from: value as NSDecimalNumber) ?? "\(currency) \(value)"
    }

    /// Parses user input like "15", "15.5" or "15,50" into minor units.
    static func parse(_ text: String) -> Int? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let value = Decimal(string: cleaned), value >= 0 else { return nil }
        var result = value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &result, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    /// Integer percentage with half-up rounding.
    static func percent(_ amount: Int, _ percent: Int) -> Int {
        (amount * percent + 50) / 100
    }

    static func editableString(_ minorUnits: Int) -> String {
        minorUnits % 100 == 0 ? "\(minorUnits / 100)" : String(format: "%.2f", Double(minorUnits) / 100)
    }
}

enum Distance {
    static func format(meters: Double, metric: Bool = true) -> String {
        if metric {
            if meters < 1000 { return "\(Int((meters / 10).rounded()) * 10) m" }
            return String(format: "%.1f km", meters / 1000)
        }
        let miles = meters / 1609.344
        return String(format: "%.1f mi", miles)
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    func adding(minutes: Int) -> Date { addingTimeInterval(TimeInterval(minutes * 60)) }
    func adding(hours: Int) -> Date { addingTimeInterval(TimeInterval(hours * 3600)) }
    func adding(days: Int) -> Date { Calendar.current.date(byAdding: .day, value: days, to: self) ?? self }
}
