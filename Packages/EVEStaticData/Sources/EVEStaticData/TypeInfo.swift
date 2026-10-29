// Everything the item info screen shows about one type (the desktop's sde info() → InfoBundle): names and
// description in the app's language, attributes by category with units, what the item changes (its dogma
// modifiers in words, the desktop's describeModifiers), ship bonuses, the skill requirement tree, the skill
// itself, masteries, variations, blueprints, reprocessing.

import Foundation
import GRDB

public struct TypeInfoBundle: Sendable {
    public struct Attribute: Sendable, Identifiable {
        public let id: Int
        public let name: String
        public let tooltip: String?
        public let category: String
        public let value: Double
        public let unit: Int?
        public let unitName: String?
        public let iconId: Int?
    }

    public enum ModifierState: String, Sendable, CaseIterable { case passive, online, active, overload }
    public enum ModifierTarget: Sendable { case me, ship, char, other, location, group, skill, selfSkill }

    public struct Modifier: Sendable {
        public let state: ModifierState
        public let target: ModifierTarget
        public let group: Int?
        public let skill: Int?
        public let attr: Int
        public let attrName: String
        public let attrIconId: Int?
        public let unit: Int?
        public let unitName: String?
        public let op: Int
        public let value: Double
        public var perLevel = false
        public var note: String?
    }

    public struct Bonus: Sendable {
        public let value: Double?
        public let unit: Int?
        public let text: String
    }

    public struct Traits: Sendable {
        public var bySkill: [(skill: Int, bonuses: [Bonus])] = []
        public var role: [Bonus] = []
    }

    public struct Requirement: Sendable, Identifiable {
        public var id: Int { skill }
        public let skill: Int
        public let level: Int
        public let rank: Double
        public let primary: Int
        public let secondary: Int
        public let children: [Requirement]
    }

    public struct Activity: Sendable {
        public let name: String
        public let time: Int
        public let materials: [(type: Int, qty: Int)]
        public let products: [(type: Int, qty: Int, probability: Double?)]
        public let skills: [(skill: Int, level: Int)]
    }

    public struct Certificate: Sendable, Identifiable {
        public let id: Int
        public let name: String
        public let skills: [(skill: Int, level: Int)]
    }

    public struct Ref: Sendable {
        public let name: String
        public let categoryId: Int
        public let metaGroupId: Int?
    }

    public let typeId: Int
    public let name: String
    /// The English name when the app shows another language.
    public let englishName: String?
    public let groupId: Int
    public let groupName: String
    public let categoryId: Int
    public let categoryName: String
    public let marketPath: [String]
    public let marketGroupId: Int?
    public let metaGroup: String?
    public let metaLevel: Int?
    public let race: String?
    public let faction: String?
    public let published: Bool
    public let description: String?
    public let volume: Double?
    public let packagedVolume: Double?
    public let mass: Double?
    public let capacity: Double?
    public let portionSize: Int?
    public let basePrice: Double?
    public let attributes: [Attribute]
    public let modifiers: [Modifier]
    /// A skill whose levels scale ship hull bonuses (e.g. Gallente Cruiser).
    public let boostsHullBonuses: Bool
    public let traits: Traits?
    public let requirements: [Requirement]
    public let skill: (rank: Double, primary: Int, secondary: Int)?
    public let requiredFor: [(level: Int, types: [Int])]
    public let variations: [Int]
    public let producedBy: (blueprint: Int, activity: Activity, maxRuns: Int?)?
    public let blueprint: (maxRuns: Int?, activities: [Activity])?
    public let usedIn: [(blueprint: Int, product: Int, qty: Int, activity: String)]
    public let reprocess: [(type: Int, qty: Int)]
    public let masteries: [(level: Int, certificates: [Certificate])]
    public let refs: [Int: Ref]
    public let groupNames: [Int: String]
    public let attributeNames: [Int: String]
}

extension SDERepository {
    /// The attribute pairs (skill, level) that name a type's required skills.
    static let requiredSkillAttrs: [(Int, Int)] = [(182, 277), (183, 278), (184, 279), (1285, 1286), (1289, 1287), (1290, 1288)]

    public func typeInfo(id typeId: Int, russian: Bool) async throws -> TypeInfoBundle {
        try await dbReader.read { db in try Self.buildInfo(db, typeId: typeId, ru: russian) }
    }

