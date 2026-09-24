import GRDB
import Domain
import Foundation

/// In-memory cache for SDE lookups that never change within a session
/// (categories, groups, market groups, type names, type profiles).
/// The SDE file is immutable after install, so caching by ID is always safe.
private actor SDEStaticCache {
    static let shared = SDEStaticCache()

    var allCategories: [ItemCategory]?
    var categoryById: [Int: ItemCategory] = [:]
    var groupsByCategoryId: [Int: [ItemGroup]] = [:]
    var groupById: [Int: ItemGroup] = [:]
    var marketGroupById: [Int: MarketGroup] = [:]
    var marketGroupsByParentId: [Int?: [MarketGroup]] = [:]
    var representativeByCategory: [Int: Int]?
    var representativeByGroup: [Int: Int]?
    var representativeByMarketGroup: [Int: Int]?
    var typeById: [Int: ItemType] = [:]
    var typeProfileById: [Int: TypeProfile] = [:]
    var skillRequirementsByTypeId: [Int: [(skillId: Int, level: Int)]] = [:]
    var effectModifiersByEffectId: [Int: [ModifierRow]] = [:]
    var compatibleChargesByWeaponTypeId: [Int: [ItemType]] = [:]

    func setAllCategories(_ value: [ItemCategory]) { allCategories = value }
    func setCategory(_ value: ItemCategory, id: Int) { categoryById[id] = value }
    func setGroups(_ value: [ItemGroup], categoryId: Int) { groupsByCategoryId[categoryId] = value }
    func setGroup(_ value: ItemGroup, id: Int) { groupById[id] = value }
    func mergeGroups(_ value: [Int: ItemGroup]) { groupById.merge(value) { _, new in new } }
    func setMarketGroup(_ value: MarketGroup, id: Int) { marketGroupById[id] = value }
    func setMarketGroups(_ value: [MarketGroup], parentId: Int?) { marketGroupsByParentId[parentId] = value }
    func setRepresentativeByCategory(_ value: [Int: Int]) { representativeByCategory = value }
    func setRepresentativeByGroup(_ value: [Int: Int]) { representativeByGroup = value }
    func setRepresentativeByMarketGroup(_ value: [Int: Int]) { representativeByMarketGroup = value }
    func mergeTypes(_ value: [Int: ItemType]) { typeById.merge(value) { _, new in new } }
    func mergeTypeProfiles(_ value: [Int: TypeProfile]) { typeProfileById.merge(value) { _, new in new } }
    func mergeSkillRequirements(_ value: [Int: [(skillId: Int, level: Int)]]) { skillRequirementsByTypeId.merge(value) { _, new in new } }
    func mergeEffectModifiers(_ value: [Int: [ModifierRow]]) { effectModifiersByEffectId.merge(value) { _, new in new } }
    func setCompatibleCharges(_ value: [ItemType], weaponTypeId: Int) { compatibleChargesByWeaponTypeId[weaponTypeId] = value }

    func reset() {
        allCategories = nil
        categoryById.removeAll()
        groupsByCategoryId.removeAll()
        groupById.removeAll()
        marketGroupById.removeAll()
        marketGroupsByParentId.removeAll()
        representativeByCategory = nil
        representativeByGroup = nil
        representativeByMarketGroup = nil
        typeById.removeAll()
        typeProfileById.removeAll()
        skillRequirementsByTypeId.removeAll()
        effectModifiersByEffectId.removeAll()
        compatibleChargesByWeaponTypeId.removeAll()
    }
}

/// Read-only access to the SDE SQLite database.
/// Sendable struct (DatabaseReader is Sendable in GRDB 7) — safe to share across
/// actors and concurrency contexts without wrapping in an actor.
public struct SDERepository: Sendable {
    private let dbReader: any DatabaseReader
    private let cache = SDEStaticCache.shared

    public init(dbReader: any DatabaseReader) {
        self.dbReader = dbReader
    }

    /// Opens the bundled SDE database off the main thread.
    public static func openBundled() async throws -> SDERepository {
        let pool = try await Task.detached(priority: .userInitiated) {
            try SDEDatabase.openBundled()
        }.value
        return SDERepository(dbReader: pool)
    }

