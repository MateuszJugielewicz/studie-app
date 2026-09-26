import SwiftUI

@main
struct EasySeshApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState.makeDefault()
    @State private var preferences = AppPreferences()
    /// The animated "easysesh" splash stays up until the app has loaded (and at least long
    /// enough for its animation to play), then fades out while the app fades in.
    @State private var showSplash = true
    /// Drives the cross-fade: the app underneath is already rendered (and loading its data) while
    /// the splash is on top, then the splash fades out as the app settles into place.
    @State private var revealed = false

    init() {
        NavigationAppearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if preferences.hasSeenIntro {
                        RootView()
                    } else {
                        IntroView()
                    }
                }
                .animation(.smooth(duration: 0.5), value: preferences.hasSeenIntro)
                .scaleEffect(revealed ? 1 : 1.04)
                .allowsHitTesting(revealed)

                if showSplash {
                    AnimatedSplashView()
                        .opacity(revealed ? 0 : 1)
                        .scaleEffect(revealed ? 1.08 : 1)
                        .allowsHitTesting(!revealed)
                        .zIndex(1)
                }
            }
            .environment(appState)
            .environment(preferences)
            .environment(\.locale, preferences.language.locale)
            .environment(\.reduceEffects, preferences.reduceEffects)
            .environment(\.hapticsEnabled, preferences.hapticsEnabled)
            .preferredColorScheme(preferences.appearance.colorScheme)
            .tint(Theme.accent)
            .task {
                AppDelegate.push = appState.push
                let started = Date.now
                await appState.bootstrap()
                // Let the splash animation finish even when loading is instant.
                // The first screen is now built underneath and fetching its data; give it a moment
                // so it's filled in before it's revealed.
                let remaining = max(1.4 - Date.now.timeIntervalSince(started), 0.5)
                try? await Task.sleep(for: .seconds(remaining))
                withAnimation(.easeInOut(duration: 0.8)) { revealed = true }
                try? await Task.sleep(for: .seconds(0.85))
                showSplash = false
                appState.launchFinished = true
            }
            .onOpenURL { url in
                Task { await appState.openAuthLink(url) }
            }
            .sheet(isPresented: $appState.needsNewPassword) {
                NavigationStack { ChangePasswordView(isRecovery: true) }
                    .interactiveDismissDisabled()
            }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if app.isBootstrapping {
                SplashView()
            } else if app.needsTermsAcceptance {
                TermsAcceptanceView()
            } else if let account = app.account {
                switch account.role {
                case .artist:
                    if app.artistProfile?.isComplete == true {
                        ArtistTabView()
                    } else {
                        ArtistOnboardingView()
                    }
                case .studioOwner:
                    StudioOwnerRootView()
                case .admin:
                    AdminInfoView()
                }
            } else {
                WelcomeView()
            }
        }
        .animation(.smooth(duration: 0.45), value: app.account?.id)
        .sheet(item: Binding(
            get: { !app.launchFinished || app.needsTermsAcceptance ? nil : app.warnings.first },
            set: { _ in }
        )) { warning in
            NavigationStack { WarningSheet(warning: warning) }
        }
        .sheet(isPresented: Binding(
            get: { app.launchFinished && !app.needsTermsAcceptance && app.warnings.isEmpty && app.account?.role != .admin && !app.unseenChangelog.isEmpty },
            set: { if !$0 { app.markChangelogSeen() } }
        )) {
            WhatsNewSheet(entries: app.unseenChangelog)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await app.refreshUpdates() } }
        }
    }
}

/// Placeholder behind the animated splash while the session is restored.
struct SplashView: View {
    var body: some View {
        Theme.background.ignoresSafeArea()
    }
}

/// Launch animation: the wordmark fades in from a blur, the neon dot drops in with a bounce and
/// a small equalizer pulses underneath until the app is ready.
struct AnimatedSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceEffects) private var reduceEffects
    @State private var wordmark = false
    @State private var dot = false
    @State private var bars = false
    @State private var glow = false

    private var reduceMotion: Bool { systemReduceMotion || reduceEffects }
    private let barHeights: [CGFloat] = [0.45, 0.8, 1, 0.65, 0.9, 0.5, 0.75]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            // Soft neon glow that breathes behind the logo.
            Circle()
                .fill(Theme.neon)
                .frame(width: 260, height: 260)
                .blur(radius: 90)
                .opacity(glow ? 0.45 : 0.15)
                .scaleEffect(glow ? 1.15 : 0.85)

            VStack(spacing: 22) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("easysesh")
                        .font(.system(size: 46, weight: .heavy))
                        .tracking(-1.4)
                        .opacity(wordmark ? 1 : 0)
                        .blur(radius: wordmark ? 0 : 12)
                        .scaleEffect(wordmark ? 1 : 0.86)
                    Circle()
                        .fill(Theme.neon)
                        .frame(width: 12, height: 12)
                        .neonGlow(Theme.accent, radius: glow ? 14 : 8)
                        .offset(y: dot ? 0 : -60)
                        .opacity(dot ? 1 : 0)
                }

                HStack(alignment: .center, spacing: 5) {
                    ForEach(barHeights.indices, id: \.self) { index in
                        Capsule()
                            .fill(Theme.neon)
                            .frame(width: 4, height: 26 * (bars ? barHeights[index] : 0.2))
                            .animation(
                                reduceMotion ? nil :
                                    .easeInOut(duration: 0.42 + Double(index % 3) * 0.12)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.06),
                                value: bars
                            )
                    }
                }
                .frame(height: 26)
                .opacity(wordmark ? 0.9 : 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("EasySesh")
        .onAppear(perform: start)
    }

    private func start() {
        guard !reduceMotion else {
            wordmark = true; dot = true; bars = true; glow = true
            return
        }
        withAnimation(.easeOut(duration: 0.7)) { wordmark = true }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.35)) { dot = true }
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { glow = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { bars = true }
    }
}

/// Admins use the web dashboard (admin/). The app only points them there.
struct AdminInfoView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ContentUnavailableView {
            Label("Admin account", systemImage: "shield.lefthalf.filled")
        } description: {
            Text("Studio approvals, users, bookings, payments and moderation are managed in the EasySesh admin dashboard on the web.")
        } actions: {
            Button("Sign out") { Task { await app.signOut() } }
                .buttonStyle(.borderedProminent)
        }
    }
}