    // swiftlint:disable:next function_body_length
    private static func buildInfo(_ db: Database, typeId: Int, ru: Bool) throws -> TypeInfoBundle {
        guard let t = try Row.fetchOne(db, sql: "SELECT * FROM types WHERE id = ?", arguments: [typeId]) else {
            throw DatabaseError(message: "type \(typeId) not found")
        }
        func l10n(_ kind: String, _ id: Int?, _ field: String = "name") throws -> String? {
            guard ru, let id else { return nil }
            return try String.fetchOne(db, sql: "SELECT value FROM l10n WHERE kind = ? AND id = ? AND field = ? AND lang = 'ru'", arguments: [kind, id, field])
        }
        func attrsOf(_ id: Int) throws -> [Int: Double] {
            var out: [Int: Double] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT attribute_id, value FROM type_attributes WHERE type_id = ?", arguments: [id]) {
                out[r["attribute_id"]] = r["value"]
            }
            return out
        }
        var refIds = Set<Int>()
        var groupIds = Set<Int>()
        var attrNameIds = Set<Int>()

        let englishName: String = t["name"]
        let name = try l10n("type", typeId) ?? englishName
        let groupId: Int = t["group_id"]
        let group = try Row.fetchOne(db, sql: "SELECT name, category_id FROM groups WHERE id = ?", arguments: [groupId])
        let categoryId: Int = group?["category_id"] ?? 0
        let categoryName = try l10n("category", categoryId) ?? String.fetchOne(db, sql: "SELECT name FROM categories WHERE id = ?", arguments: [categoryId]) ?? ""
        let groupName = try l10n("group", groupId) ?? (group?["name"] as String?) ?? ""

        var marketPath: [String] = []
        var mg: Int? = t["market_group_id"]
        var guardCount = 0
        while let g = mg, guardCount < 10, let row = try Row.fetchOne(db, sql: "SELECT parent_id, name FROM market_groups WHERE id = ?", arguments: [g]) {
            marketPath.insert(try l10n("market_group", g) ?? row["name"], at: 0)
            mg = row["parent_id"]
            guardCount += 1
        }

        let dogma = try attrsOf(typeId)
        let effectIds = try Int.fetchAll(db, sql: "SELECT effect_id FROM type_effects WHERE type_id = ?", arguments: [typeId])

        // Attributes: published, named, not the required-skill ones, not zero.
        let reqAttrIds = Set(requiredSkillAttrs.flatMap { [$0.0, $0.1] })
        var attrMeta: [Int: Row] = [:]
        for r in try Row.fetchAll(db, sql: """
            SELECT a.id, a.name, a.display_name, a.unit_id, a.icon_id, a.published, a.category_id, a.tooltip, a.default_value,
                   c.name AS category, u.display_name AS unit_name
            FROM dogma_attributes a LEFT JOIN attribute_categories c ON c.id = a.category_id LEFT JOIN dogma_units u ON u.id = a.unit_id
            """) { attrMeta[r["id"]] = r }
        func attrName(_ id: Int) throws -> String {
            try l10n("attribute", id) ?? (attrMeta[id]?["display_name"] as String?).flatMap { $0.isEmpty ? nil : $0 } ?? (attrMeta[id]?["name"] as String?) ?? String(id)
        }
        func unitName(_ unit: Int?) throws -> String? {
            guard let unit else { return nil }
            return try l10n("unit", unit) ?? attrMeta.values.first { ($0["unit_id"] as Int?) == unit }?["unit_name"]
        }
        var attributes: [TypeInfoBundle.Attribute] = []
        for (aid, value) in dogma {
            guard let m = attrMeta[aid], (m["published"] as Int) != 0, !reqAttrIds.contains(aid), value != 0 else { continue }
            let display = (m["display_name"] as String?) ?? ""
            guard !display.isEmpty else { continue }
            let unit: Int? = m["unit_id"]
            attributes.append(.init(id: aid, name: try attrName(aid), tooltip: try l10n("attribute", aid, "tooltip") ?? m["tooltip"],
                                    category: (m["category"] as String?) ?? "Other", value: value, unit: unit,
                                    unitName: try unitName(unit), iconId: m["icon_id"]))
            if unit == 116 { refIds.insert(Int(value)) }
            if unit == 115 { groupIds.insert(Int(value)) }
            if unit == 119 { attrNameIds.insert(Int(value)) }
        }
        attributes.sort { $0.id < $1.id }

