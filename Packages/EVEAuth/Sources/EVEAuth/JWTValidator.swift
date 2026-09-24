import Foundation
import CryptoKit
import Security

// RS256 JWT validator against EVE SSO JWKS.
// Actor-isolated so the JWKS cache is never accessed from two tasks simultaneously.
public actor JWTValidator {
    private var cache: [String: SecKey] = [:]
    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func validate(_ jwt: String) async throws -> EVEClaims {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw AuthError.invalidJWT }

        guard let headerData  = Data(base64URLEncoded: String(parts[0])),
              let payloadData = Data(base64URLEncoded: String(parts[1])),
              let sigData      = Data(base64URLEncoded: String(parts[2]))
        else { throw AuthError.invalidJWT }

        let header = try JSONDecoder().decode(JWTHeader.self, from: headerData)
        let claims = try JSONDecoder().decode(EVEClaims.self,  from: payloadData)

        guard claims.exp > Date().timeIntervalSince1970
        else { throw AuthError.tokenExpired }

        let iss = claims.iss
        guard iss == "login.eveonline.com" || iss == "https://login.eveonline.com"
        else { throw AuthError.invalidIssuer }

        let key = try await publicKey(kid: header.kid)
        let message = Data("\(parts[0]).\(parts[1])".utf8)
        var cfErr: Unmanaged<CFError>?
        let ok = SecKeyVerifySignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            message as CFData,
            sigData as CFData,
            &cfErr
        )
        guard ok else { throw AuthError.invalidSignature }
        return claims
    }

    // MARK: - Private

    private func publicKey(kid: String) async throws -> SecKey {
        if let cached = cache[kid] { return cached }
        try await fetchJWKS()
        guard let key = cache[kid] else { throw AuthError.unknownKeyID }
        return key
    }

    private func fetchJWKS() async throws {
        var req = URLRequest(url: EVEConstants.jwksURL)
        req.setValue(EVEConstants.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await urlSession.data(for: req)
        let jwks = try JSONDecoder().decode(JWKS.self, from: data)
        cache = [:]
        for jwk in jwks.keys where jwk.kty == "RSA" {
            if let key = try? jwk.toSecKey() { cache[jwk.kid] = key }
        }
    }
}

// MARK: - JWT types

private struct JWTHeader: Decodable {
    let kid: String
    let alg: String
}

public struct EVEClaims: Decodable, Sendable {
    public let sub: String          // "CHARACTER:EVE:12345678"
    public let name: String?
    public let scp: SCPField?       // can be String or [String]
    public let exp: TimeInterval
    public let iss: String

    public var characterId: Int? {
        let parts = sub.split(separator: ":")
        guard parts.count == 3, parts[0] == "CHARACTER", parts[1] == "EVE" else { return nil }
        return Int(parts[2])
    }

    public var scopes: [String] {
        switch scp {
        case .string(let s): return s.split(separator: " ").map(String.init)
        case .array(let a):  return a
        case nil:            return []
        }
    }

    public enum SCPField: Decodable, Sendable {
        case string(String)
        case array([String])

        public init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { self = .string(s); return }
            self = .array(try c.decode([String].self))
        }
    }
}

// MARK: - JWKS / JWK

private struct JWKS: Decodable {
    let keys: [JWK]
}

private struct JWK: Decodable {
    let kid: String
    let kty: String
    let n: String?   // RSA modulus (absent for EC keys)
    let e: String?   // RSA exponent (absent for EC keys)
    let alg: String?
    let use: String?

    func toSecKey() throws -> SecKey {
        guard let n, let e,
              let modulus  = Data(base64URLEncoded: n),
              let exponent = Data(base64URLEncoded: e)
        else { throw AuthError.invalidJWT }

        let pkcs1 = asn1Sequence(asn1Integer(modulus) + asn1Integer(exponent))
        let attrs: [CFString: Any] = [
            kSecAttrKeyType:  kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
        ]
        var cfErr: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attrs as CFDictionary, &cfErr)
        else { throw AuthError.invalidSignature }
        return key
    }

    // Minimal DER ASN.1 helpers for PKCS#1 RSAPublicKey.
    private func asn1Length(_ n: Int) -> Data {
        if n < 0x80 { return Data([UInt8(n)]) }
        if n < 0x100 { return Data([0x81, UInt8(n)]) }
        return Data([0x82, UInt8(n >> 8), UInt8(n & 0xFF)])
    }

    private func asn1Integer(_ raw: Data) -> Data {
        var b = raw
        while b.count > 1 && b.first == 0 { b = b.dropFirst() }
        if let first = b.first, first & 0x80 != 0 { b = Data([0x00]) + b }
        return Data([0x02]) + asn1Length(b.count) + b
    }

    private func asn1Sequence(_ body: Data) -> Data {
        Data([0x30]) + asn1Length(body.count) + body
    }
}
