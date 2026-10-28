// The desktop's fit tools in the bundled engine: damage against mission NPCs (npc.ts), the abyssal
// planner (abyss.ts) and the optimizer's numbers (metrics.ts). The data each one needs is added from the
// SDE first; Tools/dogma-js/check_tools.py checks it gives the same results as the desktop's whole SDE.

import Foundation
import GRDB

// MARK: - Results (canopus-desktop src/shared/npc.ts, abyss.ts, fit.ts FitMetrics)

public struct NpcReport: Decodable, Sendable {
    public struct ClassResult: Decodable, Sendable {
        public struct Extreme: Decodable, Sendable {
            public let name: String
            /// nil when the fit can't out-damage its repairs (the engine's Infinity).
            public let ttk: Double?
        }
        public struct Typical: Decodable, Sendable {
            public let hp: Double
            public let sig: Double
            public let speed: Double
            public let orbit: Double
        }
        public let cls: String
        public let count: Int
        public let application: Double
        public let appliedDps: Double
        public let ttkMedian: Double?
        public let fastest: Extreme
        public let slowest: Extreme
        public let unkillable: Int
        public let approach: Bool
        public let limits: [String]
        public let typical: Typical
    }
    public struct Room: Decodable, Sendable {
        public let composition: [String: Int]
        public let seconds: Double?
    }
    public let faction: String
    public let paperDps: Double
    public let classes: [ClassResult]
    public let room: Room
    public let weaponReach: Double
}

public struct AbyssReport: Decodable, Sendable {
    public struct Side: Decodable, Sendable {
        public let dps: Double
        public let ehp: Double
        public let resist: [Double]
        public let repair: Double
        public let capStable: Bool
        public let capLevel: Double?
        public let capLasts: Double?
        public let speed: Double
        public let reach: Double
    }
    public struct Npc: Decodable, Sendable, Identifiable {
        public let id: Int
        public let name: String
        public let hp: Double
        public let sig: Double
        public let ttk: Double?
        public let application: Double
        public let dps: Double
        public let taken: Double
        public let types: [Double]
        public let neut: Double
        public let ewar: [String]
    }
    public struct Faction: Decodable, Sendable {
        public let faction: String
        public let npcs: [Npc]
        public let ttkMedian: Double?
        public let worstTaken: Double
    }
    public let weather: String
    public let strength: Int
    public let layer: String
    public let normal: Side
    public let inWeather: Side
    public let factions: [Faction]
}

/// The numbers the optimizer compares fits by.
public struct FitMetrics: Decodable, Sendable {
    public let dps: Double
    public let ehp: Double
    public let activeTank: Double
    public let speed: Double
    public let align: Double
    public let lockRange: Double
    public let scanRes: Double
    public let signature: Double
    public let range: Double
    public let tracking: Double
    public let explosionRadius: Double
    public let explosionVelocity: Double
    public let capStable: Bool
    public let capLevel: Double
    public let capLasts: Double
    public let fits: Bool
}

/// What the next level of one skill changes on the fit (canopus-desktop src/main/dogma/gains.ts).
public struct SkillGain: Decodable, Sendable, Identifiable {
    public var id: Int { skill }
    public let skill: Int
    /// The level the pilot has now.
    public let from: Int
    public let dps: Double
    public let ehp: Double
    public let activeTank: Double
    public let speed: Double
    /// Seconds (negative = faster align).
    public let align: Double
    public let capacitor: Double
    public let lockRange: Double
}

public enum NpcFaction: String, CaseIterable, Sendable {
    case guristas, serpentis, blood_raiders, sansha, angel, rogue_drones
    case amarr, caldari, gallente, minmatar, khanid, thukker, mordu, concord

    /// The SDE group-name prefix of its mission NPCs (npc.ts FACTION_GROUP).
    var groupPrefix: String {
        switch self {
        case .guristas: "Deadspace Guristas"
        case .serpentis: "Deadspace Serpentis"
        case .blood_raiders: "Deadspace Blood Raiders"
        case .sansha: "Deadspace Sansha's Nation"
        case .angel: "Deadspace Angel Cartel"
        case .rogue_drones: "Deadspace Rogue Drone"
        case .amarr: "Mission Amarr Empire"
        case .caldari: "Mission Caldari State"
        case .gallente: "Mission Gallente Federation"
        case .minmatar: "Mission Minmatar Republic"
        case .khanid: "Mission Khanid"
        case .thukker: "Mission Thukker"
        case .mordu: "Mission Mordu"
        case .concord: "Mission CONCORD"
        }
    }
}