        // Traits (ship bonuses), in the app's language.
        var traits: TypeInfoBundle.Traits?
        let traitRows = try Row.fetchAll(db, sql: "SELECT skill_id, bonus, unit_id, text FROM \(ru ? "type_traits_ru" : "type_traits") WHERE type_id = ? ORDER BY sort", arguments: [typeId])
        if !traitRows.isEmpty {
            var tr = TypeInfoBundle.Traits()
            for r in traitRows {
                let b = TypeInfoBundle.Bonus(value: r["bonus"], unit: r["unit_id"], text: r["text"])
                if let skill = r["skill_id"] as Int? {
                    if let i = tr.bySkill.firstIndex(where: { $0.skill == skill }) { tr.bySkill[i].bonuses.append(b) } else { tr.bySkill.append((skill, [b])); refIds.insert(skill) }
                } else {
                    tr.role.append(b)
                }
            }
            traits = tr
        }

        // Requirement tree.
        func tree(_ id: Int, depth: Int) throws -> [TypeInfoBundle.Requirement] {
            guard depth <= 12 else { return [] }
            let a = depth == 0 ? dogma : try attrsOf(id)
            var out: [TypeInfoBundle.Requirement] = []
            for (sa, la) in requiredSkillAttrs {
                guard let skillD = a[sa], skillD > 0 else { continue }
                let skill = Int(skillD)
                let s = try attrsOf(skill)
                out.append(.init(skill: skill, level: Int(a[la] ?? 1), rank: s[275] ?? 1, primary: Int(s[180] ?? 0), secondary: Int(s[181] ?? 0),
                                 children: try tree(skill, depth: depth + 1)))
                refIds.insert(skill)
            }
            return out
        }
        let requirements = try tree(typeId, depth: 0)

        var skill: (rank: Double, primary: Int, secondary: Int)?
        var requiredFor: [(level: Int, types: [Int])] = []
        if categoryId == 16 {
            skill = (dogma[275] ?? 1, Int(dogma[180] ?? 0), Int(dogma[181] ?? 0))
            let rows = try Row.fetchAll(db, sql: """
                SELECT r.type_id, r.level FROM skill_requirements r JOIN types t ON t.id = r.type_id
                WHERE r.skill_id = ? AND t.published = 1
                """, arguments: [typeId])
            requiredFor = (1...5).map { lvl in (lvl, rows.filter { ($0["level"] as Int) == lvl }.map { $0["type_id"] as Int }) }.filter { !$0.types.isEmpty }
            requiredFor.forEach { refIds.formUnion($0.types) }
        }

        // Variations: the variation family, by meta level then meta group.
        let parent: Int = t["variation_parent_id"] ?? typeId
        var variations = try Int.fetchAll(db, sql: """
            SELECT t.id FROM types t LEFT JOIN type_attributes ml ON ml.type_id = t.id AND ml.attribute_id = 633
            WHERE (t.id = ? OR t.variation_parent_id = ?) AND t.published = 1
            ORDER BY coalesce(ml.value, 0), coalesce(t.meta_group_id, 0)
            """, arguments: [parent, parent])
        if variations.count <= 1 { variations = [] } else { refIds.formUnion(variations) }

