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

/// Soft colour fields drawn with radial gradients (no blur filter, so it's cheap to render).
/// Only drifts when `animated` is set (welcome, intro and sign-in screens); everywhere else it is
/// static so frosted surfaces on top don't have to re-render every frame.
struct AuroraBackground: View {
    var intensity: Double = 1
    var animated = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceEffects) private var reduceEffects
    @Environment(\.colorScheme) private var scheme
    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                blob(Theme.accent, size: w * 1.5)
                    .offset(x: drift ? -w * 0.12 : -w * 0.34, y: drift ? -h * 0.1 : -h * 0.24)
                blob(Theme.magenta, size: w * 1.25)
                    .offset(x: drift ? w * 0.18 : w * 0.38, y: drift ? h * 0.04 : -h * 0.12)
                blob(Theme.violet, size: w * 1.4)
                    .offset(x: drift ? w * 0.14 : -w * 0.16, y: drift ? h * 0.16 : h * 0.28)
                blob(Theme.cyan, size: w * 0.8)
                    .offset(x: drift ? -w * 0.26 : -w * 0.42, y: drift ? h * 0.34 : h * 0.24)
                    .opacity(0.6)
            }
            .frame(width: w, height: h)
            .opacity((scheme == .dark ? 0.6 : 0.36) * intensity)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard animated, !(systemReduceMotion || reduceEffects) else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true }
        }
    }

    private func blob(_ color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color, color.opacity(0.35), color.opacity(0)], center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
    }
}

extension View {
    /// Page background with an aurora glow at the top that fades into the normal background.
    func auroraBackground(height: CGFloat = 380, animated: Bool = false) -> some View {
        background {
            ZStack(alignment: .top) {
                Theme.background
                AuroraBackground(animated: animated)
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
                .opacity(phase.isIdentity ? 1 : 0.6)
                .scaleEffect(phase.isIdentity ? 1 : 0.95)
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
    /// Spotlight tour over the tab bar, shown until finished or skipped.
    var tour: TabTour?
    let content: (AppTab) -> Content

    @State private var visited: Set<AppTab> = []
    @State private var keyboardVisible = false
    /// Bumped when the selected tab is tapped again, rebuilding it at its first page.
    @State private var resets: [AppTab: Int] = [:]

    init(selection: Binding<AppTab>, tour: TabTour? = nil, tabs: [TabSpec], @ViewBuilder content: @escaping (AppTab) -> Content) {
        _selection = selection
        self.tabs = tabs
        self.tour = tour
        self.content = content
    }

    var body: some View {
        // The bar sits below the content (not on top of it) so no page, including pushed
        // screens inside a NavigationStack, ends up hidden behind it.
        VStack(spacing: 0) {
            ZStack {
                ForEach(tabs) { spec in
                    let isSelected = spec.tab == selection
                    if isSelected || visited.contains(spec.tab) {
                        content(spec.tab)
                            .id(resets[spec.tab, default: 0])
                            .opacity(isSelected ? 1 : 0)
                            .allowsHitTesting(isSelected)
                            .accessibilityHidden(!isSelected)
                            .onAppear { _ = visited.insert(spec.tab) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !keyboardVisible {
                SonoraTabBar(selection: $selection, tabs: tabs) { tab in
                    // Tapping the tab you're on takes you back to where that tab starts,
                    // e.g. from a studio page back to Discover.
                    withAnimation(.easeInOut(duration: 0.25)) { resets[tab, default: 0] += 1 }
                }
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity)
                    .background(Theme.background.ignoresSafeArea(edges: .bottom))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: keyboardVisible)
        .overlayPreferenceValue(TabItemAnchorKey.self) { anchors in
            if let tour {
                GeometryReader { proxy in
                    TourOverlay(tour: tour, frames: anchors.mapValues { proxy[$0] }, selection: $selection)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: tour == nil)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
    }
}

struct SonoraTabBar: View {
    @Binding var selection: AppTab
    let tabs: [TabSpec]
    var onReselect: (AppTab) -> Void = { _ in }
    @Namespace private var pill
    @State private var width: CGFloat = 0
    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { spec in
                item(spec)
            }
        }
        .padding(5)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newValue in width = newValue }
            }
        }
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.glassEdge, lineWidth: 0.8))
        .scaleEffect(isDragging ? 1.03 : 1)
        .shadow(color: .black.opacity(isDragging ? 0.3 : 0.22), radius: isDragging ? 28 : 22, y: 10)
        // Slide a finger along the bar to scrub between tabs; the pill follows and stretches.
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    if !isDragging { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isDragging = true } }
                    select(at: value.location.x)
                }
                .onEnded { value in
                    select(at: value.predictedEndLocation.x)
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) { isDragging = false }
                }
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
        .haptic(.selection, trigger: selection)
    }

    private func select(at x: CGFloat) {
        guard width > 0, !tabs.isEmpty else { return }
        let index = min(max(Int(x / (width / CGFloat(tabs.count))), 0), tabs.count - 1)
        let tab = tabs[index].tab
        if tab != selection {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { selection = tab }
        }
    }

    private func item(_ spec: TabSpec) -> some View {
        let isSelected = spec.tab == selection
        return Button {
            guard selection != spec.tab else { return onReselect(spec.tab) }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { selection = spec.tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: spec.symbol)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .symbolVariant(isSelected ? .fill : .none)
                    .symbolEffect(.bounce.down, value: isSelected)
                    .frame(height: 22)
                Text(localized: spec.title)
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
                        .overlay(Capsule().strokeBorder(Color.white.opacity(isDragging ? 0.5 : 0.25), lineWidth: 0.8))
                        .neonGlow(Theme.magenta, radius: isDragging ? 20 : 12)
                        .scaleEffect(x: isDragging ? 1.14 : 1, y: isDragging ? 1.08 : 1)
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
            .anchorPreference(key: TabItemAnchorKey.self, value: .bounds) { [spec.tab: $0] }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spec.badge > 0 ? "\(spec.title), \(spec.badge) unread" : spec.title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
