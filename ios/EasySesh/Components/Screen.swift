import SwiftUI

// MARK: - Screen with collapsing header

private struct EasySeshScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Tab root screen: a large title that fades away while scrolling and hands over to a slim
/// glass bar with a neon hairline. Replaces the system navigation bar on the tab's first screen;
/// pushed screens keep the normal bar with its back button.
struct EasySeshScreen<Trailing: View, Content: View>: View {
    let title: String
    var eyebrow: String?
    let refresh: () async -> Void
    let trailing: Trailing
    let content: Content

    /// 0 while the large title is visible, 1 once it has scrolled away. Only updated in small steps
    /// so scrolling doesn't re-render the whole screen on every frame.
    @State private var collapse: CGFloat = 0
    private let space = "easyseshScreen"

    init(_ title: String, eyebrow: String? = nil, refresh: @escaping () async -> Void,
         @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.eyebrow = eyebrow
        self.refresh = refresh
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                    .opacity(Double(1 - collapse))
                    .scaleEffect(1 - collapse * 0.08, anchor: .bottomLeading)
                content
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
            .background(alignment: .top) {
                GeometryReader { proxy in
                    Color.clear.preference(key: EasySeshScrollOffsetKey.self, value: proxy.frame(in: .named(space)).minY)
                }
                .frame(height: 0)
            }
        }
        .coordinateSpace(name: space)
        .onPreferenceChange(EasySeshScrollOffsetKey.self) { offset in
            let value = min(max((-offset - 24) / 44, 0), 1)
            let stepped = (value * 10).rounded() / 10
            if stepped != collapse { collapse = stepped }
        }
        .refreshable { await Task { await refresh() }.value }
        .overlay(alignment: .top) { compactBar }
        .animation(.easeOut(duration: 0.18), value: collapse)
        .auroraBackground(height: 420)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let eyebrow {
                    Text(localized: eyebrow).eyebrow()
                }
                Text(localized: title)
                    .font(.system(size: 34, weight: .heavy))
                    .tracking(-0.8)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(LinearGradient(colors: [Color.primary, Color.primary.opacity(0.7)], startPoint: .top, endPoint: .bottom))
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) { trailing }
        }
        .padding(.top, 12)
    }

    private var compactBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.neon)
                .frame(width: 8, height: 8)
                .neonGlow(Theme.magenta, radius: 6)
            Text(localized: title)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 8) { trailing }
                .scaleEffect(0.85)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.neon).frame(height: 1).opacity(0.7)
        }
        .opacity(Double(collapse))
        .offset(y: (1 - collapse) * -10)
        .allowsHitTesting(collapse > 0.6)
        .accessibilityHidden(collapse < 0.6)
    }
}

extension EasySeshScreen where Trailing == EmptyView {
    init(_ title: String, eyebrow: String? = nil, refresh: @escaping () async -> Void, @ViewBuilder content: () -> Content) {
        self.init(title, eyebrow: eyebrow, refresh: refresh, trailing: { EmptyView() }, content: content)
    }
}

// MARK: - Building blocks

/// Frosted card with a light glass edge. Looks best over the aurora background.
struct GlassCard: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(padding)
            // A translucent fill looks frosted over the glow but costs far less than a live blur.
            .background(Theme.card.opacity(0.78), in: shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.4), Color.primary.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.8
                )
            )
    }
}

extension View {
    func glassCard(padding: CGFloat = 16, cornerRadius: CGFloat = 22) -> some View {
        modifier(GlassCard(padding: padding, cornerRadius: cornerRadius))
    }
}

/// Rounded gradient square holding an SF Symbol.
struct IconTile: View {
    let symbol: String
    var size: CGFloat = 36
    var colors: [Color] = [Theme.accent, Theme.magenta]

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6))
            .accessibilityHidden(true)
    }
}

