import SwiftUI
import EVEAuth
import Domain

@Observable
final class CharacterStore {
    private(set) var services: [CharacterService] = []
    var selectedId: Int?

    private let authClient: EVEAuthClient

    var selectedService: CharacterService? {
        services.first { $0.tokens.characterId == selectedId }
    }

    var characters: [StoredTokens] { services.map(\.tokens) }

    init(authClient: EVEAuthClient) {
        self.authClient = authClient
        let stored = authClient.loadAll()
        services = stored.map { CharacterService(tokens: $0, authClient: authClient) }
        selectedId = services.first?.tokens.characterId
    }

    // MARK: - Auth

    /// Adds a character via EVE SSO. The caller provides the browser-opening closure
    /// (typically using @Environment(\.webAuthenticationSession)).
    @MainActor
    func addCharacter(openBrowser: (URL) async throws -> URL) async throws {
        let (authURL, pkce) = authClient.beginAuthentication()
        let callbackURL = try await openBrowser(authURL)
        let tokens = try await authClient.finishAuthentication(callbackURL: callbackURL, pkce: pkce)
        if let idx = services.firstIndex(where: { $0.tokens.characterId == tokens.characterId }) {
            services[idx] = CharacterService(tokens: tokens, authClient: authClient)
        } else {
            services.append(CharacterService(tokens: tokens, authClient: authClient))
        }
        selectedId = tokens.characterId
    }

    func removeCharacter(id: Int) {
        services.removeAll { $0.tokens.characterId == id }
        authClient.delete(characterId: id)
        if selectedId == id { selectedId = services.first?.tokens.characterId }
    }
}
