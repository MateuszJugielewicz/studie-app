import SwiftUI

@main
struct SonoraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState.makeDefault()
    @State private var preferences = AppPreferences()

    var body: some Scene {
        WindowGroup {
            Group {
                if preferences.hasSeenIntro {
                    RootView()
                } else {
                    IntroView()
                }
            }
            .animation(.smooth(duration: 0.5), value: preferences.hasSeenIntro)
            .environment(appState)
            .environment(preferences)
            .environment(\.locale, preferences.language.locale)
            .environment(\.reduceEffects, preferences.reduceEffects)
            .environment(\.hapticsEnabled, preferences.hapticsEnabled)
            .preferredColorScheme(preferences.appearance.colorScheme)
            .tint(Theme.accent)
            .task {
                AppDelegate.push = appState.push
                await appState.bootstrap()
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

    var body: some View {
        Group {
            if app.isBootstrapping {
                SplashView()
            } else if let account = app.account, account.role != .admin, account.acceptedTermsVersion != LegalDocument.currentVersion {
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
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            SonoraLogo(size: 44)
        }
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
