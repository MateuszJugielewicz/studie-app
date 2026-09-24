import SwiftUI
import PhotosUI

struct ArtistTabView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        SonoraTabContainer(selection: $app.selectedTab, tabs: [
            TabSpec(tab: .discover, title: "Discover", symbol: "sparkle.magnifyingglass"),
            TabSpec(tab: .bookings, title: "Sessions", symbol: "calendar"),
            TabSpec(tab: .messages, title: "Messages", symbol: "bubble.left.and.bubble.right", badge: app.unreadMessages),
            TabSpec(tab: .notifications, title: "Inbox", symbol: "bell", badge: app.unreadNotifications),
            TabSpec(tab: .profile, title: "Profile", symbol: "person.crop.circle"),
        ]) { tab in
            switch tab {
            case .bookings: ArtistBookingsView()
            case .messages: ConversationsView()
            case .notifications: NotificationsView()
            case .profile: ArtistProfileView()
            default: DiscoverView()
            }
        }
    }
}

/// First-run profile setup after sign-up.
struct ArtistOnboardingView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        NavigationStack {
            if let account = app.account {
                ArtistProfileEditor(profile: app.artistProfile ?? .empty(id: account.id), isOnboarding: true)
            }
        }
    }
}

struct ArtistProfileView: View {
    @Environment(AppState.self) private var app
    @State private var isEditing = false

