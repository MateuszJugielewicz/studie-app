import Foundation

/// Build-time configuration injected through `Config/*.xcconfig` → Info.plist.
enum AppConfig {
    static var supabaseURL: URL? {
        guard let raw = value("SonoraSupabaseURL"), !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    static var supabaseAnonKey: String? { value("SonoraSupabaseAnonKey") }
    static var stripePublishableKey: String? { value("SonoraStripePublishableKey") }
    static var applePayMerchantId: String { value("SonoraApplePayMerchantId") ?? "merchant.com.sonora.app" }

    static let redirectURL = URL(string: "sonora://auth-callback")!
    static let supportEmail = "support@sonora.app"
    static let termsURL = URL(string: "https://sonora.app/terms")!
    static let privacyURL = URL(string: "https://sonora.app/privacy")!

    private static func value(_ key: String) -> String? {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
        guard let value, !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }
}
