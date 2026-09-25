import UIKit
import UserNotifications

/// Remote push (APNs, sent by the `send-push` edge function) plus local session reminders.
@MainActor
final class PushNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    var onToken: ((String) -> Void)?
    var onDeepLink: ((DeepLink) -> Void)?

    private let center = UNUserNotificationCenter.current()
    private nonisolated static let reminderPrefix = "reminder-"

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }

    func didRegister(deviceToken: Data) {
        onToken?(deviceToken.map { String(format: "%02x", $0) }.joined())
    }

    func setBadge(_ count: Int) {
        center.setBadgeCount(count) { _ in }
    }

    /// Shows a notification as a local banner.
    func presentLocal(_ note: AppNotification) {
        let content = UNMutableNotificationContent()
        content.title = note.title
        content.body = note.body
        content.sound = .default
        content.userInfo = Self.userInfo(for: note)
        center.add(UNNotificationRequest(identifier: note.id.uuidString, content: content, trigger: nil))
    }

    // MARK: Session reminders

    func scheduleReminders(for bookings: [Booking]) {
        center.getPendingNotificationRequests { [center] requests in
            let stale = requests.map(\.identifier).filter { $0.hasPrefix(Self.reminderPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)

            for booking in bookings {
                for hoursBefore in [24, 2] {
                    let fireDate = booking.startsAt.addingTimeInterval(TimeInterval(-hoursBefore * 3600))
                    guard fireDate > .now else { continue }
                    let content = UNMutableNotificationContent()
                    content.title = hoursBefore == 24 ? L10n.tr("Session tomorrow") : L10n.tr("Session in 2 hours")
                    content.body = L10n.format("%@ at %@, %@.", booking.sessionTypeName, booking.studioName, booking.startsAt.formatted(date: .omitted, time: .shortened))
                    content.sound = .default
                    content.userInfo = ["booking_id": booking.id.uuidString]
                    let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    let id = "\(Self.reminderPrefix)\(booking.id.uuidString)-\(hoursBefore)"
                    center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                }
            }
        }
    }

    func cancelAllReminders() {
        center.getPendingNotificationRequests { [center] requests in
            center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(Self.reminderPrefix) })
        }
    }

    // MARK: Delegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let link = Self.deepLink(from: info) else { return }
        await MainActor.run { self.onDeepLink?(link) }
    }

    static func userInfo(for note: AppNotification) -> [String: String] {
        var info: [String: String] = [:]
        if let id = note.bookingId { info["booking_id"] = id.uuidString }
        if let id = note.conversationId { info["conversation_id"] = id.uuidString }
        if let id = note.studioId { info["studio_id"] = id.uuidString }
        return info
    }

    nonisolated static func deepLink(from info: [AnyHashable: Any]) -> DeepLink? {
        if let raw = info["conversation_id"] as? String, let id = UUID(uuidString: raw) { return .conversation(id) }
        if let raw = info["booking_id"] as? String, let id = UUID(uuidString: raw) { return .booking(id) }
        if let raw = info["studio_id"] as? String, let id = UUID(uuidString: raw) { return .studio(id) }
        return nil
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var push: PushNotificationManager?

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in Self.push?.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}
}
