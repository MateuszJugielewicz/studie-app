import SwiftUI

@main
struct SonoraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState.makeDefault()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .tint(Theme.accent)
                .task {
                    AppDelegate.push = appState.push
                    await appState.bootstrap()
                }
                .onOpenURL { url in
                    (appState.backend as? SupabaseBackend)?.handle(url: url)
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
            Text("Studio approvals, users, bookings, payments and moderation are managed in the Sonora admin dashboard on the web.")
        } actions: {
            Button("Sign out") { Task { await app.signOut() } }
                .buttonStyle(.borderedProminent)
        }
    }
}
