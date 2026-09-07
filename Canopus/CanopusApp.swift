import SwiftUI
import UserNotifications

@main
struct CanopusApp: App {
    @State private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(env)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.30, green: 0.58, blue: 0.90))
                .task {
                    _ = try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound, .badge])
                }
        }
    }
}
