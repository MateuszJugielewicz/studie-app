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
                    EasySeshLogo(size: 26)
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
            .auroraBackground(height: 560, animated: true)
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

    @FocusState private var focus: AuthField?
    @State private var showPassword = false

    enum AuthField: Hashable { case email, password }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if mode == .signUp {
                    rolePicker
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                socialButtons
                divider
                fields
                if mode == .signUp {
                    termsRow
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                submitButton
                footer
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: mode)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: role)
        }
        .scrollDismissesKeyboard(.interactively)
        .auroraBackground(height: 520, animated: true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .haptic(.selection, trigger: role)
        .haptic(.selection, trigger: mode)
        .sheet(item: $legalDocument) { document in
            NavigationStack { LegalDocumentView(document: document) }
        }
        .errorAlert($error)
        .alert("Email sent", isPresented: Binding(get: { info != nil }, set: { if !$0 { info = nil } })) {
            Button("OK") {}
        } message: { Text(info ?? "") }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            EasySeshLogo(size: 26)
            Text(mode == .signUp ? LocalizedStringKey("Create your account") : LocalizedStringKey("Welcome back"))
                .font(.system(size: 36, weight: .heavy))
                .tracking(-0.8)
                .contentTransition(.opacity)
                .padding(.top, 14)
            Text(mode == .signUp
                 ? LocalizedStringKey("Book studios or list your own in minutes.")
                 : LocalizedStringKey("Sign in to book, chat and manage your sessions."))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("I am").eyebrow()
            HStack(spacing: 10) {
                RoleCard(title: "Artist", subtitle: "Find & book studios", symbol: "music.mic",
                         colors: TilePalette.signal, isSelected: role == .artist) { role = .artist }
                RoleCard(title: "Studio owner", subtitle: "List your studio", symbol: "building.2.fill",
                         colors: TilePalette.violet, isSelected: role == .studioOwner) { role = .studioOwner }
            }
            Text(role == .artist
                 ? LocalizedStringKey("Find and book studios, pay in the app or cash, and chat with studios about your sessions.")
                 : LocalizedStringKey("Studio accounts are separate from artist accounts. You get access to studio tools only after our team has reviewed and approved your studio."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var socialButtons: some View {
        VStack(spacing: 10) {
            SignInWithAppleButton(mode == .signUp ? .signUp : .signIn) { request in
                let nonce = Nonce.random()
                currentNonce = nonce
                request.requestedScopes = [.email, .fullName]
                request.nonce = Nonce.sha256(nonce)
            } onCompletion: { result in
                handleApple(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 54)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.15), radius: 12, y: 6)

            Button {
                run { try await app.backend.signInWithGoogle(role: role) }
            } label: {
                HStack(spacing: 10) {
                    Text("G")
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundStyle(LinearGradient(colors: [.blue, .red, .yellow, .green], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text("Continue with Google").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(.primary)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.14)))
            }
            .buttonStyle(PressableCardStyle())
        }
    }

    private var divider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
            Text("Or with email").font(.caption.weight(.semibold)).foregroundStyle(.secondary).fixedSize()
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
        }
    }

    private var fields: some View {
        VStack(spacing: 12) {
            GlassField(symbol: "envelope.fill", isFocused: focus == .email) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
            }
            GlassField(symbol: "lock.fill", isFocused: focus == .password) {
                Group {
                    if showPassword {
                        TextField("Password", text: $password)
                    } else {
                        SecureField("Password", text: $password)
                    }
                }
                .textContentType(mode == .signUp ? .newPassword : .password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .password)
                .submitLabel(.go)
                .onSubmit { if canSubmit { submit() } }
                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(.secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showPassword ? "Hide password" : "Show password")
            }
            if mode == .signUp && !password.isEmpty {
                PasswordStrengthMeter(password: password)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if mode == .signIn {
                HStack {
                    Spacer()
                    Button("Forgot password?") {
                        Task {
                            do {
                                try await app.backend.sendPasswordReset(email: email)
                                info = L10n.tr("Check your inbox for a reset link.")
                            } catch { self.error = error.userMessage }
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .disabled(!email.contains("@"))
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: focus)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: password.isEmpty)
    }

    private var termsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                acceptedTerms.toggle()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .strokeBorder(Color.primary.opacity(acceptedTerms ? 0 : 0.25), lineWidth: 1.5)
                            .background(Circle().fill(acceptedTerms ? AnyShapeStyle(Theme.neon) : AnyShapeStyle(Color.clear)))
                        if acceptedTerms {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(.white)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(width: 24, height: 24)
                    .neonGlow(Theme.magenta, radius: 6, active: acceptedTerms)
                    Text(role == .studioOwner
                         ? LocalizedStringKey("I accept the Terms, the Studio Agreement and the Privacy Policy")
                         : LocalizedStringKey("I accept the Terms and the Privacy Policy"))
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: acceptedTerms)
            .haptic(.impact(weight: .light), trigger: acceptedTerms)

            FlowLayout(spacing: 8) {
                ForEach(LegalDocument.required(for: role)) { document in
                    Button {
                        legalDocument = document
                    } label: {
                        Label { Text(localized: document.title) } icon: { Image(systemName: "doc.text") }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 36)
        }
    }

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            ZStack {
                if isWorking {
                    ProgressView().tint(.white)
                } else {
                    HStack(spacing: 8) {
                        Text(mode == .signUp ? LocalizedStringKey("Create account") : LocalizedStringKey("Sign in"))
                        Image(systemName: "arrow.right")
                    }
                }
            }
        }
        .buttonStyle(.primary)
        .disabled(!canSubmit)
        .padding(.top, 4)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Spacer()
            Text(mode == .signUp ? LocalizedStringKey("Already have an account?") : LocalizedStringKey("New to EasySesh?"))
                .foregroundStyle(.secondary)
            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    mode = mode == .signUp ? .signIn : .signUp
                    focus = nil
                }
            } label: {
                Text(mode == .signUp ? LocalizedStringKey("Sign in") : LocalizedStringKey("Create account"))
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.neon)
            }
            Spacer()
        }
        .font(.subheadline)
    }

    private func submit() {
        focus = nil
        run {
            if mode == .signUp {
                return try await app.backend.signUp(email: email, password: password, role: role)
            }
            return try await app.backend.signIn(email: email, password: password)
        }
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

// MARK: - Auth components

/// Selectable card for "Artist" / "Studio owner".
private struct RoleCard: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let symbol: String
    let colors: [Color]
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    IconTile(symbol: symbol, size: 38, colors: isSelected ? colors : TilePalette.muted)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? AnyShapeStyle(Theme.neon) : AnyShapeStyle(Color.secondary.opacity(0.5)))
                        .contentTransition(.symbolEffect(.replace))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.heavy)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isSelected ? AnyShapeStyle(Theme.neon) : AnyShapeStyle(Color.primary.opacity(0.1)), lineWidth: isSelected ? 2 : 1)
            )
            .neonGlow(Theme.magenta, radius: 12, active: isSelected)
            .scaleEffect(isSelected ? 1 : 0.97)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Frosted input row with a leading icon; glows while focused.
