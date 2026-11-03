// Notifications: what the pilot turned on (skill training done), asking iOS for permission only when one
// is turned on, and showing banners while Canopus is open.

import SwiftUI
import UserNotifications

@MainActor
@Observable
final class NotificationSettings {
    static let shared = NotificationSettings()

    var skillDone = UserDefaults.standard.object(forKey: "notify.skillDone") as? Bool ?? true {
        didSet { UserDefaults.standard.set(skillDone, forKey: "notify.skillDone") }
    }
    var piExtractors = UserDefaults.standard.object(forKey: "notify.piExtractors") as? Bool ?? true {
        didSet { UserDefaults.standard.set(piExtractors, forKey: "notify.piExtractors") }
    }
    private(set) var status: UNAuthorizationStatus = .notDetermined

    func refresh() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks iOS once, when the pilot turns a notification on.
    @discardableResult
    func authorize() async -> Bool {
        await refresh()
        if status == .notDetermined {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await refresh()
        }
        return status == .authorized || status == .provisional
    }
}

/// Shows notifications as banners while the app is open.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
