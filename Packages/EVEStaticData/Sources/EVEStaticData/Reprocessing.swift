// Reprocessing data: what an item breaks down into per batch (type_materials), the batch size (portion
// size) and, for ore, ice and moon ore, the skill that improves its yield (attribute 790,
// reprocessingSkillType) — taken from the SDE so CCP's ore skill changes need no code.

import Foundation
import GRDB

public struct ReprocessInfo: Sendable {
    public let typeId: Int
    public let portionSize: Int
    /// The ore-specific processing skill; nil for modules, ships and loot (scrapmetal).
    public let oreSkill: Int?
    public let materials: [(typeId: Int, quantity: Int)]
}

extension SDERepository {
    public func reprocessInfo(typeIds: Set<Int>) async throws -> [Int: ReprocessInfo] {
        guard !typeIds.isEmpty else { return [:] }
        let list = typeIds.map(String.init).joined(separator: ",")
        return try await dbReader.read { db in
            var materials: [Int: [(Int, Int)]] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT type_id, material_id, quantity FROM type_materials WHERE type_id IN (\(list))") {
                materials[r["type_id"], default: []].append((r["material_id"], r["quantity"]))
            }
            var skill: [Int: Int] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT type_id, value FROM type_attributes WHERE attribute_id = 790 AND type_id IN (\(list))") {
                skill[r["type_id"]] = Int(r["value"] as Double)
            }
            var out: [Int: ReprocessInfo] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT id, portion_size FROM types WHERE id IN (\(list))") {
                let id: Int = r["id"]
                guard let m = materials[id], !m.isEmpty else { continue }
                out[id] = ReprocessInfo(typeId: id, portionSize: max(1, r["portion_size"] ?? 1), oreSkill: skill[id],
                                        materials: m.map { (typeId: $0.0, quantity: $0.1) })
            }
            return out
        }
    }
}
