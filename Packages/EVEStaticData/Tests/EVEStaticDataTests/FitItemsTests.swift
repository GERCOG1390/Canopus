import Foundation
import GRDB
import Testing
@testable import EVEStaticData

/// Item lists → fits (FitItems), the part between ESI and the engine that the engine's own tests don't
/// see. Each case is a real ship's contents that once came out wrong.
@Suite("FitItems")
struct FitItemsTests {
    private func repo() throws -> SDERepository {
        let sde = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Canopus/Resources/sde.sqlite")
        var config = Configuration()
        config.readonly = true
        return SDERepository(dbReader: try DatabaseQueue(path: sde.path, configuration: config))
    }

    @Test func onlyNumberedSlotsAreFitted() {
        #expect(FitItems.slot(forFlag: "HiSlot7") == .hi)
        #expect(FitItems.slot(forFlag: "MedSlot0") == .med)
        #expect(FitItems.slot(forFlag: "LoSlot2") == .lo)
        #expect(FitItems.slot(forFlag: "RigSlot1") == .rig)
        #expect(FitItems.slot(forFlag: "SubSystemSlot3") == .sub)
        // Holds, not fitted: a spare subsystem in the T3 subsystem bay once replaced the real one.
        #expect(FitItems.slot(forFlag: "SubSystemBay") == .cargo)
        #expect(FitItems.slot(forFlag: "Cargo") == .cargo)
        #expect(FitItems.slot(forFlag: "FleetHangar") == .cargo)
        #expect(FitItems.slot(forFlag: "SpecializedFuelBay") == .cargo)
        #expect(FitItems.slot(forFlag: "DroneBay") == .drone)
        #expect(FitItems.slot(forFlag: "FighterBay") == .drone)
    }

    /// A pilot's Tengu as ESI's assets list it (2026-11-03): fitted Amplification Node, a spare Covert
    /// Reconfiguration in the subsystem bay. The game shows 7 high, 7 mid, 3 low slots.
    private let tenguContents: [(String, Int, Int)] = [
        ("HiSlot0", 25715, 1), ("HiSlot1", 25715, 1), ("HiSlot2", 25715, 1), ("HiSlot3", 25715, 1),
        ("HiSlot4", 25715, 1), ("HiSlot5", 25715, 1), ("HiSlot6", 17938, 1),
        ("MedSlot0", 19189, 1), ("MedSlot1", 35790, 1), ("MedSlot1", 35795, 1), ("MedSlot2", 32414, 1),
        ("MedSlot3", 4349, 1), ("MedSlot4", 41218, 1), ("MedSlot5", 15766, 1), ("MedSlot6", 19303, 1),
        ("LoSlot0", 15681, 1), ("LoSlot1", 15681, 1), ("LoSlot2", 15681, 1),
        ("RigSlot0", 31652, 1), ("RigSlot1", 31824, 1), ("RigSlot2", 31724, 1),
        ("SubSystemSlot0", 45626, 1), ("SubSystemSlot1", 45591, 1), ("SubSystemSlot2", 45601, 1), ("SubSystemSlot3", 45615, 1),
        ("SubSystemBay", 45589, 1),
        ("Cargo", 2679, 2000), ("Cargo", 24488, 500), ("Cargo", 28668, 10),
    ]

    private func tenguAssets(shipItemId: Int) -> [FitAsset] {
        var id = 2_000_000
        var out = tenguContents.map { flag, type, qty in
            id += 1
            return FitAsset(itemId: id, typeId: type, locationId: shipItemId, locationType: "item", flag: flag, quantity: qty)
        }
        // Things elsewhere (a hangar, another ship) are not part of this ship.
        out.append(FitAsset(itemId: 3_000_001, typeId: 45589, locationId: 60_003_760, locationType: "station", flag: "Hangar", quantity: 1))
        out.append(FitAsset(itemId: 3_000_002, typeId: 15681, locationId: 999, locationType: "item", flag: "LoSlot3", quantity: 1))
        return out
    }

    @Test func liveShipTakesOnlyItsOwnContents() {
        let items = FitItems.liveShip(assets: tenguAssets(shipItemId: 1_000), shipItemId: 1_000)
        #expect(items.count == tenguContents.count)
        #expect(!items.contains { $0.flag == "LoSlot3" || $0.flag == "Hangar" })
    }

    @Test func liveTenguHasTheGameSlots() async throws {
        let repo = try repo()
        let items = FitItems.liveShip(assets: tenguAssets(shipItemId: 1_000), shipItemId: 1_000)
        let spec = try await repo.fitSpec(shipTypeId: 29984, name: "Drake", items: items)
        let subsystems = spec.modules.filter { $0.slot == "sub" }.map(\.typeId).sorted()
        #expect(subsystems == [45591, 45601, 45615, 45626])
        #expect(spec.modules.filter { $0.slot == "lo" }.count == 3)
        // The loaded script stays a charge, not a second module.
        #expect(spec.modules.filter { $0.slot == "med" }.count == 7)

        let stats = try await DogmaJS(repository: repo).calculate(spec, skills: .all5)
        #expect(stats.ship.slots["hi"] == 7)
        #expect(stats.ship.slots["med"] == 7)
        #expect(stats.ship.slots["lo"] == 3)
        #expect(stats.ship.slots["sub"] == 4)
    }
}
