import SwiftUI

enum Theme {
    static let accent = Color(red: 0.486, green: 0.302, blue: 1.0)
    static let accentSecondary = Color(red: 1.0, green: 0.42, blue: 0.58)
    static let background = Color(red: 0.05, green: 0.05, blue: 0.08)
    static let card = Color(white: 1, opacity: 0.06)
    static let stroke = Color(white: 1, opacity: 0.08)
    static let gradient = LinearGradient(colors: [accent, accentSecondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let corner: CGFloat = 16
}

struct SonoraLogo: View {
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: size * 0.25) {
            Image(systemName: "waveform")
                .font(.system(size: size * 0.9, weight: .bold))
                .foregroundStyle(Theme.gradient)
            Text("SONORA")
                .font(.system(size: size, weight: .black, design: .rounded))
                .tracking(size * 0.12)
        }
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.stroke))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.gradient.opacity(isEnabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
