import SwiftUI
import Observation

/// Languages the app ships in. Text falls back to English where a translation is missing.
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case danish = "da"
    case german = "de"
    case polish = "pl"
    case greek = "el"
    case french = "fr"
    case spanish = "es"
    case italian = "it"
    case swedish = "sv"
    case dutch = "nl"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }

    /// The language's own name, so people can always find theirs.
    var nativeName: String {
        switch self {
        case .english: "English"
        case .danish: "Dansk"
        case .german: "Deutsch"
        case .polish: "Polski"
        case .greek: "Ελληνικά"
        case .french: "Français"
        case .spanish: "Español"
        case .italian: "Italiano"
        case .swedish: "Svenska"
        case .dutch: "Nederlands"
        }
    }

    var flag: String {
        switch self {
        case .english: "🇬🇧"
        case .danish: "🇩🇰"
        case .german: "🇩🇪"
        case .polish: "🇵🇱"
        case .greek: "🇬🇷"
        case .french: "🇫🇷"
        case .spanish: "🇪🇸"
        case .italian: "🇮🇹"
        case .swedish: "🇸🇪"
        case .dutch: "🇳🇱"
        }
    }

    /// Best match for the phone's language, English otherwise.
    static var deviceDefault: AppLanguage {
        for identifier in Locale.preferredLanguages {
            let code = String(identifier.prefix(2))
            if let language = AppLanguage(rawValue: code) { return language }
        }
        return .english
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Device-level app settings (not tied to the account), stored in UserDefaults.
@Observable
final class AppPreferences {
    private let defaults: UserDefaults

    var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            L10n.languageCode = language.rawValue
            // Also used by system-provided text and formatting on the next launch.
            defaults.set([language.rawValue], forKey: "AppleLanguages")
        }
    }

    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    /// Turns off moving backgrounds, pulsing and glow animations.
    var reduceEffects: Bool {
        didSet { defaults.set(reduceEffects, forKey: Keys.reduceEffects) }
    }

    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics) }
    }

    var hasSeenIntro: Bool {
        didSet { defaults.set(hasSeenIntro, forKey: Keys.intro) }
    }

    /// Studios whose "you're approved" tour was finished or skipped.
    private(set) var completedTours: Set<String> {
        didSet { defaults.set(Array(completedTours), forKey: Keys.tours) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedLanguage = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init(rawValue:)) ?? .deviceDefault
        language = savedLanguage
        L10n.languageCode = savedLanguage.rawValue
        appearance = defaults.string(forKey: Keys.appearance).flatMap(AppAppearance.init(rawValue:)) ?? .system
        reduceEffects = defaults.bool(forKey: Keys.reduceEffects)
        hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        hasSeenIntro = defaults.bool(forKey: Keys.intro)
        completedTours = Set(defaults.stringArray(forKey: Keys.tours) ?? [])
    }

    func hasCompletedTour(studioId: UUID) -> Bool { completedTours.contains(studioId.uuidString) }
    func completeTour(studioId: UUID) { completedTours.insert(studioId.uuidString) }
    func resetTour(studioId: UUID) { completedTours.remove(studioId.uuidString) }

    private enum Keys {
        static let language = "pref.language"
        static let appearance = "pref.appearance"
        static let reduceEffects = "pref.reduceEffects"
        static let haptics = "pref.haptics"
        static let intro = "pref.hasSeenIntro"
        static let tours = "pref.completedTours"
    }
}

// MARK: - Environment

private struct ReduceEffectsKey: EnvironmentKey {
    static let defaultValue = false
}

private struct HapticsEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// App setting "Reduce visual effects" (the system Reduce Motion setting is honoured separately).
    var reduceEffects: Bool {
        get { self[ReduceEffectsKey.self] }
        set { self[ReduceEffectsKey.self] = newValue }
    }

    var hapticsEnabled: Bool {
        get { self[HapticsEnabledKey.self] }
        set { self[HapticsEnabledKey.self] = newValue }
    }
}

// MARK: - Cache

enum AppCache {
    /// Bytes used by downloaded images and responses.
    static var size: Int { URLCache.shared.currentDiskUsage + URLCache.shared.currentMemoryUsage }

    static func clear() {
        URLCache.shared.removeAllCachedResponses()
        let tmp = FileManager.default.temporaryDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
    }
}

// MARK: - Haptics

private struct HapticModifier<T: Equatable>: ViewModifier {
    @Environment(\.hapticsEnabled) private var enabled
    let feedback: SensoryFeedback
    let trigger: T
    let condition: ((T, T) -> Bool)?

    func body(content: Content) -> some View {
        content.sensoryFeedback(feedback, trigger: trigger) { old, new in
            enabled && (condition?(old, new) ?? true)
        }
    }
}

extension View {
    /// Haptic feedback that respects the app's haptics setting.
    func haptic<T: Equatable>(_ feedback: SensoryFeedback, trigger: T, condition: ((T, T) -> Bool)? = nil) -> some View {
        modifier(HapticModifier(feedback: feedback, trigger: trigger, condition: condition))
    }
}