enum TilePalette {
    static let signal = [Theme.accent, Theme.magenta]
    static let violet = [Theme.magenta, Theme.violet]
    static let ocean = [Theme.violet, Theme.cyan]
    static let mint = [Theme.cyan, Theme.positive]
    static let muted = [Color.gray.opacity(0.7), Color.gray.opacity(0.45)]
}

/// Round frosted icon, used for header actions.
struct GlassIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 40, height: 40)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(Theme.glassEdge, lineWidth: 0.8))
    }
}

struct GlassIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { GlassIcon(symbol: symbol) }
            .buttonStyle(PressableCardStyle())
            .accessibilityLabel(Text(localized: label))
    }
}

/// "On air" dot with an expanding ring.
struct PulseDot: View {
    var color: Color = Theme.positive
    var isActive = true
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceEffects) private var reduceEffects
    private var reduceMotion: Bool { systemReduceMotion || reduceEffects }

    var body: some View {
        ZStack {
            if isActive {
                Circle()
                    .fill(color.opacity(0.4))
                    .scaleEffect(pulse ? 2.2 : 0.8)
                    .opacity(pulse ? 0 : 0.9)
            }
            Circle().fill(isActive ? color : Color.secondary)
        }
        .frame(width: 10, height: 10)
        .shadow(color: isActive ? color.opacity(0.7) : .clear, radius: 5)
        .onAppear {
            guard isActive, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

/// Section title with an optional count bubble.
struct GlowSectionHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: 8) {
            Text(localized: title).font(.title3.weight(.bold))
            if let count, count > 0 {
                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Theme.neon, in: Capsule())
                    .neonGlow(Theme.magenta, radius: 6)
            }
            Spacer()
        }
        .padding(.top, 6)
    }
}

/// Soft empty state that sits on a glass card.
struct GlassEmptyState: View {
    let title: String
    let symbol: String
    var message: String?

    var body: some View {
        VStack(spacing: 10) {
            IconTile(symbol: symbol, size: 48, colors: TilePalette.violet)
            Text(localized: title).font(.headline)
            if let message {
                Text(localized: message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassCard(padding: 20)
    }
}

extension Date {
    /// "Good morning" / "Good afternoon" / "Good evening".
    var greeting: String {
        switch Calendar.current.component(.hour, from: self) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
}

/// Sign out with a confirmation, shown at the bottom of the profile and studio tabs.
struct SignOutButton: View {
    @Environment(AppState.self) private var app
    @State private var confirm = false

    var body: some View {
        Button {
            confirm = true
        } label: {
            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .glassCard(padding: 14, cornerRadius: 18)
        }
        .buttonStyle(PressableCardStyle())
        .padding(.top, 8)
        .confirmationDialog("Sign out of EasySesh?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await app.signOut() } }
        }
    }
}

// MARK: - Grouped screens (lists & forms)

extension View {
    /// House style for List/Form screens: aurora glow behind frosted rows.
    func easyseshGrouped() -> some View {
        modifier(EasySeshGroupedStyle())
    }
}

private struct EasySeshGroupedStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background {
                ZStack(alignment: .top) {
                    Theme.background
                    AuroraBackground(intensity: 0.8)
                        .frame(height: 340)
                        .mask(LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom))
                }
                .ignoresSafeArea()
            }
            .tint(Theme.accent)
    }
}

/// Segmented control in the house style: a glass capsule with a neon pill that slides between options.
struct GlassSegmentedControl<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let title: (Option) -> String
    var symbol: ((Option) -> String)? = nil
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { selection = option }
                } label: {
                    HStack(spacing: 6) {
                        if let symbol { Image(systemName: symbol(option)).font(.system(size: 13, weight: .bold)) }
                        Text(localized: title(option)).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(isSelected ? Theme.onAccent : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Theme.neon)
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8))
                                .neonGlow(Theme.magenta, radius: 10)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.glassEdge, lineWidth: 0.8))
        .haptic(.selection, trigger: selection)
    }
}