        // Blueprints.
        func activities(_ bp: Int, only: String? = nil) throws -> [TypeInfoBundle.Activity] {
            try Row.fetchAll(db, sql: "SELECT activity, time FROM blueprint_activities WHERE blueprint_id = ?" + (only == nil ? "" : " AND activity = ?"),
                             arguments: only == nil ? [bp] : [bp, only!]).map { r in
                let act: String = r["activity"]
                let mats = try Row.fetchAll(db, sql: "SELECT type_id, quantity FROM blueprint_materials WHERE blueprint_id = ? AND activity = ?", arguments: [bp, act]).map { ($0["type_id"] as Int, $0["quantity"] as Int) }
                let prods = try Row.fetchAll(db, sql: "SELECT type_id, quantity, probability FROM blueprint_products WHERE blueprint_id = ? AND activity = ?", arguments: [bp, act]).map { ($0["type_id"] as Int, $0["quantity"] as Int, $0["probability"] as Double?) }
                let skills = try Row.fetchAll(db, sql: "SELECT skill_id, level FROM blueprint_skills WHERE blueprint_id = ? AND activity = ?", arguments: [bp, act]).map { ($0["skill_id"] as Int, $0["level"] as Int) }
                mats.forEach { refIds.insert($0.0) }
                prods.forEach { refIds.insert($0.0) }
                skills.forEach { refIds.insert($0.0) }
                return .init(name: act, time: r["time"], materials: mats.map { (type: $0.0, qty: $0.1) },
                             products: prods.map { (type: $0.0, qty: $0.1, probability: $0.2) }, skills: skills.map { (skill: $0.0, level: $0.1) })
            }
        }
        var producedBy: (blueprint: Int, activity: TypeInfoBundle.Activity, maxRuns: Int?)?
        if let p = try Row.fetchOne(db, sql: """
            SELECT p.blueprint_id, p.activity FROM blueprint_products p JOIN types t ON t.id = p.blueprint_id
            WHERE p.type_id = ? AND p.activity IN ('manufacturing', 'reaction') ORDER BY t.published DESC LIMIT 1
            """, arguments: [typeId]), let act = try activities(p["blueprint_id"], only: p["activity"]).first {
            let bp: Int = p["blueprint_id"]
            producedBy = (bp, act, try Int.fetchOne(db, sql: "SELECT max_runs FROM blueprints WHERE id = ?", arguments: [bp]))
            refIds.insert(bp)
        }
        var blueprint: (maxRuns: Int?, activities: [TypeInfoBundle.Activity])?
        if let max = try Row.fetchOne(db, sql: "SELECT max_runs FROM blueprints WHERE id = ?", arguments: [typeId]) {
            let order = ["manufacturing", "reaction", "invention", "copying", "research_material", "research_time"]
            blueprint = (max["max_runs"], try activities(typeId).sorted { (order.firstIndex(of: $0.name) ?? 9) < (order.firstIndex(of: $1.name) ?? 9) })
        }
        let usedIn = try Row.fetchAll(db, sql: """
            SELECT m.blueprint_id, m.quantity, m.activity, p.type_id AS product FROM blueprint_materials m
            JOIN blueprint_products p ON p.blueprint_id = m.blueprint_id AND p.activity = m.activity
            JOIN types t ON t.id = p.type_id
            WHERE m.type_id = ? AND t.published = 1 LIMIT 300
            """, arguments: [typeId]).map { (blueprint: $0["blueprint_id"] as Int, product: $0["product"] as Int, qty: $0["quantity"] as Int, activity: $0["activity"] as String) }
        usedIn.forEach { refIds.insert($0.product) }

        let reprocess = try Row.fetchAll(db, sql: "SELECT material_id, quantity FROM type_materials WHERE type_id = ?", arguments: [typeId]).map { (type: $0["material_id"] as Int, qty: $0["quantity"] as Int) }
        reprocess.forEach { refIds.insert($0.type) }

        // Masteries: level → certificates → skills at that grade.
        let grades = ["basic", "standard", "improved", "advanced", "elite"]
        var masteries: [(level: Int, certificates: [TypeInfoBundle.Certificate])] = []
        for level in 1...5 {
            let certs = try Int.fetchAll(db, sql: "SELECT certificate_id FROM masteries WHERE type_id = ? AND level = ?", arguments: [typeId, level])
            guard !certs.isEmpty else { continue }
            let list = try certs.map { cid -> TypeInfoBundle.Certificate in
                let n = try l10n("certificate", cid) ?? String.fetchOne(db, sql: "SELECT name FROM certificates WHERE id = ?", arguments: [cid]) ?? ""
                let skills = try Row.fetchAll(db, sql: "SELECT skill_id, \(grades[level - 1]) AS lvl FROM certificate_skills WHERE certificate_id = ?", arguments: [cid])
                    .map { (skill: $0["skill_id"] as Int, level: $0["lvl"] as Int) }.filter { $0.level > 0 }
                skills.forEach { refIds.insert($0.skill) }
                return .init(id: cid, name: n, skills: skills)
            }
            masteries.append((level, list))
        }

        // What the item changes.
        let described = try describeModifiers(db, typeId: typeId, dogma: dogma, effectIds: effectIds, attrName: attrName, attrMeta: attrMeta, unitName: unitName)
        for m in described.list {
            if let s = m.skill { refIds.insert(s) }
            if let g = m.group { groupIds.insert(g) }
        }

