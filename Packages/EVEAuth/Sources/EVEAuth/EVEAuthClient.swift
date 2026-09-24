import Foundation

@MainActor
public final class EVEAuthClient {
    private let keychain = KeychainTokenStore()
    private let validator: JWTValidator
    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        self.validator = JWTValidator(urlSession: urlSession)
    }

    // MARK: - Public

    /// Returns the EVE SSO authorization URL and PKCE challenge.
    /// The caller opens the URL in a browser and passes the resulting callback URL to finishAuthentication.
    public func beginAuthentication() -> (authURL: URL, pkce: PKCEGenerator.Challenge) {
        let pkce = PKCEGenerator.generate()
        return (buildAuthURL(pkce: pkce), pkce)
    }

    /// Completes authentication after the browser redirects to the callback URL.
    public func finishAuthentication(callbackURL: URL, pkce: PKCEGenerator.Challenge) async throws -> StoredTokens {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else { throw AuthError.missingCode }
        let tokens = try await exchangeCode(code, pkce: pkce)
        try keychain.save(tokens)
        return tokens
    }

    /// Refreshes the access token using the stored refresh token.
    public func refresh(_ existing: StoredTokens) async throws -> StoredTokens {
        let tokens = try await tokenRequest(body: [
            "grant_type":    "refresh_token",
            "refresh_token": existing.refreshToken,
            "client_id":     EVEConstants.clientID,
        ])
        try keychain.save(tokens)
        return tokens
    }

    public func loadAll() -> [StoredTokens] { keychain.loadAll() }

    public func delete(characterId: Int) { keychain.delete(characterId: characterId) }

    // MARK: - Private

    private func exchangeCode(_ code: String, pkce: PKCEGenerator.Challenge) async throws -> StoredTokens {
        try await tokenRequest(body: [
            "grant_type":    "authorization_code",
            "code":          code,
            "client_id":     EVEConstants.clientID,
            "code_verifier": pkce.verifier,
            "redirect_uri":  "\(EVEConstants.callbackScheme)://callback",
        ])
    }

    private func tokenRequest(body: [String: String]) async throws -> StoredTokens {
        var req = URLRequest(url: EVEConstants.tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(EVEConstants.userAgent, forHTTPHeaderField: "User-Agent")
        var components = URLComponents()
        components.queryItems = body.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await urlSession.data(for: req)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(statusCode) {
            throw AuthError.httpError(statusCode, String(data: data, encoding: .utf8))
        }

        // Detect OAuth error responses returned with 200 status.
        struct OAuthErrorResponse: Decodable {
            let error: String
            let errorDescription: String?
            enum CodingKeys: String, CodingKey {
                case error
                case errorDescription = "error_description"
            }
        }
        if let oauthErr = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data) {
            let msg = [oauthErr.error, oauthErr.errorDescription].compactMap { $0 }.joined(separator: ": ")
            throw AuthError.httpError(statusCode, msg)
        }

        struct TokenResponse: Decodable {
            let accessToken: String
            let refreshToken: String
            let expiresIn: Int
            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case expiresIn = "expires_in"
            }
        }

        let tr = try JSONDecoder().decode(TokenResponse.self, from: data)
        let claims = try await validator.validate(tr.accessToken)

        guard let characterId = claims.characterId else {
            throw AuthError.invalidCharacterClaim
        }

        return StoredTokens(
            characterId: characterId,
            characterName: claims.name ?? "",
            accessToken: tr.accessToken,
            refreshToken: tr.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tr.expiresIn)),
            scopes: claims.scopes
        )
    }

    private func buildAuthURL(pkce: PKCEGenerator.Challenge) -> URL {
        var comps = URLComponents(url: EVEConstants.authorizeURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "response_type",         value: "code"),
            .init(name: "client_id",             value: EVEConstants.clientID),
            .init(name: "redirect_uri",          value: "\(EVEConstants.callbackScheme)://callback"),
            .init(name: "scope",                 value: EVEConstants.scopeString),
            .init(name: "code_challenge",        value: pkce.challenge),
            .init(name: "code_challenge_method", value: pkce.method),
            .init(name: "state",                 value: UUID().uuidString),
        ]
        return comps.url!
    }
}
