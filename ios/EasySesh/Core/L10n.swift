import Foundation

/// Translations for text built in code (error messages, composed sentences), in the language
/// picked in the app — immediately, not only after the next launch. SwiftUI `Text` views get the
/// language from the environment; this covers plain strings.
enum L10n {
    /// Set by AppPreferences whenever the language changes.
    static var languageCode = "en"
    private static var cache: [String: Bundle] = [:]

    private static var bundle: Bundle? {
        if let cached = cache[languageCode] { return cached }
        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"), let bundle = Bundle(path: path) else { return nil }
        cache[languageCode] = bundle
        return bundle
    }

    /// The translation of `key`, or the key itself (English) when there is none.
    static func tr(_ key: String) -> String {
        guard languageCode != "en", !key.isEmpty, let bundle else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    /// Translates a format key such as "Until %@." and fills in the values.
    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), arguments: args)
    }
}
