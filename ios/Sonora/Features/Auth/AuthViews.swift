import SwiftUI
import AuthenticationServices
import CryptoKit

struct WelcomeView: View {
    @Environment(AppState.self) private var app
    @State private var route: AuthRoute?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                RadialGradient(colors: [Theme.accent.opacity(0.45), .clear], center: .top, startRadius: 10, endRadius: 420)
                    .ignoresSafeArea()

                VStack(spacing: 28) {
                    Spacer()
                    SonoraLogo(size: 40)
                    Text("Find the studio.\nBook the session.\nMake the record.")
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()

                    if app.isDemo { DemoBanner() }

                    VStack(spacing: 12) {
                        Button { route = AuthRoute(mode: .signUp, role: .artist) } label: {
                            Label("I'm an artist", systemImage: "music.mic")
                        }
                        .buttonStyle(.primary)

                        Button { route = AuthRoute(mode: .signUp, role: .studioOwner) } label: {
                            Label("I own a studio", systemImage: "slider.vertical.3")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke))
                        }
                        .buttonStyle(.plain)

                        Button("I already have an account") { route = AuthRoute(mode: .signIn, role: .artist) }
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .navigationDestination(item: $route) { route in
                AuthView(mode: route.mode, role: route.role)
            }
        }
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
                .signInWithAppleButtonStyle(.white)
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
                        Text(problem).font(.caption).foregroundStyle(.orange)
                    }
                    Toggle(isOn: $acceptedTerms) {
                        Text(role == .studioOwner
                             ? "I accept the Terms, the Studio Agreement and the Privacy Policy"
                             : "I accept the Terms and the Privacy Policy")
                            .font(.footnote)
                    }
                    HStack(spacing: 16) {
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

            if app.isDemo {
                Section("Demo accounts") {
                    Button("Artist · artist@demo.sonora") { fillDemo("artist@demo.sonora") }
                    Button("Studio · studio@demo.sonora") { fillDemo("studio@demo.sonora") }
                    Text("Password: \(MockData.demoPassword)").font(.footnote).foregroundStyle(.secondary)
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

    private func fillDemo(_ address: String) {
        mode = .signIn
        email = address
        password = MockData.demoPassword
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
