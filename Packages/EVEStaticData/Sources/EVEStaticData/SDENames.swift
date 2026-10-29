// Names in the app's language. When the phone is in Russian, the repository loads the SDE's Russian
// names once (types, groups, categories, market groups) and every type / group / category it returns
// carries them, as the desktop shows names in its interface language. EFT export and names the game
// must read stay English (englishNames, type(named:)).

import Foundation
import Domain
import GRDB

enum SDENames {
    /// kind → id → Russian name; empty when the app shows English.
    nonisolated(unsafe) private(set) static var ru: [String: [Int: String]] = [:]
    /// Lower-cased Russian type name → id, for names typed or pasted in Russian.
    nonisolated(unsafe) private(set) static var ruTypeIds: [String: Int] = [:]

    static var appIsRussian: Bool { Locale.current.language.languageCode?.identifier == "ru" }

    static func name(_ kind: String, _ id: Int, _ fallback: String) -> String { ru[kind]?[id] ?? fallback }

    static func load(_ db: Database) throws {
        guard appIsRussian, try db.tableExists("l10n") else { ru = [:]; ruTypeIds = [:]; return }
        var out: [String: [Int: String]] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT kind, id, value FROM l10n
            WHERE lang = 'ru' AND field = 'name' AND kind IN ('type', 'group', 'category', 'market_group')
            """) {
            out[row["kind"] as String, default: [:]][row["id"]] = row["value"]
        }
        ru = out
        ruTypeIds = Dictionary((out["type"] ?? [:]).map { ($0.value.lowercased(), $0.key) }, uniquingKeysWith: { a, _ in a })
    }
}

extension SDERepository {
    /// English names, for EFT and anything the game reads back.
    public func englishNames(ids: Set<Int>) async throws -> [Int: String] {
        guard !ids.isEmpty else { return [:] }
        return try await dbReader.read { db in
            var out: [Int: String] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT id, name FROM types WHERE id IN (\(ids.map(String.init).joined(separator: ",")))") {
                out[r["id"]] = r["name"]
            }
            return out
        }
    }

    /// A type by its exact name in English or in the app's language (EFT, pasted lists).
    public func type(named name: String) async throws -> ItemType? {
        let key = name.trimmingCharacters(in: .whitespaces)
        let ruId = SDENames.ruTypeIds[key.lowercased()]
        return try await dbReader.read { db in
            let record = try TypeRecord.fetchOne(db, sql: "SELECT * FROM types WHERE lower(name) = lower(?) ORDER BY published DESC LIMIT 1", arguments: [key])
                ?? ruId.flatMap { try TypeRecord.fetchOne(db, key: $0) }
            return record?.toDomain()
        }
    }
}