public enum AbyssWeather: String, CaseIterable, Sendable {
    case electrical, dark, exotic, firestorm, gamma

    /// Weather celestials by penalty strength (abyss.ts WEATHER_CELESTIAL).
    public func celestial(strength: Int) -> Int {
        let base: Int
        switch self {
        case .electrical: base = 47381
        case .dark: base = 47378
        case .exotic: base = 47384
        case .firestorm: base = 47390
        case .gamma: base = 47387
        }
        return base + (strength == 70 ? 2 : strength == 50 ? 1 : 0)
    }

    /// Penalty strengths a tier rolls between: 30 or 50% through tier 3, 50 or 70% above.
    public static func strengths(tier: Int) -> (Int, Int) { tier >= 4 ? (50, 70) : (30, 50) }
}

/// Another version of a fitted module or drone the hull can take (the optimizer's candidates).
public struct FitVariantCandidate: Sendable {
    public let from: Int
    public let to: Int
    public let isDrone: Bool
    public let missingSkills: Bool
}

// MARK: - Engine calls

extension DogmaJS {
    public func npcDamage(_ spec: JSFitSpec, skills: JSSkills, faction: NpcFaction) async throws -> NpcReport {
        try await prepare(spec.typeIds.union(repo.npcTypeIds(faction: faction)))
        return try decode(invoke("npcDamage", [encode(spec), skills.json, faction.rawValue]))
    }

    public func abyssPlan(_ spec: JSFitSpec, skills: JSSkills, weather: AbyssWeather, strength: Int) async throws -> AbyssReport {
        try await prepare(spec.typeIds.union(repo.abyssNpcTypeIds()).union([weather.celestial(strength: strength)]))
        return try decode(invoke("abyssPlan", [encode(spec), skills.json, weather.rawValue, strength]))
    }

    /// What one more level of each unmaxed skill would change, with the pilot's levels.
    public func skillGains(_ spec: JSFitSpec, levels: [Int: Int]) async throws -> [SkillGain] {
        try await prepare(spec.typeIds)
        let json = "{" + levels.sorted { $0.key < $1.key }.map { "\"\($0.key)\":\($0.value)" }.joined(separator: ",") + "}"
        return try decode(invoke("skillGains", [encode(spec), json]))
    }

    /// The optimizer's numbers for each spec, in one call.
    public func metrics(_ specs: [JSFitSpec], skills: JSSkills) async throws -> [FitMetrics] {
        try await prepare(specs.reduce(into: Set<Int>()) { $0.formUnion($1.typeIds) })
        return try decode(invoke("metrics", [encode(specs), skills.json]))
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}

// MARK: - SDE queries

extension SDERepository {
    /// Mission NPCs of a faction, all five classes (npc.ts npcsOf: the "<prefix> <class>" groups).
    func npcTypeIds(faction: NpcFaction) async throws -> Set<Int> {
        let names = ["frigate", "destroyer", "cruiser", "battlecruiser", "battleship"].map { "\(faction.groupPrefix) \($0)".lowercased() }
        return try await dbReader.read { db in
            Set(try Int.fetchAll(db, sql: """
                SELECT t.id FROM types t JOIN groups g ON g.id = t.group_id
                WHERE lower(g.name) IN (\(names.map { _ in "?" }.joined(separator: ",")))
                """, arguments: StatementArguments(names)))
        }
    }

    /// The abyssal NPC groups (abyss.ts NPC_GROUPS) and the missiles they fire.
    func abyssNpcTypeIds() async throws -> Set<Int> {
        try await dbReader.read { db in
            let npcs = try Int.fetchAll(db, sql: "SELECT id FROM types WHERE group_id IN (1982, 1997)")
            let missiles = try Double.fetchAll(db, sql: """
                SELECT value FROM type_attributes WHERE attribute_id = 507
                AND type_id IN (SELECT id FROM types WHERE group_id IN (1982, 1997))
                """).map { Int($0) }
            return Set(npcs + missiles)
        }
    }

