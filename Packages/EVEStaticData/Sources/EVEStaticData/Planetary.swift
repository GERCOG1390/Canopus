// Planetary industry data (the desktop's sde piSchematics / systemPlanets, importer 6): every schematic
// with its inputs and output, each PI type's tier (from the customs base value), and the planets of each
// system. Which planet types hold which raw resource is not in the SDE: it is the game's fixed table
// (EVE University, "Planets"), kept here as the desktop does.

import Foundation
import GRDB

public struct PlanetSchematic: Sendable, Hashable, Identifiable {
    public let id: Int
    /// Seconds per cycle
    public let cycleTime: Int
    public let inputs: [PIAmount]
    public let output: PIAmount
}

public struct PIAmount: Sendable, Hashable {
    public let typeId: Int
    public let quantity: Int
}

public enum PlanetTypes {
    /// Planet type id → (Russian, English) name.
    public static let names: [Int: (ru: String, en: String)] = [
        2016: ("Бесплодная", "Barren"),
        13: ("Газовая", "Gas"),
        12: ("Ледяная", "Ice"),
        2015: ("Лавовая", "Lava"),
        2014: ("Океаническая", "Oceanic"),
        2063: ("Плазменная", "Plasma"),
        2017: ("Грозовая", "Storm"),
        11: ("Умеренная", "Temperate"),
    ]

    /// Raw resource (P0) → planet types it can be extracted on.
    public static let p0Planets: [Int: [Int]] = [
        2268: [2016, 13, 12, 2014, 2017, 11], // Aqueous Liquids
        2305: [11], // Autotrophs
        2267: [2016, 13, 2015, 2063, 2017], // Base Metals
        2288: [2016, 2014, 11], // Carbon Compounds
        2287: [2014, 11], // Complex Organisms
        2307: [2015], // Felsic Magma
        2272: [12, 2015, 2063], // Heavy Metals
        2309: [13, 2017], // Ionic Solutions
        2073: [2016, 12, 2014, 11], // Microorganisms
        2310: [13, 12, 2017], // Noble Gas
        2270: [2016, 2063], // Noble Metals
        2306: [2015, 2063], // Non-CS Crystals
        2286: [12, 2014], // Planktic Colonies
        2311: [13], // Reactive Gas
        2308: [2015, 2063, 2017], // Suspended Plasma
    ]

    /// ESI's colony `planet_type` ("temperate", "lava"…) → planet type id.
    public static let byESIName: [String: Int] = [
        "barren": 2016, "gas": 13, "ice": 12, "lava": 2015, "oceanic": 2014, "plasma": 2063, "storm": 2017, "temperate": 11,
    ]

    /// Customs taxable value per unit (attribute 1641) → tier.
    public static let tierByBase: [Double: Int] = [5: 0, 400: 1, 7200: 2, 60000: 3, 1_200_000: 4]
}

extension SDERepository {
    /// Every PI schematic by id; empty with a database from before importer 6.
    public func planetSchematics() async throws -> [Int: PlanetSchematic] {
        try await dbReader.read { db in
            guard try db.tableExists("planet_schematics") else { return [:] }
            var parts: [Int: (inputs: [PIAmount], output: PIAmount?)] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT schematic_id, type_id, quantity, is_input FROM planet_schematic_types") {
                let a = PIAmount(typeId: r["type_id"], quantity: r["quantity"])
                if (r["is_input"] as Int) == 1 { parts[r["schematic_id"], default: ([], nil)].inputs.append(a) } else { parts[r["schematic_id"], default: ([], nil)].output = a }
            }
            var out: [Int: PlanetSchematic] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT id, cycle_time FROM planet_schematics") {
                let id: Int = r["id"]
                guard let p = parts[id], let output = p.output else { continue }
                out[id] = PlanetSchematic(id: id, cycleTime: r["cycle_time"], inputs: p.inputs.sorted { $0.typeId < $1.typeId }, output: output)
            }
            return out
        }
    }

    /// PI types' tier (P0–P4) from their customs base value.
    public func piTiers(typeIds: Set<Int>) async throws -> [Int: Int] {
        guard !typeIds.isEmpty else { return [:] }
        return try await dbReader.read { db in
            var out: [Int: Int] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT type_id, value FROM type_attributes WHERE attribute_id = 1641 AND type_id IN (\(typeIds.map(String.init).joined(separator: ",")))") {
                if let t = PlanetTypes.tierByBase[r["value"]] { out[r["type_id"]] = t }
            }
            return out
        }
    }

    /// Customs taxable value per unit of PI types (attribute 1641).
    public func piBaseValues(typeIds: Set<Int>) async throws -> [Int: Double] {
        guard !typeIds.isEmpty else { return [:] }
        return try await dbReader.read { db in
            var out: [Int: Double] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT type_id, value FROM type_attributes WHERE attribute_id = 1641 AND type_id IN (\(typeIds.map(String.init).joined(separator: ",")))") {
                out[r["type_id"]] = r["value"]
            }
            return out
        }
    }

    /// Planet type → how many, per system.
    public func systemPlanets(ids: Set<Int>) async throws -> [Int: [Int: Int]] {
        guard !ids.isEmpty else { return [:] }
        return try await dbReader.read { db in
            guard try db.tableExists("system_planets") else { return [:] }
            var out: [Int: [Int: Int]] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT system_id, type_id, count FROM system_planets WHERE system_id IN (\(ids.map(String.init).joined(separator: ",")))") {
                out[r["system_id"], default: [:]][r["type_id"]] = r["count"]
            }
            return out
        }
    }
}
