import Foundation
import Observation

enum AppTab: Hashable {
    // Artist
    case discover, bookings
    // Studio
    case dashboard, calendar
    // Shared
    case messages, notifications, profile
}

/// Where a tapped notification should take the user.
enum DeepLink: Hashable {
    case booking(UUID)
    case conversation(UUID)
    case studio(UUID)
}

@MainActor
@Observable
final class AppState {
    let backend: Backend
    let location = LocationService()
    let push: PushNotificationManager

    private(set) var account: UserAccount?
    var artistProfile: ArtistProfile?
    var ownedStudio: Studio?
    private(set) var isBootstrapping = true

    var selectedTab: AppTab = .discover
    /// Set after opening a password-reset link: the user must choose a new password.
    var needsNewPassword = false
    var pendingDeepLink: DeepLink?

    var notifications: [AppNotification] = []
    var unreadMessages = 0
    var unreadNotifications: Int { notifications.filter { !$0.isRead }.count }

    var role: UserRole { account?.role ?? .artist }

    /// Terms version the user must have accepted: the newer of the app's and the server's.
    private(set) var requiredTermsVersion = LegalDocument.currentVersion
    /// Update notes from the EasySesh team, newest first, for this user's role.
    private(set) var changelog: [ChangelogEntry] = []

    var needsTermsAcceptance: Bool {
        guard let account, account.role != .admin else { return false }
        return (account.acceptedTermsVersion ?? "") < requiredTermsVersion
    }

    /// The latest legal update the user hasn't accepted yet, to show what changed.
    var pendingLegalUpdate: ChangelogEntry? {
        changelog.first { $0.isLegalUpdate && $0.version > (account?.acceptedTermsVersion ?? "") }
    }

    /// Changelog entries the user hasn't seen yet (only ones published since they joined).
    var unseenChangelog: [ChangelogEntry] {
        guard let account else { return [] }
        let seen = changelogSeenAt ?? account.createdAt
        return changelog.filter { $0.publishedAt > seen }
    }

    private var changelogSeenAt: Date?

    func markChangelogSeen() {
        guard let account, let newest = changelog.first?.publishedAt else { return }
        changelogSeenAt = newest
        UserDefaults.standard.set(newest, forKey: "easysesh.changelog.seen.\(account.id)")
    }

    /// Warnings from the EasySesh team the user hasn't acknowledged yet.
    private(set) var warnings: [ModerationWarning] = []

    func acknowledgeWarning(_ warning: ModerationWarning) async {
        try? await backend.acknowledgeWarning(id: warning.id)
        warnings.removeAll { $0.id == warning.id }
    }

    /// Checks for new update notes, legal updates and warnings.
    func refreshUpdates() async {
        guard let account else { return }
        if account.role != .admin { warnings = (try? await backend.unacknowledgedWarnings()) ?? warnings }
        changelogSeenAt = UserDefaults.standard.object(forKey: "easysesh.changelog.seen.\(account.id)") as? Date
        if let version = try? await backend.currentTermsVersion() {
            requiredTermsVersion = LegalDocument.newest(LegalDocument.currentVersion, version)
        }
        if let entries = try? await backend.changelog() {
            changelog = entries.filter { $0.isFor(account.role) }
        }
    }

    init(backend: Backend) {
        self.backend = backend
        self.push = PushNotificationManager()
        push.onDeepLink = { [weak self] link in self?.open(link) }
        push.onToken = { [weak self] token in
            Task { try? await self?.backend.registerPushToken(token) }
        }
    }

    static func makeDefault() -> AppState {
        AppState(backend: SupabaseBackend())
    }

    // MARK: Session

    /// Opens a link from an auth email (confirmation or password reset).
    func openAuthLink(_ url: URL) async {
        guard let supabase = backend as? SupabaseBackend else { return }
        do {
            let isRecovery = try await supabase.completeAuthLink(url)
            if let account = await backend.restoreSession() { await didAuthenticate(account) }
            needsNewPassword = isRecovery
        } catch {
            supabase.handle(url: url)
        }
    }

    func bootstrap() async {
        defer { isBootstrapping = false }
        if let account = await backend.restoreSession() {
            await didAuthenticate(account)
        }
    }

    func didAuthenticate(_ account: UserAccount) async {
        self.account = account
        selectedTab = account.role == .studioOwner ? .dashboard : .discover
        switch account.role {
        case .artist:
            artistProfile = try? await backend.artistProfile(id: account.id)
        case .studioOwner:
            ownedStudio = try? await backend.ownedStudio()
        case .admin:
            break
        }
        await refreshUpdates()
        await refreshBadges()
        if account.settings.pushEnabled { await push.requestAuthorization() }
    }

    func updateAccount(_ account: UserAccount) {
        self.account = account
    }

    func signOut() async {
        await backend.signOut()
        account = nil
        artistProfile = nil
        ownedStudio = nil
        notifications = []
        unreadMessages = 0
        push.cancelAllReminders()
    }

    func deleteAccount() async throws {
        try await backend.deleteAccount()
        await signOut()
    }

    // MARK: Badges & notifications

    func refreshBadges() async {
        guard account != nil else { return }
        await refreshUpdates()
        notifications = (try? await backend.notifications()) ?? notifications
        if let conversations = try? await backend.conversations() {
            unreadMessages = conversations.reduce(0) { $0 + $1.badgeCount(for: role) }
        }
        push.setBadge(unreadNotifications)
    }

    func markNotificationRead(_ note: AppNotification) async {
        try? await backend.markNotificationRead(id: note.id)
        if let index = notifications.firstIndex(where: { $0.id == note.id }) { notifications[index].isRead = true }
        push.setBadge(unreadNotifications)
    }

    func markAllNotificationsRead() async {
        try? await backend.markAllNotificationsRead()
        for index in notifications.indices { notifications[index].isRead = true }
        push.setBadge(0)
    }

    // MARK: Navigation

    func open(_ link: DeepLink) {
        switch link {
        case .booking:
            selectedTab = role == .studioOwner ? .calendar : .bookings
        case .conversation:
            selectedTab = .messages
        case .studio:
            selectedTab = role == .studioOwner ? .dashboard : .discover
        }
        pendingDeepLink = link
    }

    func consumeDeepLink(_ matching: (DeepLink) -> Bool) -> DeepLink? {
        guard let link = pendingDeepLink, matching(link) else { return nil }
        pendingDeepLink = nil
        return link
    }

    /// Keeps local "session starts soon" reminders in sync with the artist's bookings.
    func syncReminders(for bookings: [Booking]) {
        guard account?.settings.reminders ?? true else {
            push.cancelAllReminders()
            return
        }
        push.scheduleReminders(for: bookings.filter(\.isUpcoming))
    }
}
