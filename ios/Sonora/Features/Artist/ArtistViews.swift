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
    @State private var bookings: [Booking] = []

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            SonoraScreen("Profile", eyebrow: Date.now.greeting, refresh: { await load() }) {
                GlassIconButton(symbol: "pencil", label: "Edit profile") { isEditing = true }
            } content: {
                if let profile = app.artistProfile {
                    hero(profile)
                    stats
                    if !profile.links.isEmpty { links(profile) }
                    if !profile.isVerified { verificationCard }
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    tile("Sessions", "History & receipts", "clock.arrow.circlepath", TilePalette.ocean) { BookingHistoryView() }
                    tile("Account", "Notifications & data", "person.crop.circle.fill", TilePalette.muted) { SettingsView() }
                    tile("App settings", "Language, look, storage", "slider.horizontal.3", TilePalette.violet) { AppSettingsView() }
                    tile("Support", "Talk to EasySesh", "questionmark.bubble.fill", [Theme.warning, Theme.accent]) { SupportCenterView() }
                }
                NavigationLink { LegalListView() } label: {
                    HStack(spacing: 12) {
                        IconTile(symbol: "doc.text.fill", size: 32, colors: TilePalette.muted)
                        Text("Terms & privacy").font(.body.weight(.medium)).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .glassCard(padding: 12)
                }
                .buttonStyle(PressableCardStyle())
                SignOutButton()
            }
            .task { await load() }
            .sheet(isPresented: $isEditing) {
                if let profile = app.artistProfile {
                    NavigationStack { ArtistProfileEditor(profile: profile, isOnboarding: false) }
                }
            }
        }
    }

    private func load() async {
        bookings = (try? await app.backend.artistBookings()) ?? bookings
        if let id = app.account?.id, let profile = try? await app.backend.artistProfile(id: id) {
            app.artistProfile = profile
        }
    }

    // MARK: Sections

    private func hero(_ profile: ArtistProfile) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.neon)
                    .frame(width: 124, height: 124)
                    .blur(radius: 18)
                    .opacity(0.55)
                Avatar(url: profile.avatarUrl, name: profile.artistName, size: 104)
                    .padding(4)
                    .overlay(Circle().strokeBorder(Theme.neon, lineWidth: 3))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
            }
            .overlay(alignment: .bottomTrailing) {
                Button { isEditing = true } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Theme.neon, in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 2))
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityLabel("Change photo")
            }

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text(profile.artistName.isEmpty ? "Artist" : profile.artistName)
                        .font(.system(size: 26, weight: .heavy))
                        .tracking(-0.5)
                    if profile.isVerified { VerifiedBadge() }
                }
                if !profile.city.isEmpty {
                    Label(profile.city, systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }

            if !profile.genres.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(profile.genres) { genre in
                        Text(localized: genre.title)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Theme.violet.opacity(0.14), in: Capsule())
                            .foregroundStyle(Theme.violet)
                    }
                }
            }

            if !profile.bio.isEmpty {
                Text(profile.bio)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 20, cornerRadius: 26)
    }

    private var stats: some View {
        let completed = bookings.filter { $0.status == .completed }
        let upcoming = bookings.filter(\.isUpcoming)
        let studios = Set(completed.map(\.studioId)).count
        return HStack(spacing: 10) {
            StatCard(title: "Sessions", value: "\(completed.count)", symbol: "waveform", colors: TilePalette.signal)
            StatCard(title: "Upcoming", value: "\(upcoming.count)", symbol: "calendar", colors: TilePalette.ocean)
            StatCard(title: "Studios", value: "\(studios)", symbol: "building.2.fill", colors: TilePalette.violet)
        }
    }

    private func links(_ profile: ArtistProfile) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(profile.links) { link in
                    if let url = URL(string: link.url) {
                        Link(destination: url) {
                            Label { Text(localized: link.platform.title) } icon: { Image(systemName: link.platform.symbol) }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(Capsule().strokeBorder(Theme.glassEdge, lineWidth: 0.8))
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var verificationCard: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: "checkmark.seal.fill", size: 36, colors: [Color.blue, Theme.cyan])
            VStack(alignment: .leading, spacing: 4) {
                Text("Get verified").font(.subheadline.weight(.bold))
                Text("Verified artists get a badge. Link your Spotify or Instagram and our team will verify you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 14)
    }

    private func tile<Destination: View>(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, _ symbol: String, _ colors: [Color], @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 14) {
                IconTile(symbol: symbol, size: 38, colors: colors)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(padding: 14, cornerRadius: 20)
        }
        .buttonStyle(PressableCardStyle())
        .scrollReveal()
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
        .sonoraGrouped()
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
                Section {
                    HStack(spacing: 14) {
                        Avatar(url: app.artistProfile?.avatarUrl, name: app.artistProfile?.artistName ?? app.ownedStudio?.name ?? account.email, size: 56)
                            .padding(2.5)
                            .overlay(Circle().strokeBorder(Theme.neon, lineWidth: 2.5))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.artistProfile?.artistName ?? app.ownedStudio?.name ?? account.email)
                                .font(.headline).lineLimit(1)
                            Text(account.email).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            Text(localized: account.role.title)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Theme.violet.opacity(0.15), in: Capsule())
                                .foregroundStyle(Theme.violet)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                NavigationLink { AppSettingsView() } label: { row("App settings", "slider.horizontal.3", TilePalette.ocean) }
                NavigationLink { ChangePasswordView() } label: { row("Change password", "key.fill", TilePalette.signal) }
            } footer: {
                Text("Language, appearance, effects and storage on this device.")
            }

            Section {
                Toggle(isOn: $settings.pushEnabled) { row("Push notifications", "bell.badge.fill", TilePalette.signal) }
                Toggle(isOn: $settings.emailEnabled) { row("Email notifications", "envelope.fill", TilePalette.violet) }
            } header: {
                Text("Notifications")
            }

            Section {
                Toggle(isOn: $settings.bookingUpdates) { row("Booking updates", "calendar", TilePalette.ocean) }
                Toggle(isOn: $settings.messages) { row("Messages", "bubble.left.and.bubble.right.fill", TilePalette.mint) }
                if app.role == .artist {
                    Toggle(isOn: $settings.reminders) { row("Session reminders", "alarm.fill", [Theme.warning, Theme.accent]) }
                    Toggle(isOn: $settings.reviewPrompts) { row("Review prompts", "star.bubble.fill", TilePalette.violet) }
                }
                Toggle(isOn: $settings.marketing) { row("News & offers", "megaphone.fill", TilePalette.muted) }
            } header: {
                Text("Notify me about")
            } footer: {
                Text("Payment receipts and security messages are always sent.")
            }

            if app.role == .artist {
                Section("Search") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            row("Default radius", "scope", TilePalette.ocean)
                            Spacer()
                            Text("\(Int(settings.searchRadiusKm)) km")
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                        Slider(value: $settings.searchRadiusKm, in: 1...50, step: 1)
                    }
                    Toggle(isOn: $settings.useMetricUnits) { row("Use kilometres", "ruler.fill", TilePalette.muted) }
                    Button { app.location.requestPermission() } label: {
                        row(app.location.isAuthorized ? "Location allowed" : "Allow location access", "location.fill", TilePalette.mint)
                    }
                    .disabled(app.location.isAuthorized)
                }
            }

            Section {
                NavigationLink { LegalListView() } label: { row("Terms, privacy & policies", "doc.text.fill", TilePalette.muted) }
                if let accepted = app.account?.acceptedTermsAt {
                    HStack {
                        row("Terms accepted", "checkmark.seal.fill", TilePalette.mint)
                        Spacer()
                        Text(accepted.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Legal")
            }

            Section {
                DataExportButton()
                NavigationLink { SupportCenterView() } label: { row("Contact us about your data", "envelope.open.fill", TilePalette.violet) }
            } header: {
                Text("Your data")
            } footer: {
                Text("Download a copy of everything EasySesh stores about you (GDPR). Deleting your account removes your profile; receipts are kept as required by accounting law.")
            }

            Section {
                Button { Task { await app.signOut() } } label: {
                    row("Sign out", "rectangle.portrait.and.arrow.right", TilePalette.muted)
                }
                Button(role: .destructive) { confirmDelete = true } label: {
                    HStack {
                        SettingsIcon(symbol: "trash.fill", colors: [Color.red, Theme.magenta])
                        Text("Delete account").foregroundStyle(.red)
                    }
                }
            }
        }
        .sonoraGrouped()
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

    private func row(_ title: LocalizedStringKey, _ symbol: String, _ colors: [Color]) -> some View {
        HStack {
            SettingsIcon(symbol: symbol, colors: colors)
            Text(title).foregroundStyle(Color.primary)
        }
    }
}
