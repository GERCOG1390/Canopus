// Implants and boosters a fit can fly with (the desktop's implant browser): every published one on the
// market with its slot — implantness 1–10 (attribute 331) or boosterness 1–4 (attribute 1087).

import Foundation
import GRDB

public struct ImplantEntry: Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let slot: Int
    public let isBooster: Bool
}

extension SDERepository {
    public func implantCatalog() async throws -> [ImplantEntry] {
        try await dbReader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT t.id, t.name, a.attribute_id, a.value FROM types t
                JOIN groups g ON g.id = t.group_id
                JOIN type_attributes a ON a.type_id = t.id AND a.attribute_id IN (331, 1087)
                WHERE g.category_id = 20 AND t.published = 1 AND t.market_group_id IS NOT NULL
                ORDER BY a.value, t.name
                """).map { r in
                ImplantEntry(id: r["id"], name: r["name"], slot: Int((r["value"] as Double).rounded()), isBooster: (r["attribute_id"] as Int) == 1087)
            }
        }
    }
}
