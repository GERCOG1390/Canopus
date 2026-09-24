import GRDB
import Domain
import Foundation

/// Read-only access to the SDE SQLite database.
/// Sendable struct (DatabaseReader is Sendable in GRDB 7) — safe to share across
/// actors and concurrency contexts without wrapping in an actor.
public struct SDERepository: Sendable {
    private let dbReader: any DatabaseReader

    public init(dbReader: any DatabaseReader) {
        self.dbReader = dbReader
    }

    /// Opens the bundled SDE database off the main thread.
    public static func openBundled() async throws -> SDERepository {
        let queue = try await Task.detached(priority: .userInitiated) {
            try SDEDatabase.openBundled()
        }.value
        return SDERepository(dbReader: queue)
    }

    // MARK: - Categories

    public func categories() async throws -> [ItemCategory] {
        try await dbReader.read { db in
            try CategoryRecord
                .filter(Column("published") == true)
                .order(Column("name"))
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    // MARK: - Categories (by ID)

    public func category(id: Int) async throws -> ItemCategory? {
        try await dbReader.read { db in
            try CategoryRecord.fetchOne(db, key: id)?.toDomain()
        }
    }

    // MARK: - Representative icons

    /// Returns {categoryId: typeId} — one representative published typeID per category.
    /// Used to display real EVE item icons for category rows via images.evetech.net.
    public func representativeTypeIdsByCategory() async throws -> [Int: Int] {
        try await dbReader.read { db in
            let sql = """
                SELECT g.category_id, MIN(t.id) AS type_id
                FROM types t
                JOIN groups g ON t.group_id = g.id
                WHERE t.published = 1 AND g.published = 1
                GROUP BY g.category_id
                """
            var result: [Int: Int] = [:]
            for row in try Row.fetchAll(db, sql: sql) {
                result[row["category_id"]] = row["type_id"]
            }
            return result
        }
    }

    /// Returns {groupId: typeId} — one representative published typeID per group.
    public func representativeTypeIdsByGroup() async throws -> [Int: Int] {
        try await dbReader.read { db in
            let sql = """
                SELECT group_id, MIN(id) AS type_id
                FROM types
                WHERE published = 1
                GROUP BY group_id
                """
            var result: [Int: Int] = [:]
            for row in try Row.fetchAll(db, sql: sql) {
                result[row["group_id"]] = row["type_id"]
            }
            return result
        }
    }

    // MARK: - Groups

    public func group(id: Int) async throws -> ItemGroup? {
        try await dbReader.read { db in
            try GroupRecord.fetchOne(db, key: id)?.toDomain()
        }
    }

    public func groups(categoryId: Int) async throws -> [ItemGroup] {
        try await dbReader.read { db in
            try GroupRecord
                .filter(Column("category_id") == categoryId && Column("published") == true)
                .order(Column("name"))
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    // MARK: - Types

    public func types(groupId: Int) async throws -> [ItemType] {
        try await dbReader.read { db in
            try TypeRecord
                .filter(Column("group_id") == groupId && Column("published") == true)
                .order(Column("name"))
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func type(id: Int) async throws -> ItemType? {
        try await dbReader.read { db in
            try TypeRecord.fetchOne(db, key: id)?.toDomain()
        }
    }

    /// Batch lookup — returns typeId → ItemType for all requested IDs in one query.
    public func types(ids: Set<Int>) async throws -> [Int: ItemType] {
        guard !ids.isEmpty else { return [:] }
        return try await dbReader.read { db in
            let sorted = ids.sorted()
            let placeholders = sorted.map { _ in "?" }.joined(separator: ",")
            let sql = "SELECT * FROM types WHERE id IN (\(placeholders))"
            var result: [Int: ItemType] = [:]
            for record in try TypeRecord.fetchAll(db, sql: sql, arguments: StatementArguments(sorted)) {
                result[record.id] = record.toDomain()
            }
            return result
        }
    }

    // MARK: - Attributes

    public func attributes(typeId: Int) async throws -> [TypeAttributeDetail] {
        try await dbReader.read { db in
            let sql = """
                SELECT
                    ta.type_id, ta.attribute_id, ta.value,
                    da.id         AS da_id,
                    da.name       AS da_name,
                    da.display_name,
                    da.unit_id,
                    da.high_is_good,
                    da.stackable,
                    da.default_value,
                    da.published  AS da_published
                FROM type_attributes ta
                LEFT JOIN dogma_attributes da ON da.id = ta.attribute_id
                WHERE ta.type_id = ?
                ORDER BY COALESCE(da.display_name, da.name)
                """
            return try Row.fetchAll(db, sql: sql, arguments: [typeId])
                .map { row in
                    let daId: Int? = row["da_id"]
                    let attr: DogmaAttribute? = daId.map { _ in
                        DogmaAttribute(
                            id: row["da_id"],
                            name: row["da_name"] ?? "",
                            displayName: row["display_name"],
                            unitId: row["unit_id"],
                            highIsGood: row["high_is_good"] ?? false,
                            stackable: row["stackable"] ?? false,
                            defaultValue: row["default_value"],
                            published: row["da_published"] ?? false
                        )
                    }
                    return TypeAttributeDetail(
                        typeId: row["type_id"],
                        attributeId: row["attribute_id"],
                        value: row["value"],
                        attribute: attr
                    )
                }
        }
    }

    // MARK: - Effects

    public func effects(typeId: Int) async throws -> [TypeEffectDetail] {
        try await dbReader.read { db in
            let effectSql = """
                SELECT te.type_id, te.effect_id, de.name, de.display_name, de.effect_category
                FROM type_effects te
                JOIN dogma_effects de ON de.id = te.effect_id
                WHERE te.type_id = ?
                ORDER BY COALESCE(de.display_name, de.name)
                """

            let effectRows = try Row.fetchAll(db, sql: effectSql, arguments: [typeId])
            let effectIds = effectRows.map { row -> Int in row["effect_id"] }
            var modifiersByEffect: [Int: [DogmaModifierDetail]] = [:]

            if !effectIds.isEmpty {
                let placeholders = effectIds.map { _ in "?" }.joined(separator: ",")
                let modifierSql = """
                    SELECT
                        dm.effect_id,
                        dm.domain,
                        dm.func,
                        dm.group_id,
                        dm.modified_attr_id,
                        modified.name AS modified_attr_name,
                        dm.modifying_attr_id,
                        modifying.name AS modifying_attr_name,
                        dm.operation,
                        dm.skill_type_id,
                        skill.name AS skill_name
                    FROM dogma_modifiers dm
                    LEFT JOIN dogma_attributes modified ON modified.id = dm.modified_attr_id
                    LEFT JOIN dogma_attributes modifying ON modifying.id = dm.modifying_attr_id
                    LEFT JOIN types skill ON skill.id = dm.skill_type_id
                    WHERE dm.effect_id IN (\(placeholders))
                    ORDER BY dm.effect_id, dm.domain, dm.func, dm.modified_attr_id
                    """

                for row in try Row.fetchAll(db, sql: modifierSql, arguments: StatementArguments(effectIds)) {
                    let effectId: Int = row["effect_id"]
                    modifiersByEffect[effectId, default: []].append(DogmaModifierDetail(
                        effectId: effectId,
                        domain: row["domain"] ?? "",
                        function: row["func"] ?? "",
                        groupId: row["group_id"],
                        modifiedAttrId: row["modified_attr_id"],
                        modifiedAttrName: row["modified_attr_name"],
                        modifyingAttrId: row["modifying_attr_id"],
                        modifyingAttrName: row["modifying_attr_name"],
                        operation: row["operation"],
                        skillTypeId: row["skill_type_id"],
                        skillName: row["skill_name"]
                    ))
                }
            }

            return effectRows.map { row in
                let effectId: Int = row["effect_id"]
                return TypeEffectDetail(
                    typeId: row["type_id"],
                    effectId: effectId,
                    name: row["name"],
                    displayName: row["display_name"],
                    effectCategory: row["effect_category"],
                    modifiers: modifiersByEffect[effectId] ?? []
                )
            }
        }
    }

    // MARK: - Skill Requirements

    public func skillRequirements(typeId: Int) async throws -> [(skillId: Int, level: Int)] {
        try await dbReader.read { db in
            let sql = "SELECT skill_id, level FROM skill_requirements WHERE type_id = ? ORDER BY level"
            return try Row.fetchAll(db, sql: sql, arguments: [typeId])
                .map { (skillId: $0["skill_id"], level: $0["level"]) }
        }
    }

    // MARK: - Batch attribute maps

    /// Returns typeId → {attributeId → value} for all requested types in one query.
    public func typeAttributeMaps(typeIds: Set<Int>) async throws -> [Int: [Int: Double]] {
        guard !typeIds.isEmpty else { return [:] }
        return try await dbReader.read { db in
            let sorted = typeIds.sorted()
            let placeholders = sorted.map { _ in "?" }.joined(separator: ",")
            let sql = "SELECT type_id, attribute_id, value FROM type_attributes WHERE type_id IN (\(placeholders))"
            var result: [Int: [Int: Double]] = Dictionary(uniqueKeysWithValues: sorted.map { ($0, [:]) })
            for row in try Row.fetchAll(db, sql: sql, arguments: StatementArguments(sorted)) {
                let tid: Int = row["type_id"]
                let aid: Int = row["attribute_id"]
                let val: Double = row["value"]
                result[tid, default: [:]][aid] = val
            }
            return result
        }
    }

    // MARK: - Type Profiles (attrs + effect IDs + groupId + requiredSkills)

    /// Returns typeId → TypeProfile for all requested types.
    /// Includes dogma attributes, effect IDs, group ID, and skill requirements.
    /// Used by DogmaEngine for both module→ship and skill→module modifier chains.
    public func typeProfiles(typeIds: Set<Int>) async throws -> [Int: TypeProfile] {
        guard !typeIds.isEmpty else { return [:] }
        return try await dbReader.read { db in
            let sorted = typeIds.sorted()
            let placeholders = sorted.map { _ in "?" }.joined(separator: ",")

            // Group IDs
            var groupByType: [Int: Int] = [:]
            let grpSql = "SELECT id, group_id FROM types WHERE id IN (\(placeholders))"
            for row in try Row.fetchAll(db, sql: grpSql, arguments: StatementArguments(sorted)) {
                groupByType[row["id"] as Int] = row["group_id"]
            }

            // Dogma attributes
            var attrsByType: [Int: [Int: Double]] = Dictionary(uniqueKeysWithValues: sorted.map { ($0, [:]) })
            let attrSql = "SELECT type_id, attribute_id, value FROM type_attributes WHERE type_id IN (\(placeholders))"
            for row in try Row.fetchAll(db, sql: attrSql, arguments: StatementArguments(sorted)) {
                let tid: Int = row["type_id"]
                attrsByType[tid, default: [:]][row["attribute_id"] as Int] = row["value"]
            }

            // Effect IDs
            var effectsByType: [Int: Set<Int>] = Dictionary(uniqueKeysWithValues: sorted.map { ($0, []) })
            let effSql = "SELECT type_id, effect_id FROM type_effects WHERE type_id IN (\(placeholders))"
            for row in try Row.fetchAll(db, sql: effSql, arguments: StatementArguments(sorted)) {
                let tid: Int = row["type_id"]
                effectsByType[tid, default: []].insert(row["effect_id"] as Int)
            }

            // Required skill IDs
            var skillsByType: [Int: Set<Int>] = [:]
            let skillSql = "SELECT type_id, skill_id FROM skill_requirements WHERE type_id IN (\(placeholders))"
            for row in try Row.fetchAll(db, sql: skillSql, arguments: StatementArguments(sorted)) {
                let tid: Int = row["type_id"]
                skillsByType[tid, default: []].insert(row["skill_id"] as Int)
            }

            var result: [Int: TypeProfile] = [:]
            for tid in sorted {
                result[tid] = TypeProfile(
                    attrs: attrsByType[tid] ?? [:],
                    effectIds: effectsByType[tid] ?? [],
                    groupId: groupByType[tid] ?? 0,
                    requiredSkillIds: skillsByType[tid] ?? []
                )
            }
            return result
        }
    }

    // MARK: - Effect Modifiers

    /// Returns effectId → [ModifierRow] for all requested effect IDs.
    /// Used by DogmaEngine to apply skill/ship bonus modifier chains.
    public func effectModifiers(effectIds: Set<Int>) async throws -> [Int: [ModifierRow]] {
        guard !effectIds.isEmpty else { return [:] }
        return try await dbReader.read { db in
            let sorted = effectIds.sorted()
            let placeholders = sorted.map { _ in "?" }.joined(separator: ",")
            let sql = """
                SELECT dm.effect_id, dm.domain, dm.func, dm.group_id, dm.modified_attr_id,
                       dm.modifying_attr_id, dm.operation, dm.skill_type_id,
                       de.effect_category
                FROM dogma_modifiers dm
                JOIN dogma_effects de ON de.id = dm.effect_id
                WHERE dm.effect_id IN (\(placeholders))
                """
            var result: [Int: [ModifierRow]] = [:]
            for row in try Row.fetchAll(db, sql: sql, arguments: StatementArguments(sorted)) {
                let eid: Int = row["effect_id"]
                result[eid, default: []].append(ModifierRow(
                    domain: row["domain"] ?? "",
                    function_: row["func"] ?? "",
                    groupId: row["group_id"],
                    modifiedAttrId: row["modified_attr_id"],
                    modifyingAttrId: row["modifying_attr_id"],
                    operation: row["operation"],
                    skillTypeId: row["skill_type_id"],
                    effectCategory: row["effect_category"] ?? 4
                ))
            }
            return result
        }
    }

    // MARK: - Compatible Charges

    /// Returns all published charge types compatible with a weapon (turret or launcher).
    /// Reads the weapon's chargeGroup attributes (604–606, 609) and chargeSize (128),
    /// then returns types in those groups with a matching chargeSize.
    public func compatibleCharges(weaponTypeId: Int) async throws -> [ItemType] {
        return try await dbReader.read { db in
            // Step 1 — charge group IDs declared on the weapon
            let groupSql = """
                SELECT CAST(value AS INTEGER) AS gid
                FROM type_attributes
                WHERE type_id = ? AND attribute_id IN (604, 605, 606, 609) AND value > 0
                """
            let groupIds = try Row.fetchAll(db, sql: groupSql, arguments: [weaponTypeId])
                .map { row -> Int in row["gid"] }
            guard !groupIds.isEmpty else { return [] }

            // Step 2 — charge size required by the weapon
            let sizeSql = "SELECT value FROM type_attributes WHERE type_id = ? AND attribute_id = 128 LIMIT 1"
            let chargeSize: Double? = try Row.fetchOne(db, sql: sizeSql, arguments: [weaponTypeId])
                .map { $0["value"] }

            // Step 3 — types in those groups, filtered by chargeSize when present
            let gp = groupIds.map { _ in "?" }.joined(separator: ",")
            if let sz = chargeSize {
                let sql = """
                    SELECT t.* FROM types t
                    JOIN type_attributes ta ON ta.type_id = t.id AND ta.attribute_id = 128
                    WHERE t.published = 1 AND t.group_id IN (\(gp)) AND ta.value = ?
                    ORDER BY t.name LIMIT 300
                    """
                let args = StatementArguments(groupIds) + StatementArguments([sz])
                return try TypeRecord.fetchAll(db, sql: sql, arguments: args).map { $0.toDomain() }
            } else {
                let sql = "SELECT * FROM types WHERE published = 1 AND group_id IN (\(gp)) ORDER BY name LIMIT 300"
                return try TypeRecord.fetchAll(db, sql: sql, arguments: StatementArguments(groupIds)).map { $0.toDomain() }
            }
        }
    }

    // MARK: - FTS Search

    /// Full-text search over type names (FTS5 prefix match).
    /// Wraps each token in quotes to prevent FTS5 injection.
    public func search(_ query: String) async throws -> [ItemType] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        return try await dbReader.read { db in
            let pattern = trimmed
                .split(separator: " ", omittingEmptySubsequences: true)
                .map { "\"\($0)\"*" }
                .joined(separator: " ")

            let sql = """
                SELECT t.* FROM types t
                JOIN types_fts ON types_fts.rowid = t.id
                WHERE types_fts MATCH ? AND t.published = 1
                ORDER BY rank
                LIMIT 100
                """
            return try TypeRecord.fetchAll(db, sql: sql, arguments: [pattern])
                .map { $0.toDomain() }
        }
    }
}