    var body: some View {
        NavigationStack {
            List {
                if let profile = app.artistProfile {
                    Section {
                        VStack(spacing: 12) {
                            Avatar(url: profile.avatarUrl, name: profile.artistName, size: 96)
                            HStack(spacing: 6) {
                                Text(profile.artistName).font(.title2.bold())
                                if profile.isVerified { VerifiedBadge() }
                            }
                            Label(profile.city, systemImage: "mappin.and.ellipse").foregroundStyle(.secondary)
                            if !profile.genres.isEmpty {
                                FlowLayout {
                                    ForEach(profile.genres) { Chip(title: $0.title) }
                                }
                            }
                            if !profile.bio.isEmpty {
                                Text(profile.bio).multilineTextAlignment(.center).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    }

                    if !profile.links.isEmpty {
                        Section("Links") {
                            ForEach(profile.links) { link in
                                if let url = URL(string: link.url) {
                                    Link(destination: url) {
                                        Label(link.platform.title, systemImage: link.platform.symbol)
                                    }
                                }
                            }
                        }
                    }

                    if !profile.isVerified {
                        Section {
                            Label("Verified artists get a badge. Link your Spotify or Instagram and our team will verify you.", systemImage: "checkmark.seal")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gearshape") }
                    NavigationLink { BookingHistoryView() } label: { Label("Booking history & receipts", systemImage: "clock.arrow.circlepath") }
                    NavigationLink { LegalListView() } label: { Label("Terms & privacy", systemImage: "doc.text") }
                    NavigationLink { SupportCenterView() } label: { Label("Help & support", systemImage: "questionmark.circle") }
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                Button("Edit") { isEditing = true }
            }
            .sheet(isPresented: $isEditing) {
                if let profile = app.artistProfile {
                    NavigationStack { ArtistProfileEditor(profile: profile, isOnboarding: false) }
                }
            }
        }
    }
}

struct ArtistProfileEditor: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State var profile: ArtistProfile
    let isOnboarding: Bool

    @State private var genres: Set<Genre> = []
    @State private var photoItem: PhotosPickerItem?
    @State private var isSaving = false
    @State private var isUploading = false
    @State private var error: String?

    var body: some View {
        Form {
            if isOnboarding {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Set up your artist profile").font(.title2.bold())
                        Text("Studios see this when you book or message them.").foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                HStack {
                    Spacer()
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            Avatar(url: profile.avatarUrl, name: profile.artistName.isEmpty ? "?" : profile.artistName, size: 96)
                            Image(systemName: isUploading ? "hourglass.circle.fill" : "camera.circle.fill")
                                .font(.title)
                                .foregroundStyle(.white, Theme.accent)
                        }
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section("About you") {
                TextField("Artist name", text: $profile.artistName)
                TextField("City", text: $profile.city)
                TextField("Short bio", text: $profile.bio, axis: .vertical).lineLimit(3...6)
            }

            Section("Genres") {
                ChipPicker(items: Genre.allCases, selection: $genres, title: { $0.title })
                    .padding(.vertical, 4)
            }

            Section {
                ForEach(SocialPlatform.allCases) { platform in
                    HStack {
                        Image(systemName: platform.symbol).frame(width: 22).foregroundStyle(Theme.accent)
                        TextField(platform.title, text: linkBinding(platform))
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
            } header: {
                Text("Links")
            } footer: {
                Text("Paste profile links, e.g. https://open.spotify.com/artist/…")
            }
        }
        .navigationTitle(isOnboarding ? "Welcome" : "Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isOnboarding {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            } else {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sign out") { Task { await app.signOut() } }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isOnboarding ? "Continue" : "Save") { save() }
                    .disabled(isSaving || profile.artistName.trimmingCharacters(in: .whitespaces).isEmpty || profile.city.isEmpty)
            }
        }
        .onAppear { genres = Set(profile.genres) }
        .onChange(of: photoItem) { _, item in upload(item) }
        .errorAlert($error)
    }

    private func linkBinding(_ platform: SocialPlatform) -> Binding<String> {
        Binding {
            profile.links.first { $0.platform == platform }?.url ?? ""
        } set: { value in
            profile.links.removeAll { $0.platform == platform }
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { profile.links.append(SocialLink(platform: platform, url: trimmed)) }
        }
    }

    private func upload(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isUploading = true
        Task {
            defer { isUploading = false }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let jpeg = ImageCompressor.jpeg(from: data, maxDimension: 800) else { return }
                profile.avatarUrl = try await app.backend.uploadImage(jpeg, folder: "avatars/\(profile.id.uuidString)")
            } catch { self.error = error.userMessage }
        }
    }

    private func save() {
        isSaving = true
        profile.genres = Genre.allCases.filter(genres.contains)
        Task {
            defer { isSaving = false }
            do {
                app.artistProfile = try await app.backend.saveArtistProfile(profile)
                if !isOnboarding { dismiss() }
            } catch { self.error = error.userMessage }
        }
    }
}

enum ImageCompressor {
    static func jpeg(from data: Data, maxDimension: CGFloat, quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: quality)
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @State private var settings = UserSettings()
    @State private var confirmDelete = false
    @State private var error: String?

    var body: some View {
        Form {
            if let account = app.account {
                Section("Account") {
                    InfoRow(symbol: "envelope", title: "Email", value: account.email)
                    InfoRow(symbol: "person", title: "Account type", value: account.role.title)
                }
            }

            Section {
                Toggle("Push notifications", isOn: $settings.pushEnabled)
                Toggle("Email notifications", isOn: $settings.emailEnabled)
            } header: {
                Text("Notifications")
            }

            Section {
                Toggle("Booking updates", isOn: $settings.bookingUpdates)
                Toggle("Messages", isOn: $settings.messages)
                if app.role == .artist {
                    Toggle("Session reminders", isOn: $settings.reminders)
                    Toggle("Review prompts", isOn: $settings.reviewPrompts)
                }
                Toggle("News & offers", isOn: $settings.marketing)
            } header: {
                Text("Notify me about")
            } footer: {
                Text("Payment receipts and security messages are always sent.")
            }

            if app.role == .artist {
                Section("Search") {
                    VStack(alignment: .leading) {
                        Text("Default radius: \(Int(settings.searchRadiusKm)) km")
                        Slider(value: $settings.searchRadiusKm, in: 1...50, step: 1)
                    }
                    Toggle("Use kilometres", isOn: $settings.useMetricUnits)
                    Button("Allow location access") { app.location.requestPermission() }
                        .disabled(app.location.isAuthorized)
                }
            }

            Section {
                NavigationLink { LegalListView() } label: { Label("Terms, privacy & policies", systemImage: "doc.text") }
                if let accepted = app.account?.acceptedTermsAt {
                    InfoRow(symbol: "checkmark.seal", title: "Terms accepted", value: accepted.formatted(date: .abbreviated, time: .omitted))
                }
            } header: {
                Text("Legal")
            }

            Section {
                DataExportButton()
                NavigationLink { SupportCenterView() } label: { Label("Contact us about your data", systemImage: "envelope") }
            } header: {
                Text("Your data")
            } footer: {
                Text("Download a copy of everything Sonora stores about you (GDPR). Deleting your account removes your profile; receipts are kept as required by accounting law.")
            }

            Section {
                Button("Sign out") { Task { await app.signOut() } }
                Button("Delete account", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle("Settings")
        .onAppear { settings = app.account?.settings ?? UserSettings() }
        .onChange(of: settings) { _, newValue in
            Task {
                do {
                    let account = try await app.backend.updateSettings(newValue)
                    app.updateAccount(account)
                    if newValue.pushEnabled { await app.push.requestAuthorization() }
                } catch { self.error = error.userMessage }
            }
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task {
                    do { try await app.deleteAccount() } catch { self.error = error.userMessage }
                }
            }
        } message: {
            Text("Your profile, messages and upcoming bookings will be removed. Receipts are kept for accounting as required by law.")
        }
        .errorAlert($error)
    }
}
