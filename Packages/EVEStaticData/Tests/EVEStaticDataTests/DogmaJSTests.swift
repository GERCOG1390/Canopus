import Foundation
import GRDB
import Testing
@testable import EVEStaticData

/// The desktop engine through JavaScriptCore on the app's bundled SDE, against Pyfa's numbers for the same
/// fits (Tools/dogma-js/check_parity.py runs the full 264-case comparison).
@Suite("DogmaJS")
struct DogmaJSTests {
    private func engine() throws -> DogmaJS {
        let sde = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Canopus/Resources/sde.sqlite")
        var config = Configuration()
        config.readonly = true
        let queue = try DatabaseQueue(path: sde.path, configuration: config)
        return try DogmaJS(repository: SDERepository(dbReader: queue))
    }

    private func m(_ typeId: Int, _ slot: String, _ state: String, _ charge: Int? = nil) -> JSFitModule {
        JSFitModule(typeId: typeId, slot: slot, state: state, chargeTypeId: charge)
    }

    private var cerberus: JSFitSpec {
        let ham = 25715, scourge = 2679
        return JSFitSpec(shipTypeId: 11993, modules: [
            m(22291, "lo", "online"), m(22291, "lo", "online"), m(22291, "lo", "online"), m(2048, "lo", "online"),
            m(10858, "med", "active"), m(24443, "med", "online"), m(2281, "med", "active"), m(2299, "med", "active"),
            m(12058, "med", "active"), m(2032, "med", "online"),
            m(ham, "hi", "active", scourge), m(ham, "hi", "active", scourge), m(ham, "hi", "active", scourge),
            m(ham, "hi", "active", scourge), m(ham, "hi", "active", scourge), m(ham, "hi", "active", scourge),
            m(31372, "rig", "online"), m(31652, "rig", "online"),
        ])
    }

    /// Reference numbers from the same code fed the desktop's whole SDE (same CCP build).
    @Test func npcDamageMatchesDesktop() async throws {
        let r = try await engine().npcDamage(cerberus, skills: .all5, faction: .guristas)
        let byClass = Dictionary(uniqueKeysWithValues: r.classes.map { ($0.cls, $0) })
        #expect(byClass["frigate"]?.count == 35)
        #expect(byClass["battleship"]?.count == 23)
        #expect(abs((byClass["frigate"]?.ttkMedian ?? 0) - 5.043) < 0.001)
        #expect(abs((byClass["battleship"]?.ttkMedian ?? 0) - 37.073) < 0.001)
        #expect(abs((byClass["cruiser"]?.appliedDps ?? 0) - 634.979) < 0.001)
        #expect(abs((r.room.seconds ?? 0) - 223.457) < 0.001)
    }

    @Test func abyssPlanMatchesDesktop() async throws {
        let r = try await engine().abyssPlan(cerberus, skills: .all5, weather: .electrical, strength: 50)
        #expect(r.layer == "shield")
        #expect(abs(r.inWeather.ehp - 14358.5) < 0.1)
        #expect(abs(r.normal.ehp - 17228.4) < 0.1)
        let counts = Dictionary(uniqueKeysWithValues: r.factions.map { ($0.faction, $0.npcs.count) })
        #expect(counts == ["triglavian": 27, "drifter": 16, "sleeper": 9, "rogue_drone": 24, "sansha": 9, "angel": 10, "edencom": 13])
        #expect(abs((r.factions.first { $0.faction == "drifter" }?.worstTaken ?? 0) - 207.62) < 0.01)
    }

    @Test func optimizerMetricsAndVariants() async throws {
        let e = try engine()
        let metrics = try await e.metrics([cerberus], skills: .all5)
        #expect(abs(metrics[0].activeTank - 474.017) < 0.001)
        #expect(metrics[0].capLasts == 72)
        let variants = try await e.repo.fitVariants(shipTypeId: 11993, moduleTypeIds: [25715, 31372], droneTypeIds: [], levels: [:])
        let ham = variants.filter { $0.from == 25715 }
        #expect(ham.count >= 5)
        #expect(ham.filter { !$0.missingSkills }.isEmpty)
        let rigs = variants.filter { $0.from == 31372 }.map { $0.to }
        #expect(rigs == [31378])
    }

    @Test func hamCerberusMatchesPyfa() async throws {
        let ham = 25715, scourge = 2679
        let spec = JSFitSpec(shipTypeId: 11993, modules: [
            m(22291, "lo", "online"), m(22291, "lo", "online"), m(22291, "lo", "online"), m(2048, "lo", "online"),
            m(10858, "med", "active"), m(24443, "med", "online"), m(2281, "med", "active"), m(2299, "med", "active"),
            m(12058, "med", "active"), m(2032, "med", "online"),
            m(ham, "hi", "active", scourge), m(ham, "hi", "active", scourge), m(ham, "hi", "active", scourge),
            m(ham, "hi", "active", scourge), m(ham, "hi", "active", scourge), m(ham, "hi", "active", scourge),
            m(31372, "rig", "online"), m(31652, "rig", "online"),
        ])
        let s = try await engine().calculate(spec, skills: .all5)
        #expect(abs(s.offense.totalDps - 720.92) < 0.05)
        #expect(abs(s.defense.ehp - 17228.4) < 1)
        #expect(abs(s.navigation.maxVelocity - 667.83) < 0.05)
        #expect(abs(s.ship.cpu.used - 680.53) < 0.05)
    }

    @Test func bastionGolemMatchesPyfa() async throws {
        let cruise = 13927, mjolnir = 24533
        let spec = JSFitSpec(shipTypeId: 28710, modules: [
            m(13935, "lo", "online"), m(13935, "lo", "online"), m(13935, "lo", "online"), m(35771, "lo", "online"),
            m(41218, "med", "online"), m(41218, "med", "online"), m(32414, "med", "active"), m(4349, "med", "active"),
            m(4349, "med", "active"), m(19198, "med", "active"), m(35790, "med", "active", 35795),
            m(33400, "hi", "active"), m(cruise, "hi", "active", mjolnir), m(cruise, "hi", "active", mjolnir),
            m(cruise, "hi", "active", mjolnir), m(cruise, "hi", "active", mjolnir),
            m(25948, "rig", "online"), m(26374, "rig", "online"),
        ], implants: [20121, 20157, 20158, 20159, 20160, 20161])
        let s = try await engine().calculate(spec, skills: .all5)
        #expect(abs(s.offense.totalDps - 1649.89) < 0.05)
        #expect(abs(s.defense.ehp - 102238.7) < 1)
        #expect(s.navigation.maxVelocity == 0)
    }
}
