// Public lookups for intel (the desktop's lib/intel.ts and PvpPage): names to ids, affiliations,
// corporations, alliances, characters, and zKillboard's statistics and recent fights. No login needed;
// results are cached for the session (zKillboard statistics for 30 minutes, as the desktop).

import Foundation

public struct ZKBCharacterStats: Sendable {
    public let kills: Int
    public let losses: Int
    public let iskDestroyed: Double
    public let iskLost: Double
    public let danger: Int
    public let gang: Int
    public let soloKills: Int
    public let soloLosses: Int
    public let avgGang: Double?
    /// Kills in the last 7 days.
    public let activeWeek: Int
    /// zKillboard's "recent" window (about 3 months).
    public let recentKills: Int
    public let recentLosses: Int
    public let recentSolo: Int
    public let recentShips: [(typeId: Int, kills: Int, losses: Int)]
    public let corporationId: Int?
    public let allianceId: Int?
}

public actor PublicESI {
    public static let shared = PublicESI()

    private let session: URLSession = .shared
    private var corps: [Int: ESICorporationInfo] = [:]
    private var alliances: [Int: ESIAllianceInfo] = [:]
    private var characters: [Int: ESICharacterInfo] = [:]
    private var stats: [Int: (at: Date, value: ZKBCharacterStats?)] = [:]

    // MARK: ESI

    /// Character ids for names (exact, any case); unknown names are left out.
    public func characterIds(names: [String]) async throws -> [(id: Int, name: String)] {
        struct Hit: Decodable { let id: Int; let name: String }
        struct Res: Decodable { let characters: [Hit]? }
        var out: [(Int, String)] = []
        let unique = Array(Set(names))
        for start in stride(from: 0, to: unique.count, by: 500) {
            let chunk = Array(unique[start..<min(start + 500, unique.count)])
            let r: Res = try await post("https://esi.evetech.net/latest/universe/ids/", body: chunk)
            out += (r.characters ?? []).map { ($0.id, $0.name) }
        }
        return out.map { (id: $0.0, name: $0.1) }
    }

    /// Corporation ids for exact names.
    public func corporationIds(names: [String]) async throws -> [(id: Int, name: String)] {
        struct Hit: Decodable { let id: Int; let name: String }
        struct Res: Decodable { let corporations: [Hit]? }
        let r: Res = try await post("https://esi.evetech.net/latest/universe/ids/", body: Array(Set(names)))
        return (r.corporations ?? []).map { (id: $0.id, name: $0.name) }
    }

    /// A corporation's LP store offers (public).
    public func loyaltyOffers(corporationId: Int) async throws -> [ESILoyaltyStoreOffer] {
        try await get("https://esi.evetech.net/latest/loyalty/stores/\(corporationId)/offers/")
    }

    public struct Affiliation: Decodable, Sendable {
        public let characterId: Int
        public let corporationId: Int
        public let allianceId: Int?
    }

    public func affiliations(_ ids: [Int]) async throws -> [Int: Affiliation] {
        var out: [Int: Affiliation] = [:]
        for start in stride(from: 0, to: ids.count, by: 1000) {
            let rows: [Affiliation] = try await post("https://esi.evetech.net/latest/characters/affiliation/", body: Array(ids[start..<min(start + 1000, ids.count)]))
            for r in rows { out[r.characterId] = r }
        }
        return out
    }

    public func corporation(_ id: Int) async -> ESICorporationInfo? {
        if let c = corps[id] { return c }
        let c: ESICorporationInfo? = try? await get("https://esi.evetech.net/latest/corporations/\(id)/")
        corps[id] = c
        return c
    }

    public func alliance(_ id: Int) async -> ESIAllianceInfo? {
        if let a = alliances[id] { return a }
        let a: ESIAllianceInfo? = try? await get("https://esi.evetech.net/latest/alliances/\(id)/")
        alliances[id] = a
        return a
    }

    public func character(_ id: Int) async -> ESICharacterInfo? {
        if let c = characters[id] { return c }
        let c: ESICharacterInfo? = try? await get("https://esi.evetech.net/latest/characters/\(id)/")
        characters[id] = c
        return c
    }

    // MARK: zKillboard

    /// The pilot's zKillboard statistics; nil when zKillboard has nothing on them.
    public func zkbStats(_ id: Int) async -> ZKBCharacterStats? {
        if let hit = stats[id], Date().timeIntervalSince(hit.at) < 1800 { return hit.value }
        var value: ZKBCharacterStats?
        if let data = try? await raw("https://zkillboard.com/api/stats/characterID/\(id)/"),
           let s = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let int = { (k: String) in (s[k] as? NSNumber)?.intValue ?? 0 }
            let kills = int("shipsDestroyed"), losses = int("shipsLost")
            if kills + losses > 0 {
                let labels = s["recentLabels"] as? [String: [String: Any]] ?? [:]
                let label = { (l: String, k: String) in (labels[l]?[k] as? NSNumber)?.intValue ?? 0 }
                let ships = (s["recentShips"] as? [[String: Any]] ?? []).prefix(5).compactMap { r -> (typeId: Int, kills: Int, losses: Int)? in
                    guard let t = (r["shipTypeID"] as? NSNumber)?.intValue else { return nil }
                    return (t, (r["kills"] as? NSNumber)?.intValue ?? 0, (r["losses"] as? NSNumber)?.intValue ?? 0)
                }
                let info = s["info"] as? [String: Any]
                let active = ((s["activepvp"] as? [String: Any])?["kills"] as? [String: Any])?["count"] as? NSNumber
                value = ZKBCharacterStats(
                    kills: kills, losses: losses,
                    iskDestroyed: (s["iskDestroyed"] as? NSNumber)?.doubleValue ?? 0, iskLost: (s["iskLost"] as? NSNumber)?.doubleValue ?? 0,
                    danger: int("dangerRatio"), gang: int("gangRatio"), soloKills: int("soloKills"), soloLosses: int("soloLosses"),
                    avgGang: (s["avgGangSize"] as? NSNumber)?.doubleValue,
                    activeWeek: active?.intValue ?? 0,
                    recentKills: label("pvp", "shipsDestroyed"), recentLosses: label("pvp", "shipsLost"), recentSolo: label("solo", "shipsDestroyed"),
                    recentShips: ships,
                    corporationId: (info?["corporation_id"] as? NSNumber)?.intValue, allianceId: (info?["alliance_id"] as? NSNumber)?.intValue)
            }
        }
        stats[id] = (Date(), value)
        return value
    }

    /// The pilot's recent kills and losses (whole killmails, newest first).
    public func zkbFights(_ id: Int) async throws -> [ZKBEntry] {
        try await JSONDecoder.esi.decode([ZKBEntry].self, from: raw("https://zkillboard.com/api/characterID/\(id)/"))
    }

    // MARK: HTTP

    private func raw(_ url: String) async throws -> Data {
        var req = URLRequest(url: URL(string: url)!)
        req.setValue(EVEConstants.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw URLError(.badServerResponse) }
        return data
    }

    private func get<T: Decodable>(_ url: String) async throws -> T {
        try await JSONDecoder.esi.decode(T.self, from: raw(url))
    }

    private func post<T: Decodable, B: Encodable>(_ url: String, body: B) async throws -> T {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.setValue(EVEConstants.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw URLError(.badServerResponse) }
        return try JSONDecoder.esi.decode(T.self, from: data)
    }
}
