import Foundation

public enum AuthError: Error, LocalizedError, Sendable {
    case cancelled
    case sessionFailed
    case missingCode
    case invalidJWT
    case tokenExpired
    case invalidIssuer
    case invalidSignature
    case unknownKeyID
    case invalidCharacterClaim
    case networkError(any Error)
    case httpError(Int, String?)
    case keychainError(OSStatus)
    case noStoredTokens

    public var errorDescription: String? {
        switch self {
        case .cancelled:                return "Authentication cancelled."
        case .sessionFailed:            return "Failed to start authentication session."
        case .missingCode:              return "No authorization code in callback URL."
        case .invalidJWT:               return "EVE SSO returned an invalid token."
        case .tokenExpired:             return "Access token has expired."
        case .invalidIssuer:            return "Token issued by unknown authority."
        case .invalidSignature:         return "Token signature verification failed."
        case .unknownKeyID:             return "Unknown JWT signing key."
        case .invalidCharacterClaim:    return "Token does not contain a valid character ID."
        case .networkError(let e):      return "Network error: \(e.localizedDescription)"
        case .httpError(let code, let msg): return "ESI error \(code)\(msg.map { ": \($0)" } ?? "")"
        case .keychainError(let s):     return "Keychain error \(s)."
        case .noStoredTokens:           return "No tokens found for this character."
        }
    }
}
