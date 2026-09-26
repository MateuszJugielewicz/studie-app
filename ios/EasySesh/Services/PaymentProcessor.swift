import UIKit
import StripePaymentSheet

enum PaymentOutcome {
    case completed
    case cancelled
}

/// Presents Stripe PaymentSheet (card + Apple Pay) for a PaymentIntent created by the
/// `create-payment-intent` edge function. Google Pay is offered by the same sheet on Android;
/// on iOS the wallet option is Apple Pay.
@MainActor
enum StripePaymentProcessor {
    static func pay(_ info: PaymentIntentInfo) async throws -> PaymentOutcome {
        guard let key = AppConfig.stripePublishableKey else {
            throw BackendError.paymentFailed("Stripe is not configured.")
        }
        STPAPIClient.shared.publishableKey = key

        var configuration = PaymentSheet.Configuration()
        configuration.merchantDisplayName = "EasySesh"
        configuration.applePay = .init(merchantId: AppConfig.applePayMerchantId, merchantCountryCode: "GR")
        configuration.returnURL = "easysesh://stripe-redirect"
        configuration.style = .alwaysDark
        configuration.allowsDelayedPaymentMethods = false
        if let customerId = info.customerId, let ephemeralKey = info.ephemeralKey {
            configuration.customer = .init(id: customerId, ephemeralKeySecret: ephemeralKey)
        }

        let sheet = PaymentSheet(paymentIntentClientSecret: info.clientSecret, configuration: configuration)
        guard let presenter = UIApplication.shared.topViewController else {
            throw BackendError.paymentFailed("Could not present the payment sheet.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            sheet.present(from: presenter) { result in
                switch result {
                case .completed:
                    continuation.resume(returning: .completed)
                case .canceled:
                    continuation.resume(returning: .cancelled)
                case .failed(let error):
                    continuation.resume(throwing: BackendError.paymentFailed(error.localizedDescription))
                }
            }
        }
    }
}

extension UIApplication {
    var topViewController: UIViewController? {
        let scene = connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Turns bank details typed in the app into a one-time Stripe token with the publishable key,
/// so the account number goes straight to Stripe and never through EasySesh's servers.
enum StripeBankTokenizer {
    /// Letters and digits only, upper-cased ("dk50 0040 0440…" → "DK500040…").
    static func normalized(_ iban: String) -> String {
        iban.uppercased().filter { ($0.isLetter || $0.isNumber) && $0.isASCII }
    }

    /// Standard IBAN checksum (mod 97), so typos are caught before asking Stripe.
    static func isValidIBAN(_ iban: String) -> Bool {
        let value = normalized(iban)
        guard (15...34).contains(value.count), value.prefix(2).allSatisfy(\.isLetter) else { return false }
        let rearranged = value.dropFirst(4) + value.prefix(4)
        var remainder = 0
        for character in rearranged {
            let digits = character.isLetter ? String(Int(character.asciiValue! - 55)) : String(character)
            for digit in digits { remainder = (remainder * 10 + Int(String(digit))!) % 97 }
        }
        return remainder == 1
    }

    static func currency(forCountry country: String) -> String {
        switch country {
        case "DK": "dkk"
        case "SE": "sek"
        case "NO": "nok"
        case "GB": "gbp"
        case "PL": "pln"
        case "CH": "chf"
        default: "eur"
        }
    }

    static func token(iban: String, holder: String) async throws -> String {
        guard let key = AppConfig.stripePublishableKey else { throw BackendError.server("Stripe is not configured.") }
        let number = normalized(iban)
        let country = String(number.prefix(2))
        let fields = [
            "bank_account[country]": country,
            "bank_account[currency]": currency(forCountry: country),
            "bank_account[account_number]": number,
            "bank_account[account_holder_name]": holder,
        ]
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        var request = URLRequest(url: URL(string: "https://api.stripe.com/v1/tokens")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields.map { name, value in
            "\(name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&").data(using: .utf8)

        struct Response: Decodable {
            struct Failure: Decodable { let message: String? }
            let id: String?
            let error: Failure?
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(Response.self, from: data)
        if let id = response.id { return id }
        throw BackendError.validation(response.error?.message ?? "Stripe couldn't read these bank details.")
    }
}
