import SwiftUI
import UserNotifications

@main
struct CanopusApp: App {
    @State private var env = AppEnvironment()
    @AppStorage(CanopusAccent.storageKey) private var accent = CanopusAccent.canopus.rawValue

    init() {
        CanopusFonts.register()
        CanopusAppearance.apply()
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    var body: some Scene {
        WindowGroup {
            RootShell()
                .environment(env)
                .preferredColorScheme(.dark)
                .tint(C.accent)
                .font(.ui(15))
                // A new accent theme redraws everything with it.
                .id(accent)
        }
    }
}
