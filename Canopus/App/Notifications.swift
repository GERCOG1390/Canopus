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
    var industryDone = UserDefaults.standard.object(forKey: "notify.industryDone") as? Bool ?? true {
        didSet { UserDefaults.standard.set(industryDone, forKey: "notify.industryDone") }
    }
    var structures = UserDefaults.standard.object(forKey: "notify.structures") as? Bool ?? true {
        didSet { UserDefaults.standard.set(structures, forKey: "notify.structures") }
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

/// A timer the game won't announce on a phone: a local notification at a time known in advance (a job
/// done, an extractor stopping, fuel running low). Each kind keeps its own id prefix, so loading the data
/// again replaces what was scheduled before.
struct TimedNotice {
    let id: String
    let date: Date
    let title: String
    let body: String
}

enum TimedNotices {
    /// Replaces every pending notification under `prefix` with `notices` (future ones only); nothing is
    /// scheduled when the setting is off or iOS doesn't allow notifications.
    static func replace(prefix: String, with notices: [TimedNotice], enabled: Bool) async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard enabled, await center.notificationSettings().authorizationStatus == .authorized else { return }
        // iOS keeps at most 64 pending notifications per app: the nearest first.
        for n in notices.filter({ $0.date > .now }).sorted(by: { $0.date < $1.date }).prefix(20) {
            let content = UNMutableNotificationContent()
            content.title = n.title
            content.body = n.body
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: n.date)
            try? await center.add(UNNotificationRequest(identifier: prefix + n.id, content: content,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }
}

/// Shows notifications as banners while the app is open.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