struct GlassField<Content: View>: View {
    let symbol: String
    let isFocused: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isFocused ? AnyShapeStyle(Theme.neon) : AnyShapeStyle(Color.secondary))
                .frame(width: 22)
            content()
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(.ultraThinMaterial, in: shape)
        .overlay(
            shape.strokeBorder(isFocused ? AnyShapeStyle(Theme.neon) : AnyShapeStyle(Color.primary.opacity(0.1)), lineWidth: isFocused ? 1.6 : 1)
        )
        .neonGlow(Theme.magenta, radius: 10, active: isFocused)
    }
}

/// Four neon segments that fill up as the password gets stronger.
private struct PasswordStrengthMeter: View {
    let password: String

    private var score: Int {
        var points = 0
        if password.count >= PasswordPolicy.minimumLength { points += 1 }
        if password.count >= 14 { points += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil && password.rangeOfCharacter(from: .letters) != nil { points += 1 }
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil && password.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil { points += 1 }
        return PasswordPolicy.problem(password) == nil ? max(points, 1) : min(points, 1)
    }

    private var label: LocalizedStringKey {
        switch score {
        case 0, 1: "Too weak"
        case 2: "Okay"
        case 3: "Strong"
        default: "Very strong"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index < score ? AnyShapeStyle(Theme.neon) : AnyShapeStyle(Color.primary.opacity(0.1)))
                        .frame(height: 5)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: score)
            HStack {
                Text(label).font(.caption.weight(.bold))
                Spacer()
                if let problem = PasswordPolicy.problem(password) {
                    Text(problem).font(.caption).foregroundStyle(Theme.warning).multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}
