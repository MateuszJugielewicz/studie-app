import SwiftUI

/// A spotlight walkthrough of the tab bar (e.g. right after a studio is approved).
struct TabTour {
    var steps: [TourStep]
    var onFinish: () -> Void
}

struct TourStep: Identifiable {
    let id = UUID()
    /// nil shows a centred welcome card without a spotlight.
    let tab: AppTab?
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
}

struct TabItemAnchorKey: PreferenceKey {
    static var defaultValue: [AppTab: Anchor<CGRect>] = [:]
    static func reduce(value: inout [AppTab: Anchor<CGRect>], nextValue: () -> [AppTab: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension TabTour {
    /// Shown once when a studio is approved.
    static func studioApproved(onFinish: @escaping () -> Void) -> TabTour {
        TabTour(steps: [
            TourStep(tab: nil, symbol: "party.popper.fill",
                     title: "You're live on EasySesh!",
                     message: "Your studio was approved and artists can now book you. Here's a 30-second tour of where everything is."),
            TourStep(tab: .dashboard, symbol: "square.grid.2x2.fill",
                     title: "Dashboard",
                     message: "Earnings, booking requests and upcoming sessions at a glance. Go live or pause your studio here."),
            TourStep(tab: .calendar, symbol: "calendar",
                     title: "Calendar",
                     message: "Every session by day. Block time when the studio is busy so nobody can book it."),
            TourStep(tab: .messages, symbol: "bubble.left.and.bubble.right.fill",
                     title: "Messages",
                     message: "Chat with artists about their bookings, or write to an artist first with the ✎ button."),
            TourStep(tab: .notifications, symbol: "bell.badge.fill",
                     title: "Inbox",
                     message: "Booking requests, reviews and payouts land here and as push notifications."),
            TourStep(tab: .profile, symbol: "building.2.fill",
                     title: "Your studio",
                     message: "Edit your listing, prices and opening hours, set up payouts and change app settings."),
        ], onFinish: onFinish)
    }
}

struct TourOverlay: View {
    let tour: TabTour
    let frames: [AppTab: CGRect]
    @Binding var selection: AppTab

    @State private var index = 0
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceEffects) private var reduceEffects

    private var step: TourStep { tour.steps[index] }
    private var isLast: Bool { index == tour.steps.count - 1 }

    var body: some View {
        let target = step.tab.flatMap { frames[$0] }?.insetBy(dx: -5, dy: -5)
        GeometryReader { proxy in
            let hole = target ?? CGRect(x: proxy.size.width / 2, y: proxy.size.height / 2, width: 0, height: 0)
            ZStack {
                SpotlightShape(hole: hole, cornerRadius: 28)
                    .fill(Color.black.opacity(0.66), style: FillStyle(eoFill: true))
                    .contentShape(Rectangle())
                    .onTapGesture { advance() }

                if let target {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Theme.neon, lineWidth: 2.5)
                        .frame(width: target.width, height: target.height)
                        .scaleEffect(pulse ? 1.1 : 1)
                        .opacity(pulse ? 0.4 : 1)
                        .neonGlow(Theme.magenta, radius: 14)
                        .position(x: target.midX, y: target.midY)
                        .allowsHitTesting(false)
                }

                if step.tab == nil {
                    ConfettiBurst()
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 0.36)
                        .allowsHitTesting(false)
                }

                VStack {
                    Spacer()
                    card
                        .id(index)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.9)),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                        .padding(.horizontal, 20)
                        .padding(.bottom, target.map { max(proxy.size.height - $0.minY + 18, 0) } ?? proxy.size.height * 0.3)
                }
            }
        }
        .ignoresSafeArea(.keyboard)
        .haptic(.selection, trigger: index)
        .onAppear {
            guard !(systemReduceMotion || reduceEffects) else { return }
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulse = true }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconTile(symbol: step.symbol, size: step.tab == nil ? 52 : 42, colors: TilePalette.signal)
                    .symbolEffect(.bounce, value: index)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Step \(index + 1) of \(tour.steps.count)").eyebrow()
                    Text(localized: step.title).font(.title3.weight(.heavy))
                }
            }
            Text(step.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                PageDots(count: tour.steps.count, current: index)
                Spacer()
                if !isLast {
                    Button("Skip") { finish() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 6)
                }
                Button {
                    advance()
                } label: {
                    Text(isLast ? LocalizedStringKey("Let's go") : LocalizedStringKey("Next"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Theme.neon, in: Capsule())
                        .neonGlow(Theme.magenta, radius: 10)
                }
                .buttonStyle(PressableCardStyle())
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.glassEdge, lineWidth: 0.8))
        .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
    }

    private func advance() {
        guard !isLast else { return finish() }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            index += 1
            if let tab = tour.steps[index].tab { selection = tab }
        }
    }

    private func finish() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            if let first = tour.steps.compactMap(\.tab).first { selection = first }
            tour.onFinish()
        }
    }
}

/// Dimmed layer with an animatable rounded hole.
struct SpotlightShape: Shape {
    var hole: CGRect
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(hole.origin.x, hole.origin.y), AnimatablePair(hole.size.width, hole.size.height)) }
        set { hole = CGRect(x: newValue.first.first, y: newValue.first.second, width: newValue.second.first, height: newValue.second.second) }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Extend well past the bounds so the dim also covers the safe areas.
        path.addRect(rect.insetBy(dx: -400, dy: -400))
        if hole.width > 0 && hole.height > 0 {
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: .continuous)
        }
        return path
    }
}

/// One-shot burst of neon confetti.
struct ConfettiBurst: View {
    private struct Piece: Identifiable {
        let id: Int
        let angle: Double
        let distance: CGFloat
        let color: Color
        let spin: Double
        let size: CGSize
    }

    @State private var fired = false
    @Environment(\.reduceEffects) private var reduceEffects
    private let pieces: [Piece] = (0..<36).map { index in
        let colors = [Theme.accent, Theme.magenta, Theme.violet, Theme.cyan, Theme.warning]
        return Piece(
            id: index,
            angle: Double(index) / 36 * 2 * .pi + Double.random(in: -0.15...0.15),
            distance: CGFloat.random(in: 90...190),
            color: colors[index % colors.count],
            spin: Double.random(in: -540...540),
            size: CGSize(width: CGFloat.random(in: 5...9), height: CGFloat.random(in: 10...16))
        )
    }

    var body: some View {
        ZStack {
            if !reduceEffects {
                ForEach(pieces) { piece in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(piece.color)
                        .frame(width: piece.size.width, height: piece.size.height)
                        .rotationEffect(.degrees(fired ? piece.spin : 0))
                        .offset(x: fired ? cos(piece.angle) * piece.distance : 0,
                                y: fired ? sin(piece.angle) * piece.distance + 60 : 0)
                        .opacity(fired ? 0 : 1)
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.6)) { fired = true }
        }
    }
}
