import GRDB
import Foundation

struct SDEImporter {
    let sdeRoot: URL
    let db: DatabaseQueue

    // MARK: - Public entry point

    func importAll() async throws {
        print("→ Importing categories…")
        print("  \(try await importCategories())")

        print("→ Importing groups…")
        print("  \(try await importGroups())")

        print("→ Importing market groups…")
        print("  \(try await importMarketGroups())")

        print("→ Importing types…")
        print("  \(try await importTypes())")

        print("→ Importing type bonuses…")
        print("  \(try await importTypeBonuses())")

        print("→ Importing dogma attributes…")
        print("  \(try await importDogmaAttributes())")

        print("→ Importing dogma effects…")
        print("  \(try await importDogmaEffects())")

        print("→ Importing type dogma…")
        let (ta, te) = try await importTypeDogma()
        print("  \(ta) type-attributes, \(te) type-effects")

        print("→ Deriving skill requirements…")
        print("  \(try await deriveSkillRequirements()) rows")

        print("→ Building FTS index…")
        try await buildFTS()
        print("  done")
    }

    // MARK: - Importers

    private func importCategories() async throws -> String {
        guard let url = findFile("categories.jsonl") else {
            return "⚠️  categories.jsonl not found"
        }
        let records = try parseJSONL(url, as: SDECategory.self)
        try await db.write { database in
            for r in records {
                try database.execute(
                    sql: "INSERT OR IGNORE INTO categories (id, name, published) VALUES (?, ?, ?)",
                    arguments: [r.id, r.name?.english ?? "", r.published == true ? 1 : 0]
                )
            }
        }
        return "\(records.count) categories"
    }

    private func importGroups() async throws -> String {
        guard let url = findFile("groups.jsonl") else {
            return "⚠️  groups.jsonl not found"
        }
        let records = try parseJSONL(url, as: SDEGroup.self)
        try await db.write { database in
            for r in records {
                guard let categoryID = r.categoryID else { continue }
                try database.execute(
                    sql: "INSERT OR IGNORE INTO groups (id, category_id, name, published) VALUES (?, ?, ?, ?)",
                    arguments: [r.id, categoryID, r.name?.english ?? "", r.published == true ? 1 : 0]
                )
            }
        }
        return "\(records.count) groups"
    }

    private func importMarketGroups() async throws -> String {
        guard let url = findFile("marketGroups.jsonl") else {
            return "⚠️  marketGroups.jsonl not found"
        }
        let records = try parseJSONL(url, as: SDEMarketGroup.self)
        try await db.write { database in
            for r in records {
                try database.execute(
                    sql: """
                        INSERT OR IGNORE INTO market_groups
                        (id, parent_id, name, description, icon_id, has_types)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        r.id, r.parentGroupID,
                        r.name?.english ?? "", r.description?.english,
                        r.iconID, r.hasTypes == true ? 1 : 0,
                    ]
                )
            }
        }
        return "\(records.count) market groups"
    }

    private func importTypes() async throws -> String {
        guard let url = findFile("types.jsonl") else {
            return "⚠️  types.jsonl not found"
        }
        let records = try parseJSONL(url, as: SDEType.self)
        try await db.write { database in
            for r in records {
                guard let groupID = r.groupID else { continue }
                try database.execute(
                    sql: """
                        INSERT OR IGNORE INTO types (
                            id, group_id, market_group_id, name, description,
                            mass, volume, capacity, packaged_volume,
                            portion_size, base_price, published,
                            meta_group_id, variation_parent_id, faction_id, race_id
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        r.id, groupID, r.marketGroupID,
                        r.name?.english ?? "", r.description?.english,
                        r.mass, r.volume, r.capacity, r.packagedVolume,
                        r.portionSize, r.basePrice,
                        r.published == true ? 1 : 0,
                        r.metaGroupID, r.variationParentTypeID, r.factionID, r.raceID,
                    ]
                )
                try insertTraits(r.traits, forTypeId: r.id, into: database)
            }
        }
        return "\(records.count) types"
    }

