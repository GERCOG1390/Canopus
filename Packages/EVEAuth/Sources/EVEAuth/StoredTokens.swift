import Foundation

public struct StoredTokens: Codable, Sendable, Identifiable, Hashable {
    public var id: Int { characterId }
    public let characterId: Int
    public let characterName: String
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let scopes: [String]

    public init(
        characterId: Int, characterName: String,
        accessToken: String, refreshToken: String,
        expiresAt: Date, scopes: [String]
    ) {
        self.characterId = characterId
        self.characterName = characterName
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scopes = scopes
    }

    // True when the access token has at least 60 s of validity remaining.
    public var isAccessTokenValid: Bool {
        expiresAt.timeIntervalSinceNow > 60
    }

    public func hasScope(_ scope: String) -> Bool {
        scopes.contains(scope)
    }

    // URL for the character portrait (CCP CDN, no bundled assets).
    public func portraitURL(size: Int = 64) -> URL {
        EVEConstants.imageBase
            .appending(path: "characters/\(characterId)/portrait")
            .appending(queryItems: [.init(name: "size", value: "\(size)")])
    }
}