    public static func clearSharedCache() async {
        await SDEStaticCache.shared.reset()
    }

    // MARK: - Categories

    public func categories() async throws -> [ItemCategory] {
        if let cached = await cache.allCategories { return cached }
        let result = try await dbReader.read { db in
            try CategoryRecord
                .filter(Column("published") == true)
                .order(Column("name"))
                .fetchAll(db)
                .map { $0.toDomain() }
        }
        await cache.setAllCategories(result)
        return result
    }

    // MARK: - Categories (by ID)

    public func category(id: Int) async throws -> ItemCategory? {
        if let cached = await cache.categoryById[id] { return cached }
        let result = try await dbReader.read { db in
            try CategoryRecord.fetchOne(db, key: id)?.toDomain()
        }
        if let result { await cache.setCategory(result, id: id) }
        return result
    }

    // MARK: - Representative icons

    /// Returns {categoryId: typeId} — one representative published typeID per category.
    /// Used to display real EVE item icons for category rows via images.evetech.net.
    public func representativeTypeIdsByCategory() async throws -> [Int: Int] {
        if let cached = await cache.representativeByCategory { return cached }
        let result = try await dbReader.read { db in
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
        await cache.setRepresentativeByCategory(result)
        return result
    }

    /// Returns {groupId: typeId} — one representative published typeID per group.
    public func representativeTypeIdsByGroup() async throws -> [Int: Int] {
        if let cached = await cache.representativeByGroup { return cached }
        let result = try await dbReader.read { db in
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
        await cache.setRepresentativeByGroup(result)
        return result
    }

    // MARK: - Groups

    public func group(id: Int) async throws -> ItemGroup? {
        if let cached = await cache.groupById[id] { return cached }
        let result = try await dbReader.read { db in
            try GroupRecord.fetchOne(db, key: id)?.toDomain()
        }
        if let result { await cache.setGroup(result, id: id) }
        return result
    }

    public func groups(ids: Set<Int>) async throws -> [Int: ItemGroup] {
        guard !ids.isEmpty else { return [:] }

        let cached = await cache.groupById
        let missingIds = ids.subtracting(cached.keys)
        if missingIds.isEmpty {
            return cached.filter { ids.contains($0.key) }
        }

        let fetched = try await dbReader.read { db in
            let placeholders = Array(repeating: "?", count: missingIds.count).joined(separator: ",")
            let sql = "SELECT * FROM groups WHERE id IN (\(placeholders))"
            let arguments = StatementArguments(missingIds.sorted())
            let groups = try GroupRecord.fetchAll(db, sql: sql, arguments: arguments).map { $0.toDomain() }
            return Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        }

        await cache.mergeGroups(fetched)

        var result = cached.filter { ids.contains($0.key) }
        result.merge(fetched) { _, new in new }
        return result
    }

    public func groups(categoryId: Int) async throws -> [ItemGroup] {
        if let cached = await cache.groupsByCategoryId[categoryId] { return cached }
        let result = try await dbReader.read { db in
            try GroupRecord
                .filter(Column("category_id") == categoryId && Column("published") == true)
                .order(Column("name"))
                .fetchAll(db)
                .map { $0.toDomain() }
        }
        await cache.setGroups(result, categoryId: categoryId)
        return result
    }

    // MARK: - Market Groups

    public func marketGroup(id: Int) async throws -> MarketGroup? {
        if let cached = await cache.marketGroupById[id] { return cached }
        let result = try await dbReader.read { db in
            try MarketGroupRecord.fetchOne(db, key: id)?.toDomain()
        }
        if let result { await cache.setMarketGroup(result, id: id) }
        return result
    }

    public func marketGroups(parentId: Int?) async throws -> [MarketGroup] {
        if let cached = await cache.marketGroupsByParentId[parentId] { return cached }
        let result = try await dbReader.read { db in
            let request: QueryInterfaceRequest<MarketGroupRecord>
            if let parentId {
                request = MarketGroupRecord
                    .filter(Column("parent_id") == parentId)
                    .order(Column("name"))
            } else {
                request = MarketGroupRecord
                    .filter(Column("parent_id") == nil)
                    .order(Column("name"))
            }
            return try request.fetchAll(db).map { $0.toDomain() }
        }
        await cache.setMarketGroups(result, parentId: parentId)
        return result
    }

    public func marketGroupPath(id: Int) async throws -> [MarketGroup] {
        try await dbReader.read { db in
            var result: [MarketGroup] = []
            var currentId: Int? = id
            var visited: Set<Int> = []

            while let id = currentId, !visited.contains(id) {
                visited.insert(id)
                guard let group = try MarketGroupRecord.fetchOne(db, key: id) else { break }
                result.append(group.toDomain())
                currentId = group.parentId
            }

            return result.reversed()
        }
    }

    public func representativeTypeIdsByMarketGroup() async throws -> [Int: Int] {
        if let cached = await cache.representativeByMarketGroup { return cached }
        let result = try await dbReader.read { db in
            let sql = """
                SELECT market_group_id, MIN(id) AS type_id
                FROM types
                WHERE published = 1 AND market_group_id IS NOT NULL
                GROUP BY market_group_id
                """
            var result: [Int: Int] = [:]
            for row in try Row.fetchAll(db, sql: sql) {
                result[row["market_group_id"]] = row["type_id"]
            }
            return result
        }
        await cache.setRepresentativeByMarketGroup(result)
        return result
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

    public func types(marketGroupId: Int) async throws -> [ItemType] {
        try await dbReader.read { db in
            try TypeRecord
                .filter(Column("market_group_id") == marketGroupId && Column("published") == true)
                .order(Column("name"))
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func type(id: Int) async throws -> ItemType? {
        if let cached = await cache.typeById[id] { return cached }
        let result = try await dbReader.read { db in
            try TypeRecord.fetchOne(db, key: id)?.toDomain()
        }
        if let result { await cache.mergeTypes([id: result]) }
        return result
    }

    public func variations(typeId: Int) async throws -> [ItemType] {
        try await dbReader.read { db in
            guard let type = try TypeRecord.fetchOne(db, key: typeId) else { return [] }
            let rootId = type.variationParentId ?? type.id
            return try TypeRecord
                .filter((Column("id") == rootId || Column("variation_parent_id") == rootId) && Column("published") == true)
                .order(Column("meta_group_id"), Column("name"))
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func typeTraits(typeId: Int) async throws -> [TypeTrait] {
        try await dbReader.read { db in
            try TypeTraitRecord
                .filter(Column("type_id") == typeId)
                .order(Column("skill_id"), Column("sort"))
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    /// Batch lookup — returns typeId → ItemType for all requested IDs in one query.
    /// IDs already in the static cache are served without touching the database.
    public func types(ids: Set<Int>) async throws -> [Int: ItemType] {
        guard !ids.isEmpty else { return [:] }
        let cached = await cache.typeById
        var result = cached.filter { ids.contains($0.key) }
        let missing = ids.subtracting(result.keys)
        guard !missing.isEmpty else { return result }

        let fetched = try await dbReader.read { db in
            let sorted = missing.sorted()
            let placeholders = sorted.map { _ in "?" }.joined(separator: ",")
            let sql = "SELECT * FROM types WHERE id IN (\(placeholders))"
            var fetched: [Int: ItemType] = [:]
            for record in try TypeRecord.fetchAll(db, sql: sql, arguments: StatementArguments(sorted)) {
                fetched[record.id] = record.toDomain()
            }
            return fetched
        }
        await cache.mergeTypes(fetched)
        result.merge(fetched) { _, new in new }
        return result
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
                    da.icon_id,
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
                            iconId: row["icon_id"],
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
        if let cached = await cache.skillRequirementsByTypeId[typeId] { return cached }
        let result = try await skillRequirements(typeIds: [typeId])[typeId] ?? []
        await cache.mergeSkillRequirements([typeId: result])
        return result
    }

    public func skillRequirements(typeIds: Set<Int>) async throws -> [Int: [(skillId: Int, level: Int)]] {
        guard !typeIds.isEmpty else { return [:] }

        let cached = await cache.skillRequirementsByTypeId
        var result = cached.filter { typeIds.contains($0.key) }
        let missing = typeIds.subtracting(result.keys)
        guard !missing.isEmpty else { return result }

        let fetched = try await dbReader.read { db in
            let sorted = missing.sorted()
            let placeholders = sorted.map { _ in "?" }.joined(separator: ",")
            let sql = """
                SELECT type_id, skill_id, level
                FROM skill_requirements
                WHERE type_id IN (\(placeholders))
                ORDER BY type_id, level
                """
            var rowsByType = Dictionary(uniqueKeysWithValues: sorted.map { ($0, [(skillId: Int, level: Int)]()) })
            for row in try Row.fetchAll(db, sql: sql, arguments: StatementArguments(sorted)) {
                let typeId: Int = row["type_id"]
                rowsByType[typeId, default: []].append((skillId: row["skill_id"], level: row["level"]))
            }
            return rowsByType
        }

        await cache.mergeSkillRequirements(fetched)
        result.merge(fetched) { _, new in new }
        return result
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
        let cached = await cache.typeProfileById
        var result = cached.filter { typeIds.contains($0.key) }
        let missing = typeIds.subtracting(result.keys)
        guard !missing.isEmpty else { return result }

        let fetched = try await dbReader.read { db in
            let sorted = missing.sorted()
            let placeholders = sorted.map { _ in "?" }.joined(separator: ",")

            // Group IDs and physical columns that are part of dogma math.
            var groupByType: [Int: Int] = [:]
            var massByType: [Int: Double] = [:]
            let grpSql = "SELECT id, group_id, mass FROM types WHERE id IN (\(placeholders))"
            for row in try Row.fetchAll(db, sql: grpSql, arguments: StatementArguments(sorted)) {
                let typeId = row["id"] as Int
                groupByType[typeId] = row["group_id"]
                if let mass = row["mass"] as Double? {
                    massByType[typeId] = mass
                }
            }

            // Dogma attributes
            var attrsByType: [Int: [Int: Double]] = Dictionary(uniqueKeysWithValues: sorted.map { ($0, [:]) })
            let attrSql = "SELECT type_id, attribute_id, value FROM type_attributes WHERE type_id IN (\(placeholders))"
            for row in try Row.fetchAll(db, sql: attrSql, arguments: StatementArguments(sorted)) {
                let tid: Int = row["type_id"]
                attrsByType[tid, default: [:]][row["attribute_id"] as Int] = row["value"]
            }
            for (tid, mass) in massByType {
                attrsByType[tid, default: [:]][4] = mass
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
        await cache.mergeTypeProfiles(fetched)
        result.merge(fetched) { _, new in new }
        return result
    }

    // MARK: - Effect Modifiers

    /// Returns effectId → [ModifierRow] for all requested effect IDs.
    /// Used by DogmaEngine to apply skill/ship bonus modifier chains.
    public func effectModifiers(effectIds: Set<Int>) async throws -> [Int: [ModifierRow]] {
        guard !effectIds.isEmpty else { return [:] }

        let cached = await cache.effectModifiersByEffectId
        var result = cached.filter { effectIds.contains($0.key) }
        let missing = effectIds.subtracting(result.keys)
        guard !missing.isEmpty else { return result }

        let fetched = try await dbReader.read { db in
            let sorted = missing.sorted()
            let placeholders = sorted.map { _ in "?" }.joined(separator: ",")
            let sql = """
                SELECT dm.effect_id, dm.domain, dm.func, dm.group_id, dm.modified_attr_id,
                       dm.modifying_attr_id, dm.operation, dm.skill_type_id,
                       de.effect_category
                FROM dogma_modifiers dm
                JOIN dogma_effects de ON de.id = dm.effect_id
                WHERE dm.effect_id IN (\(placeholders))
                """
            var result = Dictionary(uniqueKeysWithValues: sorted.map { ($0, [ModifierRow]()) })
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
        await cache.mergeEffectModifiers(fetched)
        result.merge(fetched) { _, new in new }
        return result
    }

    // MARK: - Compatible Charges

    /// Returns all published charge types compatible with a weapon (turret or launcher).
    /// Reads the weapon's chargeGroup attributes (604–606, 609) and chargeSize (128),
    /// then returns types in those groups with a matching chargeSize.
    public func compatibleCharges(weaponTypeId: Int) async throws -> [ItemType] {
        if let cached = await cache.compatibleChargesByWeaponTypeId[weaponTypeId] { return cached }

        let result: [ItemType] = try await dbReader.read { db in
            // Step 1 — charge group IDs declared on the weapon
            let groupSql = """
                SELECT CAST(value AS INTEGER) AS gid
                FROM type_attributes
                WHERE type_id = ? AND attribute_id IN (604, 605, 606, 609) AND value > 0
                """
            let groupIds = try Row.fetchAll(db, sql: groupSql, arguments: [weaponTypeId])
                .map { row -> Int in row["gid"] }
            guard !groupIds.isEmpty else { return [ItemType]() }

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
        await cache.setCompatibleCharges(result, weaponTypeId: weaponTypeId)
        return result
    }

    public func compatibleChargeGroups(weaponTypeId: Int) async throws -> [ItemGroup] {
        try await dbReader.read { db in
            let sql = """
                SELECT DISTINCT g.*
                FROM type_attributes ta
                JOIN groups g ON g.id = CAST(ta.value AS INTEGER)
                WHERE ta.type_id = ? AND ta.attribute_id IN (604, 605, 606, 609) AND ta.value > 0
                ORDER BY g.name
                """
            return try GroupRecord.fetchAll(db, sql: sql, arguments: [weaponTypeId])
                .map { $0.toDomain() }
        }
    }

    public func affectingTypes(targetGroupId: Int, limit: Int = 80) async throws -> [TypeInfluence] {
        try await dbReader.read { db in
            let sql = """
                SELECT
                    t.*,
                    c.name AS category_name,
                    g.name AS source_group_name,
                    COALESCE(da.display_name, da.name) AS modified_attribute_name
                FROM dogma_modifiers dm
                JOIN type_effects te ON te.effect_id = dm.effect_id
                JOIN types t ON t.id = te.type_id
                JOIN groups g ON g.id = t.group_id
                JOIN categories c ON c.id = g.category_id
                LEFT JOIN dogma_attributes da ON da.id = dm.modified_attr_id
                WHERE dm.group_id = ? AND t.published = 1
                ORDER BY c.name, g.name, t.name
                """

            var entries: [Int: (record: TypeRecord, categoryName: String, groupName: String, attrs: Set<String>)] = [:]
            for row in try Row.fetchAll(db, sql: sql, arguments: [targetGroupId]) {
                let record = try TypeRecord(row: row)
                let attributeName: String = row["modified_attribute_name"] ?? "Attribute"
                if var existing = entries[record.id] {
                    existing.attrs.insert(attributeName)
                    entries[record.id] = existing
                } else {
                    entries[record.id] = (
                        record,
                        row["category_name"] ?? "Unknown",
                        row["source_group_name"] ?? "Unknown",
                        [attributeName]
                    )
                }
            }

            return entries.values
                .sorted {
                    if $0.categoryName != $1.categoryName { return $0.categoryName < $1.categoryName }
                    if $0.groupName != $1.groupName { return $0.groupName < $1.groupName }
                    return $0.record.name.localizedStandardCompare($1.record.name) == .orderedAscending
                }
                .prefix(limit)
                .map {
                    TypeInfluence(
                        type: $0.record.toDomain(),
                        categoryName: $0.categoryName,
                        groupName: $0.groupName,
                        modifiedAttributes: $0.attrs.sorted()
                    )
                }
        }
    }

    public func typesAffectedBySkill(skillTypeId: Int, limit: Int = 180) async throws -> [TypeInfluence] {
        try await dbReader.read { db in
            let sql = """
                SELECT
                    t.*,
                    c.name AS category_name,
                    g.name AS target_group_name,
                    COALESCE(da.display_name, da.name) AS modified_attribute_name
                FROM dogma_modifiers dm
                JOIN type_effects te ON te.effect_id = dm.effect_id
                JOIN types t ON t.id = te.type_id
                JOIN groups g ON g.id = t.group_id
                JOIN categories c ON c.id = g.category_id
                LEFT JOIN dogma_attributes da ON da.id = dm.modified_attr_id
                WHERE dm.skill_type_id = ?
                  AND t.published = 1
                  AND c.id IN (6, 7, 18, 32, 66)
                ORDER BY c.name, g.name, t.name
                """

            var entries: [Int: (record: TypeRecord, categoryName: String, groupName: String, attrs: Set<String>)] = [:]
            for row in try Row.fetchAll(db, sql: sql, arguments: [skillTypeId]) {
                let record = try TypeRecord(row: row)
                let attributeName: String = row["modified_attribute_name"] ?? "Attribute"
                if var existing = entries[record.id] {
                    existing.attrs.insert(attributeName)
                    entries[record.id] = existing
                } else {
                    entries[record.id] = (
                        record,
                        row["category_name"] ?? "Unknown",
                        row["target_group_name"] ?? "Unknown",
                        [attributeName]
                    )
                }
            }

            return entries.values
                .sorted {
                    if $0.categoryName != $1.categoryName { return $0.categoryName < $1.categoryName }
                    if $0.groupName != $1.groupName { return $0.groupName < $1.groupName }
                    return $0.record.name.localizedStandardCompare($1.record.name) == .orderedAscending
                }
                .prefix(limit)
                .map {
                    TypeInfluence(
                        type: $0.record.toDomain(),
                        categoryName: $0.categoryName,
                        groupName: $0.groupName,
                        modifiedAttributes: $0.attrs.sorted()
                    )
                }
        }
    }

    public func skillsAffectingGroups(groupIds: Set<Int>, limit: Int = 160) async throws -> [SkillInfluence] {
        guard !groupIds.isEmpty else { return [] }

        return try await dbReader.read { db in
            let sorted = groupIds.sorted()
            let placeholders = sorted.map { _ in "?" }.joined(separator: ",")
            let sql = """
                SELECT
                    s.*,
                    g.name AS target_group_name,
                    COALESCE(da.display_name, da.name) AS modified_attribute_name
                FROM dogma_modifiers dm
                JOIN types s ON s.id = dm.skill_type_id
                JOIN groups g ON g.id = dm.group_id
                LEFT JOIN dogma_attributes da ON da.id = dm.modified_attr_id
                WHERE dm.group_id IN (\(placeholders))
                  AND dm.skill_type_id IS NOT NULL
                  AND s.published = 1
                ORDER BY s.name, g.name
                """

            var entries: [Int: (record: TypeRecord, groups: Set<String>, attrs: Set<String>)] = [:]
            for row in try Row.fetchAll(db, sql: sql, arguments: StatementArguments(sorted)) {
                let record = try TypeRecord(row: row)
                let groupName: String = row["target_group_name"] ?? "Unknown"
                let attributeName: String = row["modified_attribute_name"] ?? "Attribute"
                if var existing = entries[record.id] {
                    existing.groups.insert(groupName)
                    existing.attrs.insert(attributeName)
                    entries[record.id] = existing
                } else {
                    entries[record.id] = (record, [groupName], [attributeName])
                }
            }

            return entries.values
                .sorted { $0.record.name.localizedStandardCompare($1.record.name) == .orderedAscending }
                .prefix(limit)
                .map {
                    SkillInfluence(
                        skill: $0.record.toDomain(),
                        affectedGroups: $0.groups.sorted(),
                        modifiedAttributes: $0.attrs.sorted()
                    )
                }
        }
    }

    public func skillsModifyingTypes(typeIds: Set<Int>, limit: Int = 160) async throws -> [SkillInfluence] {
        guard !typeIds.isEmpty else { return [] }

        return try await dbReader.read { db in
            let sorted = typeIds.sorted()
            let placeholders = sorted.map { _ in "?" }.joined(separator: ",")
            let sql = """
                SELECT
                    s.*,
                    t.name AS source_type_name,
                    COALESCE(da.display_name, da.name) AS modified_attribute_name
                FROM type_effects te
                JOIN dogma_modifiers dm ON dm.effect_id = te.effect_id
                JOIN types s ON s.id = dm.skill_type_id
                JOIN types t ON t.id = te.type_id
                LEFT JOIN dogma_attributes da ON da.id = dm.modified_attr_id
                WHERE te.type_id IN (\(placeholders))
                  AND dm.skill_type_id IS NOT NULL
                  AND s.published = 1
                ORDER BY s.name, t.name
                """

            var entries: [Int: (record: TypeRecord, sources: Set<String>, attrs: Set<String>)] = [:]
            for row in try Row.fetchAll(db, sql: sql, arguments: StatementArguments(sorted)) {
                let record = try TypeRecord(row: row)
                let sourceName: String = row["source_type_name"] ?? "Fit Item"
                let attributeName: String = row["modified_attribute_name"] ?? "Attribute"
                if var existing = entries[record.id] {
                    existing.sources.insert(sourceName)
                    existing.attrs.insert(attributeName)
                    entries[record.id] = existing
                } else {
                    entries[record.id] = (record, [sourceName], [attributeName])
                }
            }

            return entries.values
                .sorted { $0.record.name.localizedStandardCompare($1.record.name) == .orderedAscending }
                .prefix(limit)
                .map {
                    SkillInfluence(
                        skill: $0.record.toDomain(),
                        affectedGroups: $0.sources.sorted(),
                        modifiedAttributes: $0.attrs.sorted()
                    )
                }
        }
    }

    public func skillsModifyingFittedTypes(
        sourceTypeIds: Set<Int>,
        targetTypeIds: Set<Int>,
        limit: Int = 160
    ) async throws -> [SkillInfluence] {
        guard !sourceTypeIds.isEmpty, !targetTypeIds.isEmpty else { return [] }

        return try await dbReader.read { db in
            let sources = sourceTypeIds.sorted()
            let targets = targetTypeIds.sorted()
            let sourcePlaceholders = sources.map { _ in "?" }.joined(separator: ",")
            let targetPlaceholders = targets.map { _ in "?" }.joined(separator: ",")
            let arguments = StatementArguments(sources + targets)
            let sql = """
                SELECT
                    s.*,
                    source.name AS source_type_name,
                    target.name AS target_type_name,
                    COALESCE(da.display_name, da.name) AS modified_attribute_name
                FROM type_effects te
                JOIN dogma_modifiers dm ON dm.effect_id = te.effect_id
                JOIN skill_requirements sr ON sr.skill_id = dm.skill_type_id
                JOIN types source ON source.id = te.type_id
                JOIN types target ON target.id = sr.type_id
                JOIN types s ON s.id = dm.skill_type_id
                LEFT JOIN dogma_attributes da ON da.id = dm.modified_attr_id
                WHERE te.type_id IN (\(sourcePlaceholders))
                  AND sr.type_id IN (\(targetPlaceholders))
                  AND dm.skill_type_id IS NOT NULL
                  AND s.published = 1
                ORDER BY s.name, source.name, target.name
                """

            var entries: [Int: (record: TypeRecord, sources: Set<String>, attrs: Set<String>)] = [:]
            for row in try Row.fetchAll(db, sql: sql, arguments: arguments) {
                let record = try TypeRecord(row: row)
                let sourceName: String = row["source_type_name"] ?? "Fit Item"
                let targetName: String = row["target_type_name"] ?? "Target Item"
                let attributeName: String = row["modified_attribute_name"] ?? "Attribute"
                let sourceLabel = "\(sourceName) -> \(targetName)"
                if var existing = entries[record.id] {
                    existing.sources.insert(sourceLabel)
                    existing.attrs.insert(attributeName)
                    entries[record.id] = existing
                } else {
                    entries[record.id] = (record, [sourceLabel], [attributeName])
                }
            }

            return entries.values
                .sorted { $0.record.name.localizedStandardCompare($1.record.name) == .orderedAscending }
                .prefix(limit)
                .map {
                    SkillInfluence(
                        skill: $0.record.toDomain(),
                        affectedGroups: $0.sources.sorted(),
                        modifiedAttributes: $0.attrs.sorted()
                    )
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