    private func insertTraits(_ traits: SDETypeTraits?, forTypeId typeId: Int, into database: Database) throws {
        guard let traits else { return }
        var sort = 0

        for bonus in (traits.roleBonuses ?? []) + (traits.miscBonuses ?? []) {
            let text = bonus.displayText
            guard !text.isEmpty else { continue }
            let skillId: Int? = nil
            try database.execute(
                sql: "INSERT INTO type_traits (type_id, skill_id, bonus, unit_id, text, sort) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: [typeId, skillId, bonus.bonus, bonus.unitID, text, sort]
            )
            sort += 1
        }

        for key in (traits.types ?? [:]).keys.sorted(by: localizedNumericLessThan) {
            guard let skillId = Int(key), let bonuses = traits.types?[key] else { continue }
            for bonus in bonuses {
                let text = bonus.displayText
                guard !text.isEmpty else { continue }
                try database.execute(
                    sql: "INSERT INTO type_traits (type_id, skill_id, bonus, unit_id, text, sort) VALUES (?, ?, ?, ?, ?, ?)",
                    arguments: [typeId, skillId, bonus.bonus, bonus.unitID, text, sort]
                )
                sort += 1
            }
        }
    }

    private func localizedNumericLessThan(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    private func importTypeBonuses() async throws -> String {
        guard let url = findFile("typeBonus.yaml") else {
            return "⚠️  typeBonus.yaml not found"
        }

        let records = try parseTypeBonusYAML(url)
        try await db.write { database in
            try database.execute(sql: "DELETE FROM type_traits")
            for record in records {
                try database.execute(
                    sql: "INSERT INTO type_traits (type_id, skill_id, bonus, unit_id, text, sort) VALUES (?, ?, ?, ?, ?, ?)",
                    arguments: [record.typeId, record.skillId, record.bonus, record.unitId, record.text, record.sort]
                )
            }
        }
        return "\(records.count) type bonuses"
    }

    private func importDogmaAttributes() async throws -> String {
        guard let url = findFile("dogmaAttributes.jsonl") else {
            return "⚠️  dogmaAttributes.jsonl not found"
        }
        let records = try parseJSONL(url, as: SDEDogmaAttribute.self)
        try await db.write { database in
            for r in records {
                try database.execute(
                    sql: """
                        INSERT OR IGNORE INTO dogma_attributes
                        (id, name, display_name, unit_id, icon_id,
                         high_is_good, stackable, default_value, published)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        r.id, r.name ?? "",
                        r.displayName?.english,
                        r.unitID, r.iconID,
                        r.highIsGood == true ? 1 : 0,
                        r.stackable != false ? 1 : 0,
                        r.defaultValue,
                        r.published == true ? 1 : 0,
                    ]
                )
            }
        }
        return "\(records.count) dogma attributes"
    }

    private func importDogmaEffects() async throws -> String {
        guard let url = findFile("dogmaEffects.jsonl") else {
            return "⚠️  dogmaEffects.jsonl not found"
        }
        let records = try parseJSONL(url, as: SDEDogmaEffect.self)
        let modifierCount = try await db.write { database -> Int in
        var modifierCount = 0
            for r in records {
                try database.execute(
                    sql: """
                        INSERT OR IGNORE INTO dogma_effects (
                            id, name, effect_category,
                            is_offensive, is_assistance,
                            duration_attribute_id, discharge_attribute_id,
                            range_attribute_id, falloff_attribute_id,
                            tracking_speed_attribute_id,
                            fitting_usage_chance_attribute_id
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        r.id, r.name ?? "",
                        r.effectCategoryID ?? 0,
                        r.isOffensive.map { $0 ? 1 : 0 },
                        r.isAssistance.map { $0 ? 1 : 0 },
                        r.durationAttributeID, r.dischargeAttributeID,
                        r.rangeAttributeID, r.falloffAttributeID,
                        r.trackingSpeedAttributeID, r.fittingUsageChanceAttributeID,
                    ]
                )
                for mi in r.modifierInfo ?? [] {
                    guard let modAttr = mi.modifiedAttributeID,
                          let modifyAttr = mi.modifyingAttributeID,
                          let op = mi.operation else { continue }
                    try database.execute(
                        sql: """
                            INSERT INTO dogma_modifiers
                            (effect_id, domain, func, group_id, modified_attr_id, modifying_attr_id, operation, skill_type_id)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                        arguments: [
                            r.id,
                            mi.domain ?? "",
                            mi.func ?? "",
                            mi.groupID,
                            modAttr,
                            modifyAttr,
                            op,
                            mi.skillTypeID,
                        ]
                    )
                    modifierCount += 1
                }
            }
            return modifierCount
        }
        return "\(records.count) dogma effects, \(modifierCount) modifiers"
    }

    private func importTypeDogma() async throws -> (Int, Int) {
        guard let url = findFile("typeDogma.jsonl") else {
            print("  ⚠️  typeDogma.jsonl not found"); return (0, 0)
        }
        let records = try parseJSONL(url, as: SDETypeDogma.self)
        return try await db.write { database -> (Int, Int) in
            var attrCount = 0
            var effectCount = 0
            for r in records {
                for attr in r.dogmaAttributes ?? [] {
                    try database.execute(
                        sql: "INSERT OR IGNORE INTO type_attributes (type_id, attribute_id, value) VALUES (?, ?, ?)",
                        arguments: [r.id, attr.attributeID, attr.value]
                    )
                    attrCount += 1
                }
                for eff in r.dogmaEffects ?? [] {
                    try database.execute(
                        sql: "INSERT OR IGNORE INTO type_effects (type_id, effect_id, is_default) VALUES (?, ?, ?)",
                        arguments: [r.id, eff.effectID, eff.isDefault == true ? 1 : 0]
                    )
                    effectCount += 1
                }
            }
            return (attrCount, effectCount)
        }
    }

    private func deriveSkillRequirements() async throws -> Int {
        try await db.write { database in
            try database.execute(sql: """
                INSERT OR IGNORE INTO skill_requirements (type_id, skill_id, level)
                SELECT s.type_id, CAST(s.value AS INTEGER), CAST(l.value AS INTEGER)
                FROM type_attributes s
                JOIN type_attributes l
                  ON l.type_id = s.type_id
                 AND l.attribute_id = CASE s.attribute_id
                     WHEN 182  THEN 277
                     WHEN 183  THEN 278
                     WHEN 184  THEN 279
                     WHEN 1285 THEN 1286
                     WHEN 1289 THEN 1287
                     WHEN 1290 THEN 1288
                 END
                WHERE s.attribute_id IN (182, 183, 184, 1285, 1289, 1290)
                  AND CAST(s.value AS INTEGER) > 0
                """)
            return try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM skill_requirements") ?? 0
        }
    }

    private func buildFTS() async throws {
        try await db.write { database in
            try database.execute(sql: """
                INSERT INTO types_fts(rowid, name)
                SELECT id, name FROM types WHERE published = 1
                """)
        }
    }

    // MARK: - Helpers

    private func findFile(_ name: String) -> URL? {
        let candidates = [sdeRoot.appending(component: name),
                          sdeRoot.appending(component: "fsd").appending(component: name)]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func parseJSONL<T: Decodable>(_ url: URL, as type: T.Type) throws -> [T] {
        let decoder = JSONDecoder()
        let content = try String(contentsOf: url, encoding: .utf8)
        var results: [T] = []
        results.reserveCapacity(50_000)
        for (index, line) in content.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            guard !line.hasPrefix("#") else { continue }
            guard let data = line.data(using: .utf8) else { continue }
            do {
                results.append(try decoder.decode(T.self, from: data))
            } catch {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [],
                        debugDescription: "\(url.lastPathComponent):\(index + 1) failed to decode \(T.self): \(error)"
                    )
                )
            }
        }
        return results
    }

    private func parseTypeBonusYAML(_ url: URL) throws -> [SDETypeBonusRecord] {
        let content = try String(contentsOf: url, encoding: .utf8)
        var records: [SDETypeBonusRecord] = []
        records.reserveCapacity(3_000)

        var typeId: Int?
        var section: String?
        var skillId: Int?
        var sort = 0

        var hasEntry = false
        var entrySkillId: Int?
        var entryBonus: Double?
        var entryUnitId: Int?
        var entryTextParts: [String] = []
        var capturingEnglishText = false
        var englishTextIndent = 0

        func leadingSpaces(_ line: String) -> Int {
            line.prefix { $0 == " " }.count
        }

        func cleanYAMLText(_ value: String) -> String {
            var text = value.trimmingCharacters(in: .whitespaces)
            if ["|", ">", "|-", ">-"].contains(text) {
                return ""
            }
            if text.count >= 2,
               let first = text.first,
               let last = text.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                text.removeFirst()
                text.removeLast()
            }
            return text
        }

        func isLanguageLine(_ trimmedLine: String) -> Bool {
            guard let colonIndex = trimmedLine.firstIndex(of: ":") else { return false }
            let key = trimmedLine[..<colonIndex]
            return key.count == 2 && key.allSatisfy(\.isLetter)
        }

        func flushEntry() {
            guard hasEntry, let typeId else {
                hasEntry = false
                entryTextParts.removeAll(keepingCapacity: true)
                return
            }
            let text = entryTextParts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            if !text.isEmpty {
                records.append(SDETypeBonusRecord(
                    typeId: typeId,
                    skillId: entrySkillId,
                    bonus: entryBonus,
                    unitId: entryUnitId,
                    text: text,
                    sort: sort
                ))
                sort += 1
            }

            hasEntry = false
            entrySkillId = nil
            entryBonus = nil
            entryUnitId = nil
            entryTextParts.removeAll(keepingCapacity: true)
            capturingEnglishText = false
            englishTextIndent = 0
        }

        for line in content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if leadingSpaces(line) == 0, trimmed.hasSuffix(":") {
                let key = String(trimmed.dropLast())
                if let parsedTypeId = Int(key) {
                    flushEntry()
                    typeId = parsedTypeId
                    section = nil
                    skillId = nil
                    sort = 0
                    continue
                }
            }

            if leadingSpaces(line) == 2, ["roleBonuses:", "miscBonuses:", "types:"].contains(trimmed) {
                flushEntry()
                section = String(trimmed.dropLast())
                skillId = nil
                continue
            }

            if section == "types", leadingSpaces(line) == 4, trimmed.hasSuffix(":") {
                let key = String(trimmed.dropLast())
                if let parsedSkillId = Int(key) {
                    flushEntry()
                    skillId = parsedSkillId
                    continue
                }
            }

            if trimmed.hasPrefix("- bonus:") {
                flushEntry()
                let value = trimmed
                    .dropFirst("- bonus:".count)
                    .trimmingCharacters(in: .whitespaces)
                hasEntry = true
                entrySkillId = section == "types" ? skillId : nil
                entryBonus = Double(value)
                entryUnitId = nil
                entryTextParts.removeAll(keepingCapacity: true)
                continue
            }

            guard hasEntry else { continue }

            if trimmed.hasPrefix("unitID:") {
                let value = trimmed
                    .dropFirst("unitID:".count)
                    .trimmingCharacters(in: .whitespaces)
                entryUnitId = Int(value)
                capturingEnglishText = false
                continue
            }

            if trimmed.hasPrefix("en:") {
                capturingEnglishText = true
                englishTextIndent = leadingSpaces(line)
                let value = trimmed
                    .dropFirst("en:".count)
                    .trimmingCharacters(in: .whitespaces)
                let text = cleanYAMLText(value)
                if !text.isEmpty {
                    entryTextParts.append(text)
                }
                continue
            }

            if capturingEnglishText {
                let indent = leadingSpaces(line)
                if trimmed.isEmpty || indent <= englishTextIndent || isLanguageLine(trimmed) {
                    capturingEnglishText = false
                } else {
                    let text = cleanYAMLText(trimmed)
                    if !text.isEmpty {
                        entryTextParts.append(text)
                    }
                }
            }
        }

        flushEntry()
        return records
    }
}
