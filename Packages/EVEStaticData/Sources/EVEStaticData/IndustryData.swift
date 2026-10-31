// Blueprint data for the manufacturing calculator (the desktop's blueprintForProduct): which blueprint or
// reaction formula makes an item, its materials, time, output, skills and the runs a copy may carry.

import Foundation
import GRDB

public struct BlueprintJob: Sendable, Equatable {
    public let blueprintId: Int
    /// manufacturing or reaction
    public let activity: String
    /// Seconds per run
    public let time: Int
    public let maxRuns: Int
    public let productId: Int
    public let productQuantity: Int
    public let materials: [Material]
    public let skills: [Skill]

    public struct Material: Sendable, Equatable { public let typeId: Int; public let quantity: Int }
    public struct Skill: Sendable, Equatable { public let typeId: Int; public let level: Int }

    public var isReaction: Bool { activity == "reaction" }
}

extension SDERepository {
    /// The blueprint (or reaction formula) that makes an item; accepts the blueprint itself too.
    public func blueprintJob(for typeId: Int) async throws -> BlueprintJob? {
        try await dbReader.read { db in
            let activities = "('manufacturing', 'reaction')"
            var row = try Row.fetchOne(db, sql: """
                SELECT p.blueprint_id, p.activity, p.type_id, p.quantity FROM blueprint_products p JOIN types t ON t.id = p.blueprint_id
                WHERE p.type_id = ? AND p.activity IN \(activities) ORDER BY t.published DESC, p.blueprint_id LIMIT 1
                """, arguments: [typeId])
            if row == nil {
                // Maybe the pilot picked the blueprint: use what it makes.
                row = try Row.fetchOne(db, sql: """
                    SELECT blueprint_id, activity, type_id, quantity FROM blueprint_products
                    WHERE blueprint_id = ? AND activity IN \(activities) LIMIT 1
                    """, arguments: [typeId])
            }
            guard let row else { return nil }
            let bp: Int = row["blueprint_id"], activity: String = row["activity"]
            let materials = try Row.fetchAll(db, sql: "SELECT type_id, quantity FROM blueprint_materials WHERE blueprint_id = ? AND activity = ?",
                                             arguments: [bp, activity]).map { BlueprintJob.Material(typeId: $0["type_id"], quantity: $0["quantity"]) }
            guard !materials.isEmpty else { return nil }
            let skills = try Row.fetchAll(db, sql: "SELECT skill_id, level FROM blueprint_skills WHERE blueprint_id = ? AND activity = ?",
                                          arguments: [bp, activity]).map { BlueprintJob.Skill(typeId: $0["skill_id"], level: $0["level"]) }
            let time = try Int.fetchOne(db, sql: "SELECT time FROM blueprint_activities WHERE blueprint_id = ? AND activity = ?", arguments: [bp, activity]) ?? 0
            let maxRuns = try Int.fetchOne(db, sql: "SELECT max_runs FROM blueprints WHERE id = ?", arguments: [bp]) ?? 0
            return BlueprintJob(blueprintId: bp, activity: activity, time: time, maxRuns: maxRuns, productId: row["type_id"],
                                productQuantity: row["quantity"], materials: materials, skills: skills)
        }
    }

    /// Solar systems whose name starts with the text (then contains it), for pickers.
    public func systems(matching text: String, limit: Int = 12) async throws -> [(id: Int, name: String, security: Double)] {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return try await dbReader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, name, security FROM systems WHERE name LIKE ? || '%' OR name LIKE '%' || ? || '%'
                ORDER BY (name LIKE ? || '%') DESC, length(name), name LIMIT ?
                """, arguments: [q, q, q, limit]).map { ($0["id"], $0["name"], $0["security"]) }
        }
    }
}
