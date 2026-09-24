import SwiftUI
import AuthenticationServices
import CryptoKit

struct WelcomeView: View {
    @Environment(AppState.self) private var app
    @State private var route: AuthRoute?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    SonoraLogo(size: 26)
                    Spacer()
                }
                .padding(.top, 8)

                Spacer(minLength: 24)

                LevelMeter()
                    .frame(height: 120)
                    .padding(.bottom, 28)

                Text("Studio time,\nbooked in minutes.")
                    .font(.display(40))
                    .tracking(-0.8)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Find rooms, gear and engineers near you. See real prices and availability, book and pay in one place.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)

                Spacer(minLength: 32)

                VStack(spacing: 10) {
                    Button("Find a studio") { route = AuthRoute(mode: .signUp, role: .artist) }
                        .buttonStyle(.primary)
                    Button("List your studio") { route = AuthRoute(mode: .signUp, role: .studioOwner) }
                        .buttonStyle(.secondary)
                    Button {
                        route = AuthRoute(mode: .signIn, role: .artist)
                    } label: {
                        (Text("Already have an account? ").foregroundColor(.secondary) + Text("Sign in").fontWeight(.semibold))
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .auroraBackground(height: 560)
            .navigationDestination(item: $route) { route in
                AuthView(mode: route.mode, role: route.role)
            }
        }
    }
}

/// A live "VU meter": bars breathe like a signal on a mixing desk. Static when Reduce Motion is on.
struct LevelMeter: View {
    private let levels: [CGFloat] = [0.22, 0.35, 0.3, 0.52, 0.44, 0.7, 0.62, 0.9, 0.78, 1.0, 0.84, 0.66, 0.74, 0.5, 0.58, 0.4, 0.46, 0.28, 0.34, 0.18]
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceEffects) private var reduceEffects
    private var reduceMotion: Bool { systemReduceMotion || reduceEffects }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t: CGFloat = reduceMotion ? 0 : CGFloat(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000))
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(levels.indices, id: \.self) { index in
                        let i = CGFloat(index)
                        let wobble: CGFloat = (sin(t * 2.1 + i * 0.7) + sin(t * 3.3 + i * 1.3)) * 0.12
                        let level: CGFloat = min(1, max(0.08, levels[index] + wobble))
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(LinearGradient(colors: [Theme.violet, Theme.magenta, Theme.accent], startPoint: .bottom, endPoint: .top))
                            .opacity(0.35 + level * 0.65)
                            .frame(height: proxy.size.height * level)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .neonGlow(Theme.magenta, radius: 18)
            }
        }
        .accessibilityHidden(true)
    }
}

struct AuthRoute: Hashable, Identifiable {
    enum Mode: Hashable { case signIn, signUp }
    var mode: Mode
    var role: UserRole
    var id: String { "\(mode)-\(role.rawValue)" }
}

struct AuthView: View {
    @Environment(AppState.self) private var app
    @State var mode: AuthRoute.Mode
    @State var role: UserRole

    @State private var email = ""
    @State private var password = ""
    @State private var acceptedTerms = false
    @State private var isWorking = false
    @State private var error: String?
    @State private var info: String?
    @State private var currentNonce: String?
    @State private var legalDocument: LegalDocument?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            if mode == .signUp {
                Section {
                    Picker("I am", selection: $role) {
                        Text("Artist").tag(UserRole.artist)
                        Text("Studio owner").tag(UserRole.studioOwner)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(role == .artist
                         ? "Find and book studios, pay in the app or cash, and chat with studios about your sessions."
                         : "Studio accounts are separate from artist accounts. You get access to studio tools only after our team has reviewed and approved your studio.")
                }
            }

            Section {
                SignInWithAppleButton(mode == .signUp ? .signUp : .signIn) { request in
                    let nonce = Nonce.random()
                    currentNonce = nonce
                    request.requestedScopes = [.email, .fullName]
                    request.nonce = Nonce.sha256(nonce)
                } onCompletion: { result in
                    handleApple(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 48)
                .listRowInsets(EdgeInsets())

                Button {
                    run { try await app.backend.signInWithGoogle(role: role) }
                } label: {
                    HStack {
                        Image(systemName: "g.circle.fill")
                        Text("Continue with Google").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                }
            }

            Section("Or with email") {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(mode == .signUp ? .newPassword : .password)
                if mode == .signUp {
                    if !password.isEmpty, let problem = PasswordPolicy.problem(password) {
                        Text(problem).font(.caption).foregroundStyle(Theme.warning)
                    }
                    Toggle(isOn: $acceptedTerms) {
                        Text(role == .studioOwner
                             ? "I accept the Terms, the Studio Agreement and the Privacy Policy"
                             : "I accept the Terms and the Privacy Policy")
                            .font(.footnote)
                    }
                    FlowLayout(spacing: 14) {
                        ForEach(LegalDocument.required(for: role)) { document in
                            Button(document.title) { legalDocument = document }
                                .font(.caption)
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Section {
                Button {
                    run {
                        if mode == .signUp {
                            return try await app.backend.signUp(email: email, password: password, role: role)
                        }
                        return try await app.backend.signIn(email: email, password: password)
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isWorking { ProgressView() } else { Text(mode == .signUp ? "Create account" : "Sign in").bold() }
                        Spacer()
                    }
                }
                .disabled(!canSubmit)

                if mode == .signIn {
                    Button("Forgot password?") {
                        Task {
                            do {
                                try await app.backend.sendPasswordReset(email: email)
                                info = "Check your inbox for a reset link."
                            } catch { self.error = error.userMessage }
                        }
                    }
                    .disabled(email.isEmpty)
                }
            }

            Section {
                Button(mode == .signUp ? "I already have an account" : "Create a new account") {
                    mode = mode == .signUp ? .signIn : .signUp
                }
            }

        }
        .navigationTitle(mode == .signUp ? "Create account" : "Sign in")
        .sheet(item: $legalDocument) { document in
            NavigationStack { LegalDocumentView(document: document) }
        }
        .errorAlert($error)
        .alert("Email sent", isPresented: Binding(get: { info != nil }, set: { if !$0 { info = nil } })) {
            Button("OK") {}
        } message: { Text(info ?? "") }
    }

    private var canSubmit: Bool {
        !isWorking && email.contains("@") && !password.isEmpty
            && (mode == .signIn || (acceptedTerms && PasswordPolicy.problem(password) == nil))
    }

    private func run(_ action: @escaping () async throws -> UserAccount) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let account = try await action()
                await app.didAuthenticate(account)
            } catch {
                self.error = error.userMessage
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                error = "Apple sign-in did not return a valid token."
                return
            }
            run { try await app.backend.signInWithApple(idToken: token, nonce: nonce, role: role) }
        case .failure(let failure):
            if (failure as? ASAuthorizationError)?.code != .canceled { error = failure.userMessage }
        }
    }
}

enum Nonce {
    static func random(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
