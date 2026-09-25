import Foundation

/// Legal documents bundled with the app (source: /legal in the repository).
enum LegalDocument: String, CaseIterable, Identifiable {
    case terms
    case privacy
    case cookies
    case refunds = "refund-and-cancellation"
    case studioAgreement = "studio-agreement"
    case communityGuidelines = "community-guidelines"

    /// Bump when a document changes materially; users must accept again.
    static let currentVersion = "2026-09-26"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms: "Terms & Conditions"
        case .privacy: "Privacy Policy"
        case .cookies: "Cookie Policy"
        case .refunds: "Refund & Cancellation Policy"
        case .studioAgreement: "Studio Agreement"
        case .communityGuidelines: "Community Guidelines"
        }
    }

    var symbol: String {
        switch self {
        case .terms: "doc.text"
        case .privacy: "hand.raised"
        case .cookies: "internaldrive"
        case .refunds: "arrow.uturn.backward.circle"
        case .studioAgreement: "building.2"
        case .communityGuidelines: "person.3"
        }
    }

    var markdown: String { markdown(language: "en") }

    /// The document in the app's language (legal/<code>/<name>.md), falling back to English.
    func markdown(language: String) -> String {
        if language != "en",
           let url = Bundle.main.url(forResource: rawValue, withExtension: "md", subdirectory: "legal/\(language)"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: "md", subdirectory: "legal")
            ?? Bundle.main.url(forResource: rawValue, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "# \(title)\n\nThis document could not be loaded. Read it at https://easysesh.app/legal/\(rawValue)"
        }
        return text
    }

    /// Documents a user of the given role must accept.
    static func required(for role: UserRole) -> [LegalDocument] {
        role == .studioOwner ? [.terms, .privacy, .studioAgreement] : [.terms, .privacy]
    }
}

enum PasswordPolicy {
    static let minimumLength = 10
    static var hint: String { L10n.format("At least %lld characters with upper- and lowercase letters and a number.", minimumLength) }

    static func problem(_ password: String) -> String? {
        let ok = password.count >= minimumLength
            && password.contains(where: \.isUppercase)
            && password.contains(where: \.isLowercase)
            && password.contains(where: \.isNumber)
        return ok ? nil : hint
    }
}
