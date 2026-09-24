import SwiftUI
import UIKit

/// Sonora design tokens. Warm neutrals, one signal colour (the "REC" light), no gradients.
/// Every colour adapts to light and dark mode.
enum Theme {
    /// Signal red-orange, used sparingly: primary actions, selection, the logo dot.
    static let accent = Color(light: 0xD9431E, dark: 0xFF6A3D)
    /// Page background – the same as system lists and forms, so every screen matches.
    static let background = Color(uiColor: .systemGroupedBackground)
    /// Raised surfaces (cards, input fields, chat bubbles).
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    /// Subtle fills (chips, placeholders).
    static let fill = Color(uiColor: .tertiarySystemFill)
    /// Hairlines.
    static let stroke = Color(light: 0x000000, dark: 0xFFFFFF).opacity(0.08)
    /// Text on top of the accent colour.
    static let onAccent = Color.white
    static let positive = Color(light: 0x2F7D4F, dark: 0x5CC98A)
    static let warning = Color(light: 0xB86E00, dark: 0xF2A93B)

    static let corner: CGFloat = 14
    static let spacing: CGFloat = 16
}

extension Color {
    /// Adaptive colour from two hex values.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Typography

extension Font {
    /// Large editorial headline.
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .default) }
}

struct Eyebrow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

extension View {
    /// Small uppercase label above a section or value.
    func eyebrow() -> some View { modifier(Eyebrow()) }
}

// MARK: - Logo

/// Lowercase wordmark with a small "recording" dot.
struct SonoraLogo: View {
    var size: CGFloat = 28

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.12) {
            Text("sonora")
                .font(.system(size: size, weight: .heavy))
                .tracking(-size * 0.03)
            Circle()
                .fill(Theme.accent)
                .frame(width: size * 0.26, height: size * 0.26)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sonora")
    }
}

// MARK: - Surfaces & buttons

struct CardBackground: ViewModifier {
    var padding: CGFloat = Theme.spacing

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).strokeBorder(Theme.stroke))
    }
}

extension View {
    func card(padding: CGFloat = Theme.spacing) -> some View { modifier(CardBackground(padding: padding)) }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .background(isEnabled ? Theme.accent : Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(isEnabled ? Theme.onAccent : Color.secondary)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
            .foregroundStyle(.primary)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
