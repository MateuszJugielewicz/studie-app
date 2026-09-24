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
    var pendingDeepLink: DeepLink?

    var notifications: [AppNotification] = []
    var unreadMessages = 0
    var unreadNotifications: Int { notifications.filter { !$0.isRead }.count }

    var role: UserRole { account?.role ?? .artist }

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
        notifications = (try? await backend.notifications()) ?? notifications
        if let conversations = try? await backend.conversations() {
            unreadMessages = conversations.reduce(0) { $0 + $1.unread(for: role) }
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
