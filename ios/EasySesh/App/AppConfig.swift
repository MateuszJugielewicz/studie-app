import Foundation

/// Build-time configuration injected through `Config/*.xcconfig` → Info.plist.
enum AppConfig {
    static var supabaseURL: URL? {
        guard let raw = value("EasySeshSupabaseURL"), !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    static var supabaseAnonKey: String? { value("EasySeshSupabaseAnonKey") }
    static var stripePublishableKey: String? { value("EasySeshStripePublishableKey") }
    static var applePayMerchantId: String { value("EasySeshApplePayMerchantId") ?? "merchant.com.easysesh.app" }

    static let redirectURL = URL(string: "easysesh://auth-callback")!
    static let supportEmail = "support@easysesh.app"
    static let termsURL = URL(string: "https://easysesh.app/terms")!
    static let privacyURL = URL(string: "https://easysesh.app/privacy")!

    private static func value(_ key: String) -> String? {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
        guard let value, !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }
}
