import SwiftUI
import UIKit

// MARK: - Neon palette

extension Theme {
    /// Secondary neon tones that the accent fades into.
    static let magenta = Color(light: 0xE0246F, dark: 0xFF3D8B)
    static let violet = Color(light: 0x6A4DF5, dark: 0x8C73FF)
    static let cyan = Color(light: 0x0FA5D6, dark: 0x3FD8FF)

    /// The "signal" gradient: selection, primary buttons, the logo dot.
    static let neon = LinearGradient(colors: [accent, magenta, violet], startPoint: .leading, endPoint: .trailing)
    /// Thin glass edge used on floating surfaces.
    static let glassEdge = LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom)
}

// MARK: - Aurora

/// Slowly drifting blurred colour fields, animated by Core Animation (no per-frame redraws).
/// Static when Reduce Motion is on.
struct AuroraBackground: View {
    var intensity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                blob(Theme.accent, size: w * 0.9)
                    .offset(x: drift ? -w * 0.12 : -w * 0.34, y: drift ? -h * 0.1 : -h * 0.24)
                blob(Theme.magenta, size: w * 0.75)
                    .offset(x: drift ? w * 0.18 : w * 0.38, y: drift ? h * 0.04 : -h * 0.12)
                blob(Theme.violet, size: w * 0.85)
                    .offset(x: drift ? w * 0.14 : -w * 0.16, y: drift ? h * 0.16 : h * 0.28)
                blob(Theme.cyan, size: w * 0.45)
                    .offset(x: drift ? -w * 0.26 : -w * 0.42, y: drift ? h * 0.34 : h * 0.24)
                    .opacity(0.6)
            }
            .frame(width: w, height: h)
            .blur(radius: 60)
            .opacity((scheme == .dark ? 0.55 : 0.32) * intensity)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true }
        }
    }

    private func blob(_ color: Color, size: CGFloat) -> some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

extension View {
    /// Page background with an aurora glow at the top that fades into the normal background.
    func auroraBackground(height: CGFloat = 380) -> some View {
        background {
            ZStack(alignment: .top) {
                Theme.background
                AuroraBackground()
                    .frame(height: height)
                    .mask(LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom))
            }
            .ignoresSafeArea()
        }
    }

    /// Cards lift in and settle as they scroll into view.
    func scrollReveal() -> some View {
        scrollTransition(.interactive, axis: .vertical) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.55)
                .scaleEffect(phase.isIdentity ? 1 : 0.94)
                .blur(radius: phase.isIdentity ? 0 : 1.5)
        }
    }

    /// Soft coloured glow behind a view.
    func neonGlow(_ color: Color = Theme.accent, radius: CGFloat = 14, active: Bool = true) -> some View {
        shadow(color: active ? color.opacity(0.45) : .clear, radius: radius, y: radius * 0.35)
    }
}

/// Tappable card that sinks slightly under the finger.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// MARK: - Floating tab bar

struct TabSpec: Identifiable {
    let tab: AppTab
    let title: String
    let symbol: String
    var badge: Int = 0
    var id: AppTab { tab }
}

/// Replaces the system tab bar with a floating glass bar. Tabs are created on first visit and kept
/// alive afterwards, so scroll positions and navigation stacks survive switching.
struct SonoraTabContainer<Content: View>: View {
    @Binding var selection: AppTab
    let tabs: [TabSpec]
    @ViewBuilder let content: (AppTab) -> Content

    @State private var visited: Set<AppTab> = []
    @State private var keyboardVisible = false

    var body: some View {
        ZStack {
            ForEach(tabs) { spec in
                let isSelected = spec.tab == selection
                if isSelected || visited.contains(spec.tab) {
                    content(spec.tab)
                        .opacity(isSelected ? 1 : 0)
                        .allowsHitTesting(isSelected)
                        .accessibilityHidden(!isSelected)
                        .onAppear { _ = visited.insert(spec.tab) }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardVisible {
                SonoraTabBar(selection: $selection, tabs: tabs)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: keyboardVisible)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
    }
}

struct SonoraTabBar: View {
    @Binding var selection: AppTab
    let tabs: [TabSpec]
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { spec in
                item(spec)
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.glassEdge, lineWidth: 0.8))
        .shadow(color: .black.opacity(0.22), radius: 22, y: 10)
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func item(_ spec: TabSpec) -> some View {
        let isSelected = spec.tab == selection
        return Button {
            guard selection != spec.tab else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { selection = spec.tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: spec.symbol)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .symbolVariant(isSelected ? .fill : .none)
                    .symbolEffect(.bounce.down, value: isSelected)
                    .frame(height: 22)
                Text(spec.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Theme.onAccent : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Theme.neon)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8))
                        .neonGlow(Theme.magenta, radius: 12)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .overlay(alignment: .top) {
                if spec.badge > 0 {
                    Text(spec.badge > 99 ? "99+" : "\(spec.badge)")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Theme.accent, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
                        .offset(x: 14, y: 2)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: spec.badge)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spec.badge > 0 ? "\(spec.title), \(spec.badge) unread" : spec.title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