        // Description: Russian (compressed) when the app shows Russian.
        var description: String? = t["description"]
        if ru, let z = try Data.fetchOne(db, sql: "SELECT z FROM type_descriptions_ru WHERE type_id = ?", arguments: [typeId]),
           let d = try? (z as NSData).decompressed(using: .zlib) {
            description = String(decoding: d as Data, as: UTF8.self)
        }
        let linkRe = try NSRegularExpression(pattern: #"showinfo:(\d+)"#)
        for text in [description ?? ""] + (traits.map { $0.role.map(\.text) + $0.bySkill.flatMap { $0.bonuses.map(\.text) } } ?? []) {
            for m in linkRe.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let r = Range(m.range(at: 1), in: text), let id = Int(text[r]) { refIds.insert(id) }
            }
        }

        // Names of everything referenced.
        var refs: [Int: TypeInfoBundle.Ref] = [:]
        if !refIds.isEmpty {
            for r in try Row.fetchAll(db, sql: """
                SELECT t.id, t.name, t.meta_group_id, g.category_id FROM types t JOIN groups g ON g.id = t.group_id
                WHERE t.id IN (\(refIds.map(String.init).joined(separator: ",")))
                """) {
                let id: Int = r["id"]
                refs[id] = .init(name: try l10n("type", id) ?? r["name"], categoryId: r["category_id"], metaGroupId: r["meta_group_id"])
            }
        }
        var groupNames: [Int: String] = [:]
        for g in groupIds {
            groupNames[g] = try l10n("group", g) ?? String.fetchOne(db, sql: "SELECT name FROM groups WHERE id = ?", arguments: [g])
        }
        var attributeNames: [Int: String] = [:]
        for a in attrNameIds { attributeNames[a] = try attrName(a) }

