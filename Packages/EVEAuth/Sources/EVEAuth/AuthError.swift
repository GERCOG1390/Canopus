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
    /// EVE SSO no longer accepts the refresh token (revoked, or replaced): only signing in again helps.
    case sessionExpired

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
        case .sessionExpired:           return String(localized: "EVE no longer accepts this character's sign-in. Sign in again to continue.", bundle: .main)
        }
    }

    /// The token endpoint's answer for a refresh token it won't take. Server trouble and network errors
    /// are not this: they pass, and must not sign anyone out.
    var isDeadRefreshToken: Bool {
        if case .httpError(let code, let body) = self {
            return (400..<500).contains(code) && (body?.contains("invalid_grant") ?? false)
        }
        return false
    }
}
