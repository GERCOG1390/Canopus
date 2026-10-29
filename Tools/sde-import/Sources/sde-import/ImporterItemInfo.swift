// What the item info screen shows besides dogma (importer 3, the desktop's InfoBundle): unit names,
// attribute categories, meta groups, races, factions, blueprints, reprocessing, certificates and ship
// masteries, and Russian texts (l10n) next to the English ones.

import Foundation
import GRDB
@preconcurrency import Yams

extension SDEImporter {
    /// A Russian text, when the SDE has one that differs from nothing.
    static func russian(_ db: Database, _ kind: String, _ id: Int, _ field: String, _ value: String?) throws {
        guard let value, !value.isEmpty else { return }
        try db.execute(sql: "INSERT OR REPLACE INTO l10n (kind, id, field, lang, value) VALUES (?, ?, ?, 'ru', ?)",
                       arguments: [kind, id, field, value])
    }

    func importItemInfo() async throws -> String {
        var parts: [String] = []

        if let url = findFile("dogmaUnits.yaml") {
            // name is a plain string here; displayName is localised.
            let units = try parseYAMLNodeMap(url)
            try await db.write { db in
                for (id, u) in units {
                    let display = u["displayName"]?.mapping
                    try db.execute(sql: "INSERT OR REPLACE INTO dogma_units (id, name, display_name) VALUES (?, ?, ?)",
                                   arguments: [id, u["name"]?.string, display?["en"]?.string])
                    try Self.russian(db, "unit", id, "name", display?["ru"]?.string)
                }
            }
            parts.append("\(units.count) units")
        }

        if let url = findFile("dogmaAttributeCategories.yaml") {
            let cats = try parseYAMLMap(url, as: SDEAttributeCategory.self)
            try await db.write { db in
                for (id, c) in cats {
                    try db.execute(sql: "INSERT OR REPLACE INTO attribute_categories (id, name) VALUES (?, ?)", arguments: [id, c.name ?? ""])
                }
            }
            parts.append("\(cats.count) attribute categories")
        }

        for (file, table, kind) in [("metaGroups.yaml", "meta_groups", "meta_group"), ("races.yaml", "races", "race"), ("factions.yaml", "factions", "faction")] {
            guard let url = findFile(file) else { continue }
            let rows = try parseYAMLNodeMap(url)
            try await db.write { db in
                for (id, m) in rows {
                    let name = m["name"]?.mapping
                    try db.execute(sql: "INSERT OR REPLACE INTO \(table) (id, name) VALUES (?, ?)", arguments: [id, name?["en"]?.string ?? ""])
                    try Self.russian(db, kind, id, "name", name?["ru"]?.string)
                }
            }
            parts.append("\(rows.count) \(table)")
        }

        if let url = findFile("blueprints.yaml") {
            let rows = try parseYAMLNodeMap(url)
            try await db.write { db in
                for (id, m) in rows {
                    try db.execute(sql: "INSERT OR REPLACE INTO blueprints (id, max_runs) VALUES (?, ?)", arguments: [id, m["maxProductionLimit"]?.int])
                    guard let acts = m["activities"]?.mapping else { continue }
                    for (k, v) in acts {
                        guard let activity = k.string, let a = v.mapping else { continue }
                        try db.execute(sql: "INSERT OR REPLACE INTO blueprint_activities (blueprint_id, activity, time) VALUES (?, ?, ?)",
                                       arguments: [id, activity, a["time"]?.int ?? 0])
                        for x in a["materials"]?.sequence?.compactMap(\.mapping) ?? [] {
                            try db.execute(sql: "INSERT INTO blueprint_materials (blueprint_id, activity, type_id, quantity) VALUES (?, ?, ?, ?)",
                                           arguments: [id, activity, x["typeID"]?.int ?? 0, x["quantity"]?.int ?? 0])
                        }
                        for x in a["products"]?.sequence?.compactMap(\.mapping) ?? [] {
                            try db.execute(sql: "INSERT INTO blueprint_products (blueprint_id, activity, type_id, quantity, probability) VALUES (?, ?, ?, ?, ?)",
                                           arguments: [id, activity, x["typeID"]?.int ?? 0, x["quantity"]?.int ?? 0, x["probability"]?.float])
                        }
                        for x in a["skills"]?.sequence?.compactMap(\.mapping) ?? [] {
                            try db.execute(sql: "INSERT INTO blueprint_skills (blueprint_id, activity, skill_id, level) VALUES (?, ?, ?, ?)",
                                           arguments: [id, activity, x["typeID"]?.int ?? 0, x["level"]?.int ?? 0])
                        }
                    }
                }
            }
            parts.append("\(rows.count) blueprints")
        }

        if let url = findFile("typeMaterials.yaml") {
            let rows = try parseYAMLNodeMap(url)
            try await db.write { db in
                for (id, m) in rows {
                    for x in m["materials"]?.sequence?.compactMap(\.mapping) ?? [] {
                        try db.execute(sql: "INSERT INTO type_materials (type_id, material_id, quantity) VALUES (?, ?, ?)",
                                       arguments: [id, x["materialTypeID"]?.int ?? 0, x["quantity"]?.int ?? 0])
                    }
                }
            }
            parts.append("\(rows.count) reprocessable types")
        }

        if let url = findFile("certificates.yaml") {
            let rows = try parseYAMLNodeMap(url)
            try await db.write { db in
                for (id, m) in rows {
                    let name = m["name"]?.mapping
                    try db.execute(sql: "INSERT OR REPLACE INTO certificates (id, name) VALUES (?, ?)", arguments: [id, name?["en"]?.string ?? ""])
                    try Self.russian(db, "certificate", id, "name", name?["ru"]?.string)
                    for (k, v) in m["skillTypes"]?.mapping ?? [:] {
                        guard let skill = k.string.flatMap(Int.init), let lv = v.mapping else { continue }
                        let level = { (g: String) in lv[g]?.int ?? 0 }
                        try db.execute(sql: """
                            INSERT INTO certificate_skills (certificate_id, skill_id, basic, standard, improved, advanced, elite)
                            VALUES (?, ?, ?, ?, ?, ?, ?)
                            """, arguments: [id, skill, level("basic"), level("standard"), level("improved"), level("advanced"), level("elite")])
                    }
                }
            }
            parts.append("\(rows.count) certificates")
        }

        if let url = findFile("masteries.yaml") {
            let rows = try parseYAMLNodeMap(url)
            try await db.write { db in
                for (id, m) in rows {
                    for (k, v) in m {
                        guard let level = k.string.flatMap(Int.init) else { continue }
                        for cert in v.sequence?.compactMap(\.int) ?? [] {
                            try db.execute(sql: "INSERT INTO masteries (type_id, level, certificate_id) VALUES (?, ?, ?)", arguments: [id, level + 1, cert])
                        }
                    }
                }
            }
            parts.append("\(rows.count) ship masteries")
        }
        return parts.joined(separator: ", ")
    }
}
