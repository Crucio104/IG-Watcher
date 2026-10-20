import Foundation
import UserNotifications

/// Servizio per la gestione delle notifiche locali su iOS quando viene perso un follower
public final class NotificationService: Sendable {
    public static let shared = NotificationService()

    private init() {}

    /// Richiede i permessi per inviare notifiche push all'utente
    public func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            return granted
        } catch {
            print("Notification authorization error: \(error)")
            return false
        }
    }

    /// Controlla se le notifiche sono attualmente abilitate
    public func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    /// Invia una notifica per ciascun follower perso (oppure riassuntiva)
    public func notifyLostFollowers(_ lostUsers: [InstagramUser], detectedAt date: Date = Date()) {
        guard !lostUsers.isEmpty else { return }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let dateString = formatter.string(from: date)

        let content = UNMutableNotificationContent()
        content.sound = .default

        if lostUsers.count == 1, let single = lostUsers.first {
            content.title = "📉 Lost Follower"
            content.body = "@\(single.username) unfollowed you (detected on \(dateString))."
        } else {
            content.title = "📉 \(lostUsers.count) Lost Followers"
            let sample = lostUsers.prefix(3).map { "@\($0.username)" }.joined(separator: ", ")
            content.body = "\(sample)\(lostUsers.count > 3 ? " and others..." : "") unfollowed you."
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.0, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification scheduling error: \(error)")
            }
        }
    }
}
