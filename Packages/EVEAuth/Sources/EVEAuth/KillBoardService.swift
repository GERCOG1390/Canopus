import Foundation

/// One zKillboard entry. zKillboard now returns whole killmails (victim with items, attackers) with the
/// hash under `zkb`; older responses had only the id and a top-level `killmail_hash`. Both decode.
public struct ZKBEntry: Decodable, Sendable, Identifiable {
    public var id: Int { killmailId }
    public let killmailId: Int
    public let killmailHash: String
    public let zkb: ZKBData
    /// Present in the current format.
    public let killmailTime: Date?
    public let victim: ESIKillVictim?

    private enum CodingKeys: String, CodingKey { case killmailId, killmailHash, zkb, killmailTime, victim }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        killmailId = try c.decode(Int.self, forKey: .killmailId)
        zkb = try c.decode(ZKBData.self, forKey: .zkb)
        guard let hash = try c.decodeIfPresent(String.self, forKey: .killmailHash) ?? zkb.hash else {
            throw DecodingError.keyNotFound(CodingKeys.killmailHash, .init(codingPath: c.codingPath, debugDescription: "no killmail hash"))
        }
        killmailHash = hash
        killmailTime = try? c.decodeIfPresent(Date.self, forKey: .killmailTime)
        victim = try? c.decodeIfPresent(ESIKillVictim.self, forKey: .victim)
    }
}

public struct ZKBData: Decodable, Sendable {
    public let hash: String?
    public let totalValue: Double?
    public let points: Int?
    public let npc: Bool?
    public let solo: Bool?
    public let locationId: Int?
}

@MainActor
public final class KillBoardService {
    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func kills(characterId: Int, page: Int = 1) async throws -> [ZKBEntry] {
        try await fetch("https://zkillboard.com/api/kills/characterID/\(characterId)/page/\(page)/")
    }

    public func losses(characterId: Int, page: Int = 1) async throws -> [ZKBEntry] {
        try await fetch("https://zkillboard.com/api/losses/characterID/\(characterId)/page/\(page)/")
    }

    /// Recent losses of a ship type (the "popular fits" tool reads the fits people lose).
    public func losses(shipTypeId: Int) async throws -> [ZKBEntry] {
        try await fetch("https://zkillboard.com/api/losses/shipTypeID/\(shipTypeId)/")
    }

    private func fetch(_ urlString: String) async throws -> [ZKBEntry] {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue(EVEConstants.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await urlSession.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder.esi.decode([ZKBEntry].self, from: data)
    }
}
