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
        configuration.returnURL = "sonora://stripe-redirect"
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
