import GRDB
import Foundation

struct IntegrityChecker {
    let db: DatabaseQueue

    struct Report {
        var passed: [String] = []
        var failed: [String] = []
        var isOK: Bool { failed.isEmpty }
    }

    func check() async throws -> Report {
        // Collect data outside the @Sendable read closure, then build the report.
        let rows: [(label: String, count: Int, minimum: Int)] = try await db.read { database in
            [
                ("Categories",      try count(database, "categories"),      1),
                ("Groups",          try count(database, "groups"),          10),
                ("Types",           try count(database, "types"),           100),
                ("Dogma attributes",try count(database, "dogma_attributes"),50),
                ("Type attributes", try count(database, "type_attributes"), 100),
                ("FTS index",       try count(database, "types_fts"),       1),
            ]
        }

        let fkResults: [(label: String, ok: Bool)] = try await db.read { database in
            try [
                ("groups.category_id FK", fkCheck(database, sql: """
                    SELECT COUNT(*) = 0 FROM groups g
                    LEFT JOIN categories c ON c.id = g.category_id WHERE c.id IS NULL
                    """)),
                ("types.group_id FK", fkCheck(database, sql: """
                    SELECT COUNT(*) = 0 FROM types t
                    LEFT JOIN groups g ON g.id = t.group_id WHERE g.id IS NULL
                    """)),
                ("type_attributes.attribute_id FK", fkCheck(database, sql: """
                    SELECT COUNT(*) = 0 FROM type_attributes ta
                    LEFT JOIN dogma_attributes da ON da.id = ta.attribute_id WHERE da.id IS NULL
                    """)),
            ]
        }

        var report = Report()
        for row in rows {
            if row.count >= row.minimum {
                report.passed.append("\(row.label) (\(row.count) rows)")
            } else {
                report.failed.append("\(row.label) — expected ≥\(row.minimum), got \(row.count)")
            }
        }
        for fk in fkResults {
            if fk.ok { report.passed.append(fk.label) } else { report.failed.append(fk.label) }
        }
        return report
    }

    private func count(_ db: Database, _ table: String) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
    }

    private func fkCheck(_ db: Database, sql: String) throws -> Bool {
        try Bool.fetchOne(db, sql: sql) ?? false
    }
}
