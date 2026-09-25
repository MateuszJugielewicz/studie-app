import SwiftUI
import PhotosUI

struct ArtistTabView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        EasySeshTabContainer(selection: $app.selectedTab, tabs: [
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
    @State private var pendingStudioLinks = 0

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            EasySeshScreen("Profile", eyebrow: Date.now.greeting, refresh: { await load() }) {
                GlassIconButton(symbol: "pencil", label: "Edit profile") { isEditing = true }
            } content: {
                if let profile = app.artistProfile {
                    hero(profile)
                    stats
                    if !profile.links.isEmpty { links(profile) }
                    if !profile.isVerified { verificationCard }
                    if pendingStudioLinks > 0 {
                        NavigationLink { ArtistPublicProfileView(artistId: profile.id, initial: profile) } label: {
                            HStack(spacing: 12) {
                                IconTile(symbol: "link", size: 36, colors: TilePalette.violet)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("A studio wants to connect").font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                                    Text("Confirm to show it on your profile").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                PulseDot(color: Theme.accent, isActive: true)
                            }
                            .glassCard(padding: 14)
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    if let profile = app.artistProfile {
                        tile("Public profile", "Studio & ratings", "person.text.rectangle.fill", TilePalette.signal) {
                            ArtistPublicProfileView(artistId: profile.id, initial: profile)
                        }
                    }
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
        if let id = app.account?.id, let links = try? await app.backend.artistStudioLinks(artistId: id) {
            pendingStudioLinks = links.filter { !$0.isAccepted }.count
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
                    Text(profile.artistName.isEmpty ? L10n.tr("Artist") : profile.artistName)
                        .font(.system(size: 26, weight: .heavy))
                        .tracking(-0.5)
                    if profile.isVerified { VerifiedBadge() }
                    if profile.hasAdminBadge == true { AdminBadge() }
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
                    if let url = link.resolvedURL {
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

    @FocusState private var focus: EditorField?

    enum EditorField: Hashable { case name, city, bio, link(SocialPlatform) }

    private var canSave: Bool {
        !isSaving && !profile.artistName.trimmingCharacters(in: .whitespaces).isEmpty && !profile.city.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if isOnboarding {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Set up your artist profile")
                            .font(.system(size: 30, weight: .heavy))
                            .tracking(-0.6)
                        Text("Studios see this when you book or message them.").foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }

                avatarPicker

                editorSection("About you") {
                    GlassField(symbol: "person.fill", isFocused: focus == .name) {
                        TextField("Artist name", text: $profile.artistName)
                            .textContentType(.nickname)
                            .focused($focus, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focus = .city }
                    }
                    GlassField(symbol: "mappin.and.ellipse", isFocused: focus == .city) {
                        TextField("City", text: $profile.city)
                            .textContentType(.addressCity)
                            .focused($focus, equals: .city)
                            .submitLabel(.next)
                            .onSubmit { focus = .bio }
                    }
                    bioField
                }

                editorSection("Genres", trailing: genres.isEmpty ? nil : L10n.format("%lld selected", genres.count)) {
                    FlowLayout(spacing: 8) {
                        ForEach(Genre.allCases) { genre in
                            let isOn = genres.contains(genre)
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    if isOn { genres.remove(genre) } else { genres.insert(genre) }
                                }
                            } label: {
                                Chip(title: genre.title, symbol: isOn ? "checkmark" : nil, isSelected: isOn)
                            }
                            .buttonStyle(PressableCardStyle())
                        }
                    }
                    .haptic(.selection, trigger: genres)
                }

                editorSection("Links", footer: "Paste profile links, e.g. https://open.spotify.com/artist/…") {
                    VStack(spacing: 10) {
                        ForEach(SocialPlatform.allCases) { platform in
                            HStack(spacing: 12) {
                                IconTile(symbol: platform.symbol, size: 36, colors: platform.brandColors)
                                GlassField(symbol: "link", isFocused: focus == .link(platform)) {
                                    TextField(platform.title, text: linkBinding(platform))
                                        .keyboardType(.URL)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .focused($focus, equals: .link(platform))
                                }
                            }
                        }
                    }
                }

                Button {
                    save()
                } label: {
                    HStack(spacing: 8) {
                        if isSaving { ProgressView().tint(.white) }
                        Text(isOnboarding ? LocalizedStringKey("Continue") : LocalizedStringKey("Save"))
                    }
                }
                .buttonStyle(.primary)
                .disabled(!canSave)
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: focus)
        }
        .scrollDismissesKeyboard(.interactively)
        .auroraBackground(height: 420)
        .navigationTitle(LocalizedStringKey(isOnboarding ? "Welcome" : "Edit profile"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if !isOnboarding {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            } else {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sign out") { Task { await app.signOut() } }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(LocalizedStringKey(isOnboarding ? "Continue" : "Save")) { save() }
                    .fontWeight(.bold)
                    .disabled(!canSave)
            }
        }
        .onAppear { genres = Set(profile.genres) }
        .onChange(of: photoItem) { _, item in upload(item) }
        .errorAlert($error)
    }

    private var avatarPicker: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack {
                    Circle()
                        .fill(Theme.neon)
                        .frame(width: 136, height: 136)
                        .blur(radius: 20)
                        .opacity(0.5)
                    Avatar(url: profile.avatarUrl, name: profile.artistName.isEmpty ? "?" : profile.artistName, size: 116)
                        .padding(4)
                        .overlay(Circle().strokeBorder(Theme.neon, lineWidth: 3))
                        .overlay {
                            if isUploading {
                                Circle().fill(.black.opacity(0.45)).padding(4)
                                ProgressView().tint(.white)
                            }
                        }
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Theme.neon, in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 2))
                        .offset(x: -4, y: -4)
                }
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityLabel("Change photo")
            Text(profile.artistName.isEmpty ? "Add a photo" : profile.artistName)
                .font(.headline)
                .foregroundStyle(profile.artistName.isEmpty ? Color.secondary : Color.primary)
        }
        .frame(maxWidth: .infinity)
    }

    private var bioField: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let isFocused = focus == .bio
        return VStack(alignment: .trailing, spacing: 4) {
            TextField("Short bio", text: $profile.bio, axis: .vertical)
                .lineLimit(3...8)
                .focused($focus, equals: .bio)
            Text("\(profile.bio.count)/300")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(profile.bio.count > 300 ? Theme.warning : Color.secondary)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: shape)
        .overlay(shape.strokeBorder(isFocused ? AnyShapeStyle(Theme.neon) : AnyShapeStyle(Color.primary.opacity(0.1)), lineWidth: isFocused ? 1.6 : 1))
        .neonGlow(Theme.magenta, radius: 10, active: isFocused)
    }

    private func editorSection<Content: View>(_ title: LocalizedStringKey, trailing: String? = nil, footer: LocalizedStringKey? = nil,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).eyebrow()
                Spacer()
                if let trailing {
                    Text(trailing).font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                }
            }
            content()
            if let footer {
                Text(footer).font(.caption).foregroundStyle(.secondary)
            }
        }
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
        .easyseshGrouped()
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

extension SocialPlatform {

    /// Colours for the platform's icon tile.
    var brandColors: [Color] {
        switch self {
        case .spotify: [Color(red: 0.11, green: 0.73, blue: 0.33), Color(red: 0.05, green: 0.5, blue: 0.25)]
        case .appleMusic: [Color(red: 0.98, green: 0.26, blue: 0.41), Color(red: 0.99, green: 0.44, blue: 0.3)]
        case .instagram: [Color(red: 0.51, green: 0.23, blue: 0.71), Color(red: 0.99, green: 0.35, blue: 0.3)]
        case .tiktok: [Color(red: 0.1, green: 0.1, blue: 0.12), Color(red: 0.0, green: 0.83, blue: 0.87)]
        case .youtube: [Color(red: 1.0, green: 0.2, blue: 0.2), Color(red: 0.75, green: 0.05, blue: 0.05)]
        case .soundcloud: [Color(red: 1.0, green: 0.6, blue: 0.1), Color(red: 1.0, green: 0.33, blue: 0.0)]
        case .website: [Color(red: 0.45, green: 0.4, blue: 1.0), Color(red: 0.25, green: 0.8, blue: 1.0)]
        }
    }
}