        let metaGroupId: Int? = t["meta_group_id"], raceId: Int? = t["race_id"], factionId: Int? = t["faction_id"]
        return TypeInfoBundle(
            typeId: typeId, name: name, englishName: name != englishName ? englishName : nil,
            groupId: groupId, groupName: groupName, categoryId: categoryId, categoryName: categoryName,
            marketPath: marketPath, marketGroupId: t["market_group_id"],
            metaGroup: try metaGroupId.flatMap { try l10n("meta_group", $0) ?? String.fetchOne(db, sql: "SELECT name FROM meta_groups WHERE id = ?", arguments: [$0]) },
            metaLevel: dogma[633].map { Int($0) },
            race: try raceId.flatMap { try l10n("race", $0) ?? String.fetchOne(db, sql: "SELECT name FROM races WHERE id = ?", arguments: [$0]) },
            faction: try factionId.flatMap { try l10n("faction", $0) ?? String.fetchOne(db, sql: "SELECT name FROM factions WHERE id = ?", arguments: [$0]) },
            published: (t["published"] as Int) != 0,
            description: description,
            volume: t["volume"], packagedVolume: t["packaged_volume"], mass: t["mass"], capacity: t["capacity"],
            portionSize: t["portion_size"], basePrice: t["base_price"],
            attributes: attributes, modifiers: described.list, boostsHullBonuses: described.boostsHull,
            traits: traits, requirements: requirements, skill: skill, requiredFor: requiredFor,
            variations: variations, producedBy: producedBy, blueprint: blueprint, usedIn: usedIn,
            reprocess: reprocess, masteries: masteries, refs: refs, groupNames: groupNames, attributeNames: attributeNames)
    }

    // MARK: - What the item changes (the desktop's describeModifiers)

    private static let effectState: [Int: TypeInfoBundle.ModifierState] = [0: .passive, 4: .online, 1: .active, 5: .overload]
    private static let itemTarget: [String: TypeInfoBundle.ModifierTarget] = ["itemID": .me, "shipID": .ship, "charID": .char, "otherID": .other]
    /// Client-coded skill effects (no modifiers in the SDE): the same set the dogma engine implements.
    private static let selfSkillEffects: [String: (attr: Int, src: Int)] = [
        "missileEMDmgBonus": (114, 292), "missileExplosiveDmgBonus": (116, 292), "missileThermalDmgBonus": (118, 292),
        "missileKineticDmgBonus2": (117, 292), "selfRof": (51, 293), "droneDmgBonus": (64, 292),
    ]

    private static func describeModifiers(
        _ db: Database, typeId: Int, dogma: [Int: Double], effectIds: [Int],
        attrName: (Int) throws -> String, attrMeta: [Int: Row], unitName: (Int?) throws -> String?
    ) throws -> (list: [TypeInfoBundle.Modifier], boostsHull: Bool) {
        guard !effectIds.isEmpty else { return ([], false) }
        let list = effectIds.map(String.init).joined(separator: ",")
        let effects = try Row.fetchAll(db, sql: "SELECT id, name, effect_category FROM dogma_effects WHERE id IN (\(list))")
        var mods: [Int: [Row]] = [:]
        for r in try Row.fetchAll(db, sql: "SELECT * FROM dogma_modifiers WHERE effect_id IN (\(list)) ORDER BY id") {
            mods[r["effect_id"], default: []].append(r)
        }
        let skillLevel = 280
        // Attributes the item multiplies by its own skill level are "per level" bonuses.
        var perLevel = Set<Int>()
        for e in effects {
            for m in mods[e["id"] as Int] ?? [] where (m["domain"] as String) == "itemID" && (m["modifying_attr_id"] as Int) == skillLevel && (m["operation"] as Int) == 0 {
                perLevel.insert(m["modified_attr_id"])
            }
        }
        let valueOf = { (attr: Int) -> Double in dogma[attr] ?? (attrMeta[attr]?["default_value"] as Double?) ?? 0 }
        func modifier(_ state: TypeInfoBundle.ModifierState, _ target: TypeInfoBundle.ModifierTarget, attr: Int, op: Int, value: Double,
                      group: Int? = nil, skill: Int? = nil, perLevel: Bool = false, note: String? = nil) throws -> TypeInfoBundle.Modifier {
            let unit: Int? = attrMeta[attr]?["unit_id"]
            var m = TypeInfoBundle.Modifier(state: state, target: target, group: group, skill: skill, attr: attr, attrName: try attrName(attr),
                                            attrIconId: attrMeta[attr]?["icon_id"], unit: unit, unitName: try unitName(unit), op: op, value: value)
            m.perLevel = perLevel
            m.note = note
            return m
        }
        var out: [TypeInfoBundle.Modifier] = []
        var boostsHull = false
        for e in effects {
            let name: String = e["name"]
            guard name != "skillEffect", let state = effectState[e["effect_category"] as Int] else { continue }
            if name == "moduleBonusMicrowarpdrive" || name == "moduleBonusAfterburner" {
                out.append(try modifier(state, .ship, attr: 37, op: 6, value: valueOf(20), note: "the actual gain depends on the ship's mass"))
                out.append(try modifier(state, .ship, attr: 4, op: 2, value: valueOf(796)))
                if name == "moduleBonusMicrowarpdrive" { out.append(try modifier(state, .ship, attr: 552, op: 6, value: valueOf(554))) }
                continue
            }
            if let s = selfSkillEffects[name] {
                out.append(try modifier(state, .selfSkill, attr: s.attr, op: 6, value: valueOf(s.src), perLevel: true))
                continue
            }
            for m in mods[e["id"] as Int] ?? [] {
                let domain: String = m["domain"], fn: String = m["func"]
                let src: Int = m["modifying_attr_id"], attr: Int = m["modified_attr_id"], op: Int = m["operation"]
                if src == skillLevel {
                    if domain == "shipID" { boostsHull = true }
                    continue
                }
                guard ["itemID", "shipID", "charID", "otherID"].contains(domain) else { continue }
                let target: TypeInfoBundle.ModifierTarget?
                switch fn {
                case "ItemModifier": target = itemTarget[domain]
                case "LocationGroupModifier": target = .group
                case "LocationRequiredSkillModifier", "OwnerRequiredSkillModifier": target = .skill
                case "LocationModifier": target = .location
                default: target = nil
                }
                guard let target else { continue }
                // Skills modifying their own bonus attribute are bookkeeping, not an effect on anything.
                if target == .me && perLevel.contains(attr) { continue }
                let value = valueOf(src)
                if value == 0 && op != 7 && op != -1 { continue }
                let skillId: Int? = m["skill_type_id"]
                let srcName = (attrMeta[src]?["name"] as String?) ?? ""
                out.append(try modifier(state, target, attr: attr, op: op, value: value, group: m["group_id"],
                                        skill: skillId == -1 ? typeId : skillId,
                                        perLevel: perLevel.contains(src) || srcName.hasPrefix("shipBonus") || srcName.hasPrefix("eliteBonus")))
            }
        }
        var seen = Set<String>()
        return (out.filter { m in seen.insert("\(m.state)|\(m.target)|\(m.group ?? 0)|\(m.skill ?? 0)|\(m.attr)|\(m.op)|\(m.value)").inserted }, boostsHull)
    }
}
