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

    @Test func fitRelevantModifierShapesAreClassified() throws {
        let db = try DatabaseQueue(path: bundledSDEPath())
        let shapes = try db.read { db in
            try String.fetchAll(db, sql: """
                SELECT dm.domain || '|' || dm.func || '|' || dm.operation
                FROM dogma_modifiers dm
                JOIN dogma_effects de ON de.id = dm.effect_id
                JOIN type_effects te ON te.effect_id = de.id
                JOIN types t ON t.id = te.type_id
                JOIN groups g ON g.id = t.group_id
                WHERE t.published = 1
                  AND g.category_id IN (6, 7, 8, 16, 20)
                GROUP BY dm.domain, dm.func, dm.operation
                """)
        }

        let classified: Set<String> = [
            "charID|ItemModifier|-1",
            "charID|ItemModifier|0",
            "charID|ItemModifier|2",
            "charID|ItemModifier|3",
            "charID|ItemModifier|6",
            "charID|ItemModifier|7",
            "charID|LocationGroupModifier|0",
            "charID|LocationGroupModifier|6",
            "charID|LocationRequiredSkillModifier|0",
            "charID|OwnerRequiredSkillModifier|2",
            "charID|OwnerRequiredSkillModifier|4",
            "charID|OwnerRequiredSkillModifier|6",
            "itemID|ItemModifier|-1",
            "itemID|ItemModifier|0",
            "itemID|ItemModifier|2",
            "itemID|ItemModifier|4",
            "itemID|ItemModifier|6",
            "itemID|ItemModifier|7",
            "itemID|ItemModifier|9",
            "otherID|ItemModifier|-1",
            "otherID|ItemModifier|0",
            "otherID|ItemModifier|2",
            "otherID|ItemModifier|4",
            "otherID|ItemModifier|6",
            "otherID|ItemModifier|7",
            "shipID|ItemModifier|-1",
            "shipID|ItemModifier|0",
            "shipID|ItemModifier|2",
            "shipID|ItemModifier|3",
            "shipID|ItemModifier|4",
            "shipID|ItemModifier|6",
            "shipID|ItemModifier|7",
            "shipID|LocationGroupModifier|0",
            "shipID|LocationGroupModifier|2",
            "shipID|LocationGroupModifier|4",
            "shipID|LocationGroupModifier|6",
            "shipID|LocationGroupModifier|7",
            "shipID|LocationModifier|6",
            "shipID|LocationRequiredSkillModifier|0",
            "shipID|LocationRequiredSkillModifier|2",
            "shipID|LocationRequiredSkillModifier|3",
            "shipID|LocationRequiredSkillModifier|4",
            "shipID|LocationRequiredSkillModifier|6",
            "shipID|LocationRequiredSkillModifier|7",
            "structureID|LocationGroupModifier|6",
            "targetID|ItemModifier|2",
            "targetID|ItemModifier|7",
            "targetID|LocationRequiredSkillModifier|2",
        ]
        let unknown = Set(shapes).subtracting(classified)

        #expect(unknown.isEmpty, "Unclassified fit-relevant dogma modifier shapes: \(unknown.sorted())")
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
