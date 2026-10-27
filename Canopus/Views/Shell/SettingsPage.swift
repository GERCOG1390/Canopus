// Settings: characters (add, switch, remove), the accent theme as on the desktop, the game database.

import AuthenticationServices
import EVEAuth
import SwiftUI

struct SettingsPage: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.webAuthenticationSession) private var webAuthSession
    @AppStorage(CanopusAccent.storageKey) private var accent = CanopusAccent.canopus.rawValue
    @State private var adding = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                charactersCard
                themeCard
                databaseCard
                aboutCard
            }
            .padding(16)
        }
        .navigationTitle("Settings")
    }

    private var charactersCard: some View {
        Card(title: "Characters", actions: {
            Button {
                Task { await addCharacter() }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.canopusSmall)
            .disabled(adding)
        }) {
            let store = env.characterStore
            if store.characters.isEmpty {
                Text("Sign in with EVE Online to see your character, skills, wallet and more.")
                    .font(.ui(14))
                    .foregroundStyle(C.muted)
            }
            ForEach(store.characters, id: \.characterId) { c in
                HStack(spacing: 12) {
                    EVECharacterPortrait(characterId: c.characterId, size: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text(c.characterName)
                        .font(.ui(15, .medium))
                        .foregroundStyle(C.text)
                    Spacer()
                    if store.selectedId == c.characterId {
                        Pill(text: "Active", color: C.good)
                    } else {
                        Button("Select") { store.selectedId = c.characterId }
                            .buttonStyle(.canopusSmall)
                    }
                    Button(role: .destructive) {
                        store.removeCharacter(id: c.characterId)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(CanopusButtonStyle(kind: .danger, small: true))
                }
            }
            if let error {
                Text(error).font(.ui(13)).foregroundStyle(C.bad)
            }
        }
    }

    private var themeCard: some View {
        Card("Accent theme") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(CanopusAccent.allCases) { a in
                    Button {
                        accent = a.rawValue
                    } label: {
                        HStack(spacing: 8) {
                            Circle().fill(a.color).frame(width: 14, height: 14)
                            Text(a.title).font(.ui(13))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.canopusGhost)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(accent == a.rawValue ? a.color : .clear, lineWidth: 1.5))
                }
            }
        }
    }

    private var databaseCard: some View {
        Card("Game database (SDE)") {
            Text("Ships, modules, attributes and the map come from CCP's static data. Canopus checks for a new version and downloads it on request.")
                .font(.ui(14))
                .foregroundStyle(C.muted)
            Button {
                env.showSDEUpdateSheet = true
            } label: {
                Label("Check for updates", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.canopusGhost)
        }
    }

    private var aboutCard: some View {
        Card("About") {
            let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
            let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
            Text("Canopus \(v) (\(b))").font(.ui(14)).foregroundStyle(C.text2)
            Text("EVE Online and all related materials are property of CCP hf. Canopus is not affiliated with CCP.")
                .font(.ui(12))
                .foregroundStyle(C.faint)
        }
    }

    private func addCharacter() async {
        adding = true
        defer { adding = false }
        do {
            try await env.characterStore.addCharacter { url in
                try await webAuthSession.authenticate(using: url, callbackURLScheme: EVEConstants.callbackScheme)
            }
        } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {
        } catch AuthError.cancelled {
        } catch {
            self.error = error.localizedDescription
        }
    }
}
