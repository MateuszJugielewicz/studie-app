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
    /// Apple Pay needs the merchant ID registered in the Apple Developer account, with Stripe's
    /// certificate (see docs/PAYMENTS.md). Set EASYSESH_APPLE_PAY_ENABLED = NO to hide it until then.
    static var applePayEnabled: Bool { value("EasySeshApplePayEnabled")?.uppercased() != "NO" }
    /// Country of the Stripe account (two letters), used by Apple Pay and Google Pay.
    static var merchantCountry: String { value("EasySeshMerchantCountry") ?? "GR" }

    static let redirectURL = URL(string: "easysesh://auth-callback")!
    /// Public support address (EASYSESH_SUPPORT_EMAIL in App.xcconfig). Without one, the app points
    /// people to in-app support instead.
    static var supportEmail: String? { value("EasySeshSupportEmail") }
    /// Public legal pages, served by the `legal` edge function (also used in App Store Connect).
    static var legalBaseURL: URL? { supabaseURL?.appendingPathComponent("functions/v1/legal") }
    static var termsURL: URL? { legalBaseURL?.appendingPathComponent("terms") }
    static var privacyURL: URL? { legalBaseURL?.appendingPathComponent("privacy") }

    private static func value(_ key: String) -> String? {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
        guard let value, !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }
}
