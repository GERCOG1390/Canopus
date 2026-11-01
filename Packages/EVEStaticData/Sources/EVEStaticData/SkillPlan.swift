// The skill planner's data (the desktop's sde skillPlan / requirementTree): every level to train for a set
// of goals — ships, modules, charges or skills to a level — prerequisites first, each skill with its rank
// and training attributes.

import Foundation
import GRDB

public struct SkillPlanStep: Sendable, Hashable {
    public let skill: Int
    public let level: Int
    public let rank: Int
    /// Primary and secondary training attributes (164 charisma … 168 willpower)
    public let primary: Int
    public let secondary: Int
}

/// Skill points a skill of this rank has at a level (the game's formula).
public func skillPoints(rank: Int, level: Int) -> Int {
    guard level > 0 else { return 0 }
    return Int((250 * Double(rank) * pow(2, 2.5 * Double(level - 1))).rounded(.up))
}

/// Required skill attribute → its level attribute, in the order the game lists them.
private let planRequirementAttrs: [(Int, Int)] = [(182, 277), (183, 278), (184, 279), (1285, 1286), (1289, 1287), (1290, 1288)]
private let skillCategory = 16

extension SDERepository {
    /// Every level to train for the goals, in training order (prerequisites first), each level once.
    public func skillPlan(goals: [(typeId: Int, level: Int?)]) async throws -> [SkillPlanStep] {
        try await dbReader.read { db in
            var attrsCache: [Int: [Int: Double]] = [:]
            func attrs(_ id: Int) throws -> [Int: Double] {
                if let a = attrsCache[id] { return a }
                var a: [Int: Double] = [:]
                for r in try Row.fetchAll(db, sql: "SELECT attribute_id, value FROM type_attributes WHERE type_id = ?", arguments: [id]) {
                    a[r["attribute_id"]] = r["value"]
                }
                attrsCache[id] = a
                return a
            }
            func skillInfo(_ id: Int) throws -> (rank: Int, primary: Int, secondary: Int) {
                let a = try attrs(id)
                return (Int(a[275] ?? 1), Int(a[180] ?? 0), Int(a[181] ?? 0))
            }
            var out: [SkillPlanStep] = []
            var planned: [Int: Int] = [:]
            func add(skill: Int, level: Int, depth: Int) throws {
                guard depth < 13 else { return }
                try requirements(of: skill, depth: depth + 1)
                let info = try skillInfo(skill)
                let from = (planned[skill] ?? 0) + 1
                if from <= level {
                    for l in from...level { out.append(SkillPlanStep(skill: skill, level: l, rank: info.rank, primary: info.primary, secondary: info.secondary)) }
                }
                planned[skill] = max(planned[skill] ?? 0, level)
            }
            func requirements(of typeId: Int, depth: Int) throws {
                guard depth < 13 else { return }
                let a = try attrs(typeId)
                for (sa, la) in planRequirementAttrs {
                    guard let skill = a[sa], skill > 0 else { continue }
                    try add(skill: Int(skill), level: Int(a[la] ?? 1), depth: depth)
                }
            }
            for goal in goals {
                let category = try Int.fetchOne(db, sql: "SELECT g.category_id FROM types t JOIN groups g ON g.id = t.group_id WHERE t.id = ?", arguments: [goal.typeId])
                if category == skillCategory {
                    try add(skill: goal.typeId, level: goal.level ?? 5, depth: 0)
                } else {
                    try requirements(of: goal.typeId, depth: 0)
                }
            }
            return out
        }
    }
}