    /// Every other published version of each module / drone type (the variation family, as the desktop's
    /// variantsOf) that this hull can take by the static rules (the desktop's fittableFor), and whether the
    /// pilot lacks a skill for it (`levels` nil: all skills at V).
    public func fitVariants(shipTypeId: Int, moduleTypeIds: Set<Int>, droneTypeIds: Set<Int>, levels: [Int: Int]?) async throws -> [FitVariantCandidate] {
        try await dbReader.read { db in
            let attrIds = { (pattern: String) in try Int.fetchAll(db, sql: "SELECT id FROM dogma_attributes WHERE name GLOB ?", arguments: [pattern]) }
            let groupAttrs = Set(try attrIds("canFitShipGroup[0-9]*"))
            let typeAttrs = Set(try attrIds("canFitShipType[0-9]*"))
            let ship = try Row.fetchOne(db, sql: "SELECT group_id FROM types WHERE id = ?", arguments: [shipTypeId])
            let shipGroup: Int = ship?["group_id"] ?? 0
            let shipAttrs = try Self.attrs(db, ids: [shipTypeId])[shipTypeId] ?? [:]

            var out: [FitVariantCandidate] = []
            for (from, isDrone) in moduleTypeIds.map({ ($0, false) }) + droneTypeIds.map({ ($0, true) }) {
                let parent = try Int.fetchOne(db, sql: "SELECT coalesce(variation_parent_id, id) FROM types WHERE id = ?", arguments: [from]) ?? from
                let family = try Int.fetchAll(db, sql: """
                    SELECT id FROM types WHERE (id = ? OR variation_parent_id = ?) AND id != ?
                    AND published = 1 AND market_group_id IS NOT NULL
                    """, arguments: [parent, parent, from])
                let attrs = try Self.attrs(db, ids: family)
                let volumes = try Dictionary(uniqueKeysWithValues: Row.fetchAll(db, sql: """
                    SELECT id, coalesce(volume, 0) AS v FROM types WHERE id IN (\(family.map(String.init).joined(separator: ",").nonEmpty ?? "0"))
                    """).map { ($0["id"] as Int, $0["v"] as Double) })
                for to in family {
                    if isDrone, droneTypeIds.contains(to) { continue }
                    let a = attrs[to] ?? [:]
                    if !isDrone {
                        let groups = groupAttrs.compactMap { a[$0] }.filter { $0 != 0 }.map { Int($0) }
                        let types = typeAttrs.compactMap { a[$0] }.filter { $0 != 0 }.map { Int($0) }
                        if !(groups.isEmpty && types.isEmpty), !groups.contains(shipGroup), !types.contains(shipTypeId) { continue }
                        if let fitsTo = a[1380], Int(fitsTo) != shipTypeId { continue }
                        if let size = a[1547], size != (shipAttrs[1547] ?? -1) { continue }
                        if (volumes[to] ?? 0) > 3500, (shipAttrs[1785] ?? 0) == 0 { continue }
                    }
                    var missing = false
                    if let levels {
                        let reqs = try Row.fetchAll(db, sql: "SELECT skill_id, level FROM skill_requirements WHERE type_id = ?", arguments: [to])
                        missing = reqs.contains { (levels[$0["skill_id"] as Int] ?? 0) < ($0["level"] as Int) }
                    }
                    out.append(FitVariantCandidate(from: from, to: to, isDrone: isDrone, missingSkills: missing))
                }
            }
            return out
        }
    }

    private static func attrs(_ db: Database, ids: [Int]) throws -> [Int: [Int: Double]] {
        guard !ids.isEmpty else { return [:] }
        var out: [Int: [Int: Double]] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT type_id, attribute_id, value FROM type_attributes WHERE type_id IN (\(ids.map(String.init).joined(separator: ",")))") {
            out[row["type_id"] as Int, default: [:]][row["attribute_id"] as Int] = row["value"]
        }
        return out
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
