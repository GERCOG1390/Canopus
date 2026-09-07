import Foundation
import Security

public struct KeychainTokenStore: Sendable {
    private static let service = "com.canopus.evetokens"

    public init() {}

    public func save(_ tokens: StoredTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        let query: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrService:     Self.service,
            kSecAttrAccount:     "\(tokens.characterId)",
            kSecAttrAccessible:  kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData:       data,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw AuthError.keychainError(status) }
    }

    public func load(characterId: Int) throws -> StoredTokens {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: "\(characterId)",
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw AuthError.noStoredTokens
        }
        return try JSONDecoder().decode(StoredTokens.self, from: data)
    }

    public func loadAll() -> [StoredTokens] {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitAll,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [Data] else { return [] }
        return items.compactMap { try? JSONDecoder().decode(StoredTokens.self, from: $0) }
    }

    public func delete(characterId: Int) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: "\(characterId)",
        ]
        SecItemDelete(query as CFDictionary)
    }
}
