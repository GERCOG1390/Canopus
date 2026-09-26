import GRDB
import Foundation

/// Named diff of one table between the previous release's database and the
/// one just built. `added`/`changed`/`removed` hold up to `maxNamedEntries`
/// names (sorted); the `*Count` fields hold the true totals so the client can
/// show "and N more" without us shipping a 40,000-line changelog.
struct SDEChangelogSection: Encodable {
    let added: [String]
    let addedCount: Int
    let changed: [String]
    let changedCount: Int
    let removed: [String]
    let removedCount: Int

    enum CodingKeys: String, CodingKey {
        case added, changed, removed
        case addedCount = "added_count"
        case changedCount = "changed_count"
        case removedCount = "removed_count"
    }

    static let empty = SDEChangelogSection(added: [], addedCount: 0, changed: [], changedCount: 0, removed: [], removedCount: 0)
}

struct SDEChangelog: Encodable {
    let types: SDEChangelogSection
    let categoriesChanged: Int
    let groupsChanged: Int
    let dogmaAttributesChanged: Int
    let dogmaEffectsChanged: Int

    enum CodingKeys: String, CodingKey {
        case types
        case categoriesChanged = "categories_changed"
        case groupsChanged = "groups_changed"
        case dogmaAttributesChanged = "dogma_attributes_changed"
        case dogmaEffectsChanged = "dogma_effects_changed"
    }

    static let empty = SDEChangelog(types: .empty, categoriesChanged: 0, groupsChanged: 0, dogmaAttributesChanged: 0, dogmaEffectsChanged: 0)
}

/// Diffs two Canopus SDE databases (same schema_version) to produce a
/// human-facing changelog. Ships/modules ("types") get a full named diff
/// since that's what players actually care about ("New ship: Vindicator II").
/// Categories/groups/dogma tables rarely change and aren't interesting by
/// name, so those just get a changed-row count.
struct ChangelogGenerator {
    static let maxNamedEntries = 40

    static func generate(oldDB: DatabaseQueue, newDB: DatabaseQueue) throws -> SDEChangelog {
        SDEChangelog(
            types: try diffTypes(oldDB: oldDB, newDB: newDB),
            categoriesChanged: try diffCount(oldDB: oldDB, newDB: newDB, table: "categories", columns: ["name", "published"]),
            groupsChanged: try diffCount(oldDB: oldDB, newDB: newDB, table: "groups", columns: ["category_id", "name", "published"]),
            dogmaAttributesChanged: try diffCount(
                oldDB: oldDB, newDB: newDB, table: "dogma_attributes",
                columns: ["name", "display_name", "unit_id", "high_is_good", "stackable", "default_value", "published"]
            ),
            dogmaEffectsChanged: try diffCount(
                oldDB: oldDB, newDB: newDB, table: "dogma_effects",
                columns: ["name", "effect_category", "is_offensive", "is_assistance"]
            )
        )
    }

    // MARK: - Private

    private struct RowSnapshot {
        let name: String
        let signature: String
    }

    private static func snapshot(_ db: DatabaseQueue, table: String, columns: [String]) throws -> [Int: RowSnapshot] {
        try db.read { conn in
            let selectCols = (["id", "name"] + columns).joined(separator: ", ")
            var result: [Int: RowSnapshot] = [:]
            for row in try Row.fetchAll(conn, sql: "SELECT \(selectCols) FROM \(table)") {
                let id: Int = row["id"]
                let name: String = row["name"]
                // name is part of the signature too — a pure rename must still count as "changed".
                let signature = (["name"] + columns).map { col -> String in
                    let value: DatabaseValue = row[col]
                    return String(describing: value)
                }.joined(separator: "|")
                result[id] = RowSnapshot(name: name, signature: signature)
            }
            return result
        }
    }

    private static func diffCount(oldDB: DatabaseQueue, newDB: DatabaseQueue, table: String, columns: [String]) throws -> Int {
        let old = try snapshot(oldDB, table: table, columns: columns)
        let new = try snapshot(newDB, table: table, columns: columns)
        return new.reduce(into: 0) { count, entry in
            let (id, newVal) = entry
            if let oldVal = old[id], oldVal.signature != newVal.signature {
                count += 1
            }
        }
    }

    private static func diffTypes(oldDB: DatabaseQueue, newDB: DatabaseQueue) throws -> SDEChangelogSection {
        let columns = ["group_id", "market_group_id", "published", "mass", "volume", "capacity",
                       "packaged_volume", "portion_size", "base_price", "meta_group_id",
                       "variation_parent_id", "faction_id", "race_id"]
        let old = try snapshot(oldDB, table: "types", columns: columns)
        let new = try snapshot(newDB, table: "types", columns: columns)

        var added: [String] = []
        var changed: [String] = []
        for (id, newVal) in new {
            if let oldVal = old[id] {
                if oldVal.signature != newVal.signature { changed.append(newVal.name) }
            } else {
                added.append(newVal.name)
            }
        }
        var removed: [String] = []
        for (id, oldVal) in old where new[id] == nil {
            removed.append(oldVal.name)
        }

        added.sort(); changed.sort(); removed.sort()
        return SDEChangelogSection(
            added: Array(added.prefix(maxNamedEntries)), addedCount: added.count,
            changed: Array(changed.prefix(maxNamedEntries)), changedCount: changed.count,
            removed: Array(removed.prefix(maxNamedEntries)), removedCount: removed.count
        )
    }
}
