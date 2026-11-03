// Mission agents and mutaplasmids (importer 7): every agent with its corporation, division, level and
// system; and for a module, the mutaplasmids that apply to it, what they turn it into and the range of each
// attribute they roll.

import Foundation
import GRDB

public struct AgentEntry: Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let corporationId: Int
    public let corporation: String
    public let factionId: Int?
    public let division: String
    public let level: Int
    public let isLocator: Bool
    /// 2 basic, 4 research, 6/7 storyline, 9 factional warfare, 10 epic arc, 12 career…
    public let agentType: Int?
    public let systemId: Int?
    /// Docked in a station (otherwise the agent is in space)
    public let inStation: Bool
}

public struct MutaplasmidOption: Sendable, Hashable, Identifiable {
    /// The mutaplasmid's type
    public let id: Int
    public let name: String
    /// The abyssal module it makes from this one
    public let resultTypeId: Int
}

public struct MutaplasmidRange: Sendable, Hashable, Identifiable {
    public var id: Int { attributeId }
    public let attributeId: Int
    public let name: String
    public let unitId: Int?
    public let unitName: String?
    public let highIsGood: Bool
    /// Multipliers of the module's own value
    public let min: Double
    public let max: Double
}

extension SDERepository {
    /// Every agent; empty with a database from before importer 7.
    public func agents() async throws -> [AgentEntry] {
        try await dbReader.read { db in
            guard try db.tableExists("agents") else { return [] }
            return try Row.fetchAll(db, sql: """
                SELECT a.id, a.name, a.corporation_id, c.name AS corp, c.faction_id, COALESCE(d.name, '') AS division,
                       a.level, a.is_locator, a.agent_type, a.system_id, a.station_id
                FROM agents a JOIN npc_corporations c ON c.id = a.corporation_id
                LEFT JOIN npc_divisions d ON d.id = a.division_id
                """).map { r in
                AgentEntry(id: r["id"], name: r["name"], corporationId: r["corporation_id"], corporation: r["corp"], factionId: r["faction_id"],
                           division: r["division"], level: r["level"], isLocator: (r["is_locator"] as Int) == 1, agentType: r["agent_type"],
                           systemId: r["system_id"], inStation: (r["station_id"] as Int?) != nil)
            }
        }
    }

    /// Modules a mutaplasmid applies to.
    public func mutableTypeIds() async throws -> Set<Int> {
        try await dbReader.read { db in
            guard try db.tableExists("dynamic_mappings") else { return [] }
            return Set(try Int.fetchAll(db, sql: "SELECT DISTINCT source_type_id FROM dynamic_mappings"))
        }
    }

    public func mutaplasmids(forModule typeId: Int) async throws -> [MutaplasmidOption] {
        try await dbReader.read { db in
            guard try db.tableExists("dynamic_mappings") else { return [] }
            return try Row.fetchAll(db, sql: """
                SELECT m.mutaplasmid_id, t.name, m.result_type_id FROM dynamic_mappings m JOIN types t ON t.id = m.mutaplasmid_id
                WHERE m.source_type_id = ? ORDER BY t.name
                """, arguments: [typeId]).map { MutaplasmidOption(id: $0["mutaplasmid_id"], name: $0["name"], resultTypeId: $0["result_type_id"]) }
        }
    }

    public func mutaplasmidRanges(_ mutaplasmidId: Int) async throws -> [MutaplasmidRange] {
        try await dbReader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT r.attribute_id, COALESCE(NULLIF(a.display_name, ''), a.name) AS name, a.unit_id, u.display_name AS unit,
                       a.high_is_good, r.min, r.max
                FROM dynamic_attributes r JOIN dogma_attributes a ON a.id = r.attribute_id
                LEFT JOIN dogma_units u ON u.id = a.unit_id
                WHERE r.mutaplasmid_id = ? ORDER BY name
                """, arguments: [mutaplasmidId]).map { r in
                MutaplasmidRange(attributeId: r["attribute_id"], name: r["name"], unitId: r["unit_id"], unitName: r["unit"],
                                 highIsGood: (r["high_is_good"] as Int? ?? 0) == 1, min: r["min"], max: r["max"])
            }
        }
    }
}
