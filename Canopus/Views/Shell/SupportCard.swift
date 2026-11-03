// Supporting Canopus, as the desktop's Support.tsx: a voluntary ISK donation to the author's character in
// the game. Nothing in the app depends on it (CCP's Developer License, section 4.4, allows ISK donations;
// the app is the same for everyone). It is in-game currency sent in the game, not a purchase.

import SwiftUI
import EVEAuth

/// The character donations go to.
let supportAuthor = (id: 92260358, name: "Alexandr Gercog")

struct SupportCard: View {
    @Environment(AppEnvironment.self) private var env
    @State private var status: String?
    @State private var copied = false

    var body: some View {
        Card(String(localized: "Support Canopus")) {
            HStack(spacing: 12) {
                EVECharacterPortrait(characterId: supportAuthor.id, size: 56).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: supportAuthor.name).font(.ui(15, .semibold)).foregroundStyle(C.text)
                    Text("Canopus author").font(.ui(12)).foregroundStyle(C.muted)
                }
            }
            Text("Canopus is free and will stay free — no ads, subscriptions or paid features. If it saves you time or ISK, you can send the author any amount of ISK in the game. Every transfer helps the app grow — thank you!")
                .font(.ui(13)).foregroundStyle(C.text2)
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Tap “Open in game” — the character's card opens in the game client (or find him by name).")
                Text("2. Right-click the portrait → “Give Money”.")
                Text("3. Write “Canopus” in the transfer's reason.")
            }
            .font(.ui(12)).foregroundStyle(C.muted)
            HStack(spacing: 8) {
                if let svc = env.characterStore.selectedService {
                    Button("Open in game") {
                        Task {
                            do {
                                try await svc.openInfoInGame(targetId: supportAuthor.id)
                                status = String(localized: "Opened in the game")
                            } catch {
                                status = String(localized: "The game didn't answer: is the character logged in?")
                            }
                        }
                    }
                    .buttonStyle(.canopusSmall)
                }
                Button(copied ? "Name copied" : "Copy name") {
                    UIPasteboard.general.string = supportAuthor.name
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(2)); copied = false }
                }
                .buttonStyle(.canopusSmall)
            }
            if let status { Text(verbatim: status).font(.ui(11)).foregroundStyle(C.muted) }
            Text("The donation is voluntary: every Canopus feature works the same for everyone.").font(.ui(11)).foregroundStyle(C.faint)
        }
    }
}
