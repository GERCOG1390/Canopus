// Notifications: what the pilot turned on (skill training done, radar alerts as the desktop's
// danger / all / off with sound), asking iOS for permission only when one is turned on, and showing
// banners while Canopus is open (the radar runs in the foreground).

import SwiftUI
import UserNotifications

enum RadarNotify: String, CaseIterable {
    case danger, all, off
}

@MainActor
@Observable
final class NotificationSettings {
    static let shared = NotificationSettings()

    var skillDone = UserDefaults.standard.object(forKey: "notify.skillDone") as? Bool ?? true {
        didSet { UserDefaults.standard.set(skillDone, forKey: "notify.skillDone") }
    }
    /// Gate camps, bubbles and smartbombs only; every nearby kill; nothing.
    var radar = RadarNotify(rawValue: UserDefaults.standard.string(forKey: "notify.radar") ?? "") ?? .danger {
        didSet { UserDefaults.standard.set(radar.rawValue, forKey: "notify.radar") }
    }
    var radarSound = UserDefaults.standard.object(forKey: "notify.radarSound") as? Bool ?? true {
        didSet { UserDefaults.standard.set(radarSound, forKey: "notify.radarSound") }
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
