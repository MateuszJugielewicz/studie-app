import SwiftUI

/// Device settings for artists and studios: language, look, effects, cache, tutorials.
struct AppSettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(AppPreferences.self) private var preferences
    @State private var cacheSize = AppCache.size
    @State private var confirmClear = false
    @State private var cleared = false

    var body: some View {
        @Bindable var preferences = preferences
        List {
            Section {
                NavigationLink {
                    LanguagePickerView()
                } label: {
                    HStack {
                        SettingsIcon(symbol: "globe", colors: TilePalette.ocean)
                        Text("Language")
                        Spacer()
                        Text("\(preferences.language.flag) \(preferences.language.nativeName)").foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Picker(selection: $preferences.appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                } label: {
                    HStack {
                        SettingsIcon(symbol: "circle.lefthalf.filled", colors: TilePalette.violet)
                        Text("Appearance")
                    }
                }
                Toggle(isOn: $preferences.reduceEffects) {
                    HStack {
                        SettingsIcon(symbol: "sparkles", colors: TilePalette.signal)
                        Text("Reduce visual effects")
                    }
                }
                Toggle(isOn: $preferences.hapticsEnabled) {
                    HStack {
                        SettingsIcon(symbol: "iphone.radiowaves.left.and.right", colors: TilePalette.mint)
                        Text("Haptics")
                    }
                }
            } header: {
                Text("Look & feel")
            } footer: {
                Text("Reduce visual effects turns off moving backgrounds and pulsing animations. It can also save battery.")
            }

            Section {
                HStack {
                    SettingsIcon(symbol: "internaldrive", colors: TilePalette.muted)
                    Text("Cached images & data")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(cacheSize), countStyle: .file))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Button(role: .destructive) {
                    confirmClear = true
                } label: {
                    HStack {
                        SettingsIcon(symbol: "trash", colors: [Color.red, Theme.magenta])
                        Text(cleared ? LocalizedStringKey("Cache cleared") : LocalizedStringKey("Clear cache"))
                    }
                }
                .disabled(cacheSize == 0)
            } header: {
                Text("Storage")
            } footer: {
                Text("Photos are downloaded again when you need them. Your account, bookings and messages are not affected.")
            }

            Section("Tutorials") {
                Button {
                    preferences.hasSeenIntro = false
                } label: {
                    HStack {
                        SettingsIcon(symbol: "play.rectangle.on.rectangle", colors: TilePalette.signal)
                        Text("Show the intro again").foregroundStyle(Color.primary)
                    }
                }
                if app.role == .studioOwner, let studio = app.ownedStudio, studio.status == .approved {
                    Button {
                        preferences.resetTour(studioId: studio.id)
                        app.selectedTab = .dashboard
                    } label: {
                        HStack {
                            SettingsIcon(symbol: "wand.and.stars", colors: TilePalette.violet)
                            Text("Replay the studio tour").foregroundStyle(Color.primary)
                        }
                    }
                }
            }

            Section("About") {
                LabeledContent("Version", value: Self.version)
                NavigationLink { LegalListView() } label: { Text("Terms, privacy & policies") }
            }
        }
        .sonoraGrouped()
        .navigationTitle("App settings")
        .confirmationDialog("Clear cached images and data?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear cache", role: .destructive) {
                AppCache.clear()
                withAnimation {
                    cacheSize = AppCache.size
                    cleared = true
                }
            }
        }
        .onAppear { cacheSize = AppCache.size }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

struct LanguagePickerView: View {
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        List {
            Section {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        withAnimation(.snappy) { preferences.language = language }
                    } label: {
                        HStack(spacing: 12) {
                            Text(language.flag).font(.title2)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(language.nativeName).foregroundStyle(Color.primary)
                                Text(Locale.current.localizedString(forIdentifier: language.rawValue) ?? language.nativeName)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if preferences.language == language {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                }
            } footer: {
                Text("Most text changes right away. A few system texts update the next time you open the app.")
            }
        }
        .sonoraGrouped()
        .navigationTitle("Language")
        .haptic(.selection, trigger: preferences.language)
    }
}

/// Small gradient icon used in settings rows.
struct SettingsIcon: View {
    let symbol: String
    var colors: [Color] = TilePalette.signal

    var body: some View {
        IconTile(symbol: symbol, size: 28, colors: colors)
            .padding(.trailing, 4)
    }
}

/// Choose a new password: from Settings, or after opening a password-reset link.
struct ChangePasswordView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    var isRecovery = false

    @State private var password = ""
    @State private var confirmation = ""
    @State private var isSaving = false
    @State private var saved = false
    @State private var error: String?

    private var problem: String? {
        if password.isEmpty { return nil }
        if let problem = PasswordPolicy.problem(password) { return problem }
        if !confirmation.isEmpty && confirmation != password { return String(localized: "The passwords don't match.") }
        return nil
    }

    private var canSave: Bool {
        !isSaving && PasswordPolicy.problem(password) == nil && password == confirmation
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    IconTile(symbol: saved ? "checkmark.shield.fill" : "key.fill", size: 44, colors: saved ? TilePalette.mint : TilePalette.signal)
                        .contentTransition(.symbolEffect(.replace))
                    Text(isRecovery
                         ? LocalizedStringKey("Choose a new password for your account.")
                         : LocalizedStringKey("Use at least 10 characters with upper- and lowercase letters and a number."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Section {
                SecureField("New password", text: $password)
                    .textContentType(.newPassword)
                SecureField("Repeat new password", text: $confirmation)
                    .textContentType(.newPassword)
            } footer: {
                if let problem {
                    Text(problem).foregroundStyle(Theme.warning)
                }
            }
            Section {
                Button {
                    save()
                } label: {
                    HStack {
                        Spacer()
                        if isSaving { ProgressView() } else { Text(saved ? LocalizedStringKey("Password changed") : LocalizedStringKey("Save new password")).bold() }
                        Spacer()
                    }
                }
                .disabled(!canSave || saved)
            }
        }
        .sonoraGrouped()
        .navigationTitle("Change password")
        .toolbar {
            if isRecovery {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { app.needsNewPassword = false }
                }
            }
        }
        .haptic(.success, trigger: saved)
        .errorAlert($error)
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await app.backend.changePassword(to: password)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { saved = true }
                try? await Task.sleep(for: .seconds(1))
                if isRecovery { app.needsNewPassword = false } else { dismiss() }
            } catch { self.error = error.userMessage }
        }
    }
}
