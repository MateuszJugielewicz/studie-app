import SwiftUI

/// First launch: pick a language, then a short tour of what the app does.
struct IntroView: View {
    @Environment(AppPreferences.self) private var preferences
    @State private var page = 0

    private let features: [IntroFeature] = [
        IntroFeature(symbol: "sparkle.magnifyingglass", colors: TilePalette.signal,
                     title: "Find your sound", message: "Discover recording studios near you with real prices, gear lists and open slots."),
        IntroFeature(symbol: "calendar.badge.checkmark", colors: TilePalette.violet,
                     title: "Book in seconds", message: "Pick a time, pay securely in the app or in cash at the studio, and get instant confirmation."),
        IntroFeature(symbol: "bubble.left.and.bubble.right.fill", colors: TilePalette.ocean,
                     title: "Talk to the studio", message: "Chat about your session, share references and get reminders before you go."),
        IntroFeature(symbol: "music.mic", colors: TilePalette.mint,
                     title: "Run a studio?", message: "List your rooms, fill your calendar and get paid. Every studio is reviewed before it goes live."),
    ]

    private var pageCount: Int { features.count + 1 }
    private var isLast: Bool { page == pageCount - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SonoraLogo(size: 24)
                Spacer()
                if page > 0 && !isLast {
                    Button("Skip") { finish() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .frame(height: 44)

            TabView(selection: $page) {
                LanguagePage().tag(0)
                ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                    IntroFeaturePage(feature: feature, isCurrent: page == index + 1).tag(index + 1)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack(spacing: 18) {
                PageDots(count: pageCount, current: page)
                Button {
                    if isLast {
                        finish()
                    } else {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { page += 1 }
                    }
                } label: {
                    Text(isLast ? LocalizedStringKey("Get started") : LocalizedStringKey("Continue"))
                }
                .buttonStyle(.primary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .auroraBackground(height: 700, animated: true)
        .haptic(.selection, trigger: page)
    }

    private func finish() {
        withAnimation(.smooth(duration: 0.5)) { preferences.hasSeenIntro = true }
    }
}

struct IntroFeature {
    let symbol: String
    let colors: [Color]
    let title: LocalizedStringKey
    let message: LocalizedStringKey
}

private struct LanguagePage: View {
    @Environment(AppPreferences.self) private var preferences
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome to EasySesh")
                        .font(.system(size: 36, weight: .heavy))
                        .tracking(-0.8)
                    Text("Choose your language. You can change it any time in Settings.")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(AppLanguage.allCases) { language in
                        LanguageCard(language: language, isSelected: preferences.language == language) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { preferences.language = language }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }
}

struct LanguageCard: View {
    let language: AppLanguage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(language.flag).font(.title2)
                Text(language.nativeName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? Theme.onAccent : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .background {
                let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
                if isSelected {
                    shape.fill(Theme.neon).neonGlow(Theme.magenta, radius: 12)
                } else {
                    shape.fill(.ultraThinMaterial)
                        .overlay(shape.strokeBorder(Color.primary.opacity(0.1)))
                }
            }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct IntroFeaturePage: View {
    let feature: IntroFeature
    let isCurrent: Bool
    @State private var appeared = false
    @Environment(\.reduceEffects) private var reduceEffects

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 12)
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: feature.colors.map { $0.opacity(0.35) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 230, height: 230)
                    .blur(radius: 40)
                    .scaleEffect(appeared ? 1 : 0.6)
                Circle()
                    .strokeBorder(LinearGradient(colors: feature.colors + [.clear], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
                    .frame(width: 210, height: 210)
                    .rotationEffect(.degrees(appeared ? 360 : 0))
                    .animation(reduceEffects ? nil : .linear(duration: 18).repeatForever(autoreverses: false), value: appeared)
                Circle()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    .frame(width: 150, height: 150)
                IconTile(symbol: feature.symbol, size: 104, colors: feature.colors)
                    .symbolEffect(.bounce, value: isCurrent)
                    .scaleEffect(appeared ? 1 : 0.4)
                    .rotationEffect(.degrees(appeared ? 0 : -18))
            }
            .frame(height: 260)

            VStack(spacing: 12) {
                Text(feature.title)
                    .font(.system(size: 32, weight: .heavy))
                    .tracking(-0.6)
                    .multilineTextAlignment(.center)
                Text(feature.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 24)
            Spacer(minLength: 12)
        }
        .onChange(of: isCurrent, initial: true) { _, current in
            guard current else { return }
            appeared = false
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.05)) { appeared = true }
        }
    }
}

/// Expanding neon capsule for the current page.
struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AnyShapeStyle(Theme.neon) : AnyShapeStyle(Color.primary.opacity(0.18)))
                    .frame(width: index == current ? 26 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: current)
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}
