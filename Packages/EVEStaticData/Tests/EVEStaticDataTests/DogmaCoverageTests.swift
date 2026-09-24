import Foundation
import GRDB
import Testing
@testable import EVEStaticData

@Suite("Dogma coverage")
struct DogmaCoverageTests {

    @Test func fitRelevantNoModifierEffectsAreClassified() throws {
        let db = try DatabaseQueue(path: bundledSDEPath())
        let effectIds = try db.read { db in
            try Int.fetchAll(db, sql: """
                SELECT de.id
                FROM dogma_effects de
                JOIN type_effects te ON te.effect_id = de.id
                JOIN types t ON t.id = te.type_id
                JOIN groups g ON g.id = t.group_id
                WHERE t.published = 1
                  AND g.category_id IN (6, 7, 8, 16, 20)
                  AND NOT EXISTS (
                      SELECT 1
                      FROM dogma_modifiers dm
                      WHERE dm.effect_id = de.id
                  )
                GROUP BY de.id
                """)
        }

        let classified = DogmaEngine.handledBehaviorEffectIds
            .union(DogmaEngine.intentionallyIgnoredBehaviorEffectIds)
        let unknown = Set(effectIds).subtracting(classified)

        #expect(unknown.isEmpty, "Unclassified fit-relevant no-modifier dogma effects: \(unknown.sorted())")
    }

    private func bundledSDEPath() throws -> String {
        let fileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dbURL = repoRoot
            .appendingPathComponent("Canopus")
            .appendingPathComponent("Resources")
            .appendingPathComponent("sde.sqlite")

        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        return dbURL.path
    }
}
