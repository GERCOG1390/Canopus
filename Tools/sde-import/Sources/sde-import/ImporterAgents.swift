import GRDB
@preconcurrency import Yams
import Foundation

// Importer 7: NPC stations (their system: the SDE has no station names, ESI does), NPC corporations and
// divisions, mission agents (npcCharacters with an `agent` block, plus agents in space), and mutaplasmid
// ranges (dynamicItemAttributes: which modules each one applies to, what it makes, attribute min / max).

struct SDENpcStation: Decodable { let solarSystemID: Int; let ownerID: Int?; let typeID: Int? }
struct SDENpcCorporation: Decodable { let name: LocalizedString?; let factionID: Int? }
struct SDENpcDivision: Decodable { let name: LocalizedString? }
struct SDENpcCharacter: Decodable {
    struct Agent: Decodable { let agentTypeID: Int?; let divisionID: Int?; let isLocator: Bool?; let level: Int? }
    let name: LocalizedString?
    let corporationID: Int?
    let locationID: Int?
    let agent: Agent?
}
struct SDEAgentInSpace: Decodable { let solarSystemID: Int }
struct SDEDynamicItem: Decodable {
    struct Range: Decodable { let min: Double; let max: Double }
    struct Mapping: Decodable { let applicableTypes: [Int]; let resultingType: Int }
    let attributeIDs: [String: Range]?
    let inputOutputMapping: [Mapping]?
}

extension SDEImporter {
    func importAgentsAndMutaplasmids() async throws -> String {
        let stations = findFile("npcStations.yaml").flatMap { try? parseYAMLMap($0, as: SDENpcStation.self) } ?? []
        let corps = findFile("npcCorporations.yaml").flatMap { try? parseYAMLMap($0, as: SDENpcCorporation.self) } ?? []
        let divisions = findFile("npcCorporationDivisions.yaml").flatMap { try? parseYAMLMap($0, as: SDENpcDivision.self) } ?? []
        let characters = findFile("npcCharacters.yaml").flatMap { try? parseYAMLMap($0, as: SDENpcCharacter.self) } ?? []
        let inSpace = Dictionary((findFile("agentsInSpace.yaml").flatMap { try? parseYAMLMap($0, as: SDEAgentInSpace.self) } ?? []).map { ($0.id, $0.value.solarSystemID) },
                                 uniquingKeysWith: { a, _ in a })
        let dynamic = findFile("dynamicItemAttributes.yaml").flatMap { try? parseYAMLMap($0, as: SDEDynamicItem.self) } ?? []
        let stationSystem = Dictionary(stations.map { ($0.id, $0.value.solarSystemID) }, uniquingKeysWith: { a, _ in a })
        let agentCount = characters.filter { $0.value.agent != nil && $0.value.corporationID != nil }.count
        try await db.write { database in
            for (id, s) in stations {
                try database.execute(sql: "INSERT OR REPLACE INTO stations (id, system_id, name, type_id) VALUES (?, ?, '', ?)",
                                     arguments: [id, s.solarSystemID, s.typeID])
            }
            for (id, c) in corps {
                try database.execute(sql: "INSERT OR REPLACE INTO npc_corporations (id, name, faction_id) VALUES (?, ?, ?)",
                                     arguments: [id, c.name?.english ?? "", c.factionID])
            }
            for (id, d) in divisions {
                try database.execute(sql: "INSERT OR REPLACE INTO npc_divisions (id, name) VALUES (?, ?)", arguments: [id, d.name?.english ?? ""])
            }
            for (id, c) in characters {
                guard let a = c.agent, let corp = c.corporationID else { continue }
                let location = c.locationID
                let system = location.flatMap { stationSystem[$0] } ?? inSpace[id] ?? location.flatMap { (30_000_000..<33_000_000).contains($0) ? $0 : nil }
                try database.execute(sql: """
                    INSERT OR REPLACE INTO agents (id, name, corporation_id, division_id, level, agent_type, is_locator, station_id, system_id)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [id, c.name?.english ?? "", corp, a.divisionID, a.level ?? 1, a.agentTypeID, (a.isLocator ?? false) ? 1 : 0,
                                     location.flatMap { stationSystem[$0] != nil ? $0 : nil }, system])
            }
            for (id, d) in dynamic {
                for (attr, r) in d.attributeIDs ?? [:] {
                    guard let attrId = Int(attr) else { continue }
                    try database.execute(sql: "INSERT INTO dynamic_attributes (mutaplasmid_id, attribute_id, min, max) VALUES (?, ?, ?, ?)",
                                         arguments: [id, attrId, r.min, r.max])
                }
                for m in d.inputOutputMapping ?? [] {
                    for source in m.applicableTypes {
                        try database.execute(sql: "INSERT INTO dynamic_mappings (mutaplasmid_id, source_type_id, result_type_id) VALUES (?, ?, ?)",
                                             arguments: [id, source, m.resultingType])
                    }
                }
            }
        }
        return "\(stations.count) stations, \(corps.count) NPC corporations, \(agentCount) agents, \(dynamic.count) mutaplasmids"
    }
}
