// The desktop's dogma engine (canopus-desktop src/main/dogma, bundled as Resources/canopus-dogma.js by
// Tools/dogma-js/build.mjs) running in JavaScriptCore: the same code and the same numbers as the desktop,
// checked against Pyfa (Tools/dogma-js/check_parity.py). Swift builds the engine's SDE data from the
// app's database (the shape of the desktop's SdeDb) and passes fits in as JSON.

import Foundation
import GRDB
import JavaScriptCore

// MARK: - Input (the desktop's FitSpec / SkillSource)

public struct JSFitModule: Codable, Sendable {
    public var typeId: Int
    /// "hi" | "med" | "lo" | "rig" | "sub"
    public var slot: String
    /// "offline" | "online" | "active" | "overload"
    public var state: String
    public var chargeTypeId: Int?

    public init(typeId: Int, slot: String, state: String, chargeTypeId: Int? = nil) {
        self.typeId = typeId
        self.slot = slot
        self.state = state
        self.chargeTypeId = chargeTypeId
    }
}

public struct JSFitDrone: Codable, Sendable {
    public var typeId: Int
    public var count: Int
    public var active: Int

    public init(typeId: Int, count: Int, active: Int) {
        self.typeId = typeId
        self.count = count
        self.active = active
    }
}

public struct JSFitSpec: Codable, Sendable {
    public var shipTypeId: Int
    public var name: String
    public var modules: [JSFitModule]
    public var drones: [JSFitDrone]
    public var implants: [Int]
    /// Tactical destroyer mode (type id); nil = Defense
    public var mode: Int?
    /// Abyssal weather celestial (type id); nil = normal space
    public var environment: Int?

    public init(shipTypeId: Int, name: String = "", modules: [JSFitModule], drones: [JSFitDrone] = [], implants: [Int] = [], mode: Int? = nil, environment: Int? = nil) {
        self.shipTypeId = shipTypeId
        self.name = name
        self.modules = modules
        self.drones = drones
        self.implants = implants
        self.mode = mode
        self.environment = environment
    }

    public var typeIds: Set<Int> {
        var ids: Set<Int> = [shipTypeId]
        for m in modules {
            ids.insert(m.typeId)
            if let c = m.chargeTypeId { ids.insert(c) }
        }
        drones.forEach { ids.insert($0.typeId) }
        implants.forEach { ids.insert($0) }
        if let mode { ids.insert(mode) }
        if let environment { ids.insert(environment) }
        return ids
    }
}

/// The skills to fit with: every skill at V, or the character's trained levels.
public enum JSSkills: Sendable {
    case all5
    case character([Int: Int])

    /// The engine's SkillSource as JSON (levels sorted, so equal skills give equal text).
    public var json: String {
        switch self {
        case .all5:
            return #"{"mode":"all5"}"#
        case .character(let levels):
            let pairs = levels.sorted { $0.key < $1.key }.map { "\"\($0.key)\":\($0.value)" }.joined(separator: ",")
            return #"{"mode":"char","levels":{"# + pairs + "}}"
        }
    }
}

// MARK: - Output (the desktop's FitStats, the parts the app shows)

public struct JSFitStats: Decodable, Sendable {
    public struct Use: Decodable, Sendable { public let used: Double; public let total: Double }
    public struct Layer: Decodable, Sendable {
        public let hp: Double
        /// em, thermal, kinetic, explosive as fractions 0…1
        public let resist: [Double]
        public let ehp: Double
    }
    public struct Ship: Decodable, Sendable {
        public let slots: [String: Double]
        public let turrets: Use
        public let launchers: Use
        public let cpu: Use
        public let power: Use
        public let calibration: Use
        public let droneBay: Use
        public let droneBandwidth: Use
        public let maxActiveDrones: Double
        public let cargo: Double
    }
    public struct Defense: Decodable, Sendable {
        public let shield: Layer
        public let armor: Layer
        public let hull: Layer
        public let ehp: Double
        public let hp: Double
        public let shieldRechargeSec: Double
        public let passiveShieldRegen: Double
        public let shieldBoost: Double
        public let armorRepair: Double
        public let hullRepair: Double
        public let activeTankEhp: Double
    }
    public struct Capacitor: Decodable, Sendable {
        public let capacity: Double
        public let rechargeSec: Double
        public let peakRecharge: Double
        public let usePerSecond: Double
        public let stable: Bool
        public let stableLevel: Double?
        public let lastsSec: Double?
    }
    public struct Weapon: Decodable, Sendable {
        public let moduleIndex: Int
        public let typeId: Int
        public let chargeTypeId: Int?
        public let kind: String
        public var count: Double
        public let volley: Double
        public var dps: Double
        public let dpsReload: Double
        /// EM, thermal, kinetic, explosive volley.
        public let damage: [Double]
        public let cycle: Double
        public let optimal: Double?
        public let falloff: Double?
        public let explosionRadius: Double?
    }
    public struct Offense: Decodable, Sendable {
        public let weapons: [Weapon]
        public let totalDps: Double
        public let totalDpsReload: Double
        public let totalVolley: Double
        public let turretDps: Double
        public let missileDps: Double
        public let droneDps: Double
    }
    public struct Navigation: Decodable, Sendable {
        public let maxVelocity: Double
        public let agility: Double
        public let mass: Double
        public let alignSec: Double
        public let warpSpeed: Double
        public let signatureRadius: Double
    }
    public struct Targeting: Decodable, Sendable {
        public let maxRange: Double
        public let scanResolution: Double
        public let maxTargets: Double
        public let sensorStrength: Double
        public let sensorType: String
        public let droneControlRange: Double?
    }
    public struct Module: Decodable, Sendable {
        public let index: Int
        public let cpu: Double
        public let power: Double
        public let capPerSecond: Double
        public let cycle: Double
        public let problems: [String]
    }

    public let ship: Ship
    public let defense: Defense
    public let capacitor: Capacitor
    public let offense: Offense
    public let navigation: Navigation
    public let targeting: Targeting
    public let modules: [Module]
    public let problems: [String]
}

// MARK: - Engine

public enum DogmaJSError: Error, LocalizedError {
    case bundleMissing
    case script(String)

    public var errorDescription: String? {
        switch self {
        case .bundleMissing: "canopus-dogma.js is missing from the app"
        case .script(let m): m
        }
    }
}

/// One JavaScriptCore context with the engine and the SDE data added so far (kept between fits).
public actor DogmaJS {
    private let context: JSContext
    let repo: SDERepository
    private var loadedTypes: Set<Int> = []
    private var baseLoaded = false

    public init(repository: SDERepository) throws {
        guard let url = Bundle.module.url(forResource: "canopus-dogma", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { throw DogmaJSError.bundleMissing }
        guard let ctx = JSContext() else { throw DogmaJSError.script("JavaScriptCore is unavailable") }
        ctx.evaluateScript(source)
        if let e = ctx.exception { throw DogmaJSError.script(e.toString()) }
        context = ctx
        repo = repository
    }

    /// The fit's stats from the desktop engine.
    public func calculate(_ spec: JSFitSpec, skills: JSSkills) async throws -> JSFitStats {
        try await prepare(spec.typeIds)
        let specJSON = String(decoding: try JSONEncoder().encode(spec), as: UTF8.self)
        let json = try invoke("calculate", [specJSON, skills.json])
        return try JSONDecoder().decode(JSFitStats.self, from: Data(json.utf8))
    }

    /// Adds the base data once and the given types' dogma the first time they are seen.
    func prepare(_ typeIds: Set<Int>) async throws {
        if !baseLoaded {
            try add(await repo.dogmaBaseData())
            baseLoaded = true
        }
        let missing = typeIds.subtracting(loadedTypes)
        if !missing.isEmpty {
            try add(await repo.dogmaTypeData(typeIds: missing))
            loadedTypes.formUnion(missing)
        }
    }

    /// Calls one of the bundle's CanopusDogma functions; JSON (or numbers) in, JSON out.
    func invoke(_ name: String, _ arguments: [Any]) throws -> String {
        let engine = context.objectForKeyedSubscript("CanopusDogma")
        let result = engine?.invokeMethod(name, withArguments: arguments)
        if let e = context.exception {
            context.exception = nil
            throw DogmaJSError.script(e.toString())
        }
        guard let json = result?.toString() else { throw DogmaJSError.script("no result") }
        return json
    }

    private func add(_ data: Data) throws {
        let engine = context.objectForKeyedSubscript("CanopusDogma")
        engine?.invokeMethod("addData", withArguments: [String(decoding: data, as: UTF8.self)])
        if let e = context.exception {
            context.exception = nil
            throw DogmaJSError.script(e.toString())
        }
    }
}

// MARK: - SDE data in the engine's shape (mirrors Tools/dogma-js/check_parity.py)

extension SDERepository {
    /// Groups, attributes, the character type and every skill, subsystem and tactical-destroyer mode with
    /// their dogma: what the engine reads for any fit (all-V skills, T3 subsystem slots, T3D modes).
    func dogmaBaseData() async throws -> Data {
        try await dbReader.read { db in
            let baseIds = try Int.fetchAll(db, sql: """
                SELECT t.id FROM types t JOIN groups g ON g.id = t.group_id
                WHERE g.category_id IN (16, 32) OR t.group_id = 1306 OR t.id = 1373
                """)
            var out = try Self.typeData(db, ids: Set(baseIds))
            var groups: [String: Any] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT id, category_id, name, published FROM groups") {
                let name: String = row["name"]
                groups[String(row["id"] as Int)] = ["n": [name, name], "c": row["category_id"] as Int, "pub": (row["published"] as Int) != 0]
            }
            var attributes: [String: Any] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT id, name, published, high_is_good, default_value, stackable FROM dogma_attributes") {
                attributes[String(row["id"] as Int)] = [
                    "name": row["name"] as String,
                    "pub": (row["published"] as Int) != 0,
                    "high": (row["high_is_good"] as Int) != 0,
                    "def": (row["default_value"] as Double?) ?? 0,
                    "stack": (row["stackable"] as Int) != 0,
                ]
            }
            out["groups"] = groups
            out["attributes"] = attributes
            return try JSONSerialization.data(withJSONObject: out)
        }
    }

    /// Types with their dogma attributes, effects and the effects' modifiers.
    func dogmaTypeData(typeIds: Set<Int>) async throws -> Data {
        try await dbReader.read { db in
            try JSONSerialization.data(withJSONObject: Self.typeData(db, ids: typeIds))
        }
    }

    private static func typeData(_ db: Database, ids: Set<Int>) throws -> [String: Any] {
        guard !ids.isEmpty else { return [:] }
        let list = ids.sorted().map(String.init).joined(separator: ",")
        var types: [String: Any] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT id, group_id, name, published, mass, volume, capacity FROM types WHERE id IN (\(list))") {
            let id: Int = row["id"]
            let name: String = row["name"]
            var t: [String: Any] = ["id": id, "n": [name, name], "g": row["group_id"] as Int, "pub": (row["published"] as Int) != 0]
            if let v: Double = row["mass"] { t["mass"] = v }
            if let v: Double = row["volume"] { t["vol"] = v }
            if let v: Double = row["capacity"] { t["cap"] = v }
            types[String(id)] = t
        }
        var attrs: [Int: [String: Double]] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT type_id, attribute_id, value FROM type_attributes WHERE type_id IN (\(list))") {
            attrs[row["type_id"] as Int, default: [:]][String(row["attribute_id"] as Int)] = row["value"] as Double
        }
        var effectsOf: [Int: [Int]] = [:]
        var defaultEffect: [Int: Int] = [:]
        var effectIds: Set<Int> = []
        for row in try Row.fetchAll(db, sql: "SELECT type_id, effect_id, is_default FROM type_effects WHERE type_id IN (\(list))") {
            let tid: Int = row["type_id"], eid: Int = row["effect_id"]
            effectsOf[tid, default: []].append(eid)
            if (row["is_default"] as Int) != 0 { defaultEffect[tid] = eid }
            effectIds.insert(eid)
        }
        var dogma: [String: Any] = [:]
        for id in ids where attrs[id] != nil || effectsOf[id] != nil {
            var d: [String: Any] = ["a": attrs[id] ?? [:], "e": effectsOf[id] ?? []]
            if let de = defaultEffect[id] { d["de"] = de }
            dogma[String(id)] = d
        }
        var effects: [String: [String: Any]] = [:]
        if !effectIds.isEmpty {
            let elist = effectIds.sorted().map(String.init).joined(separator: ",")
            for row in try Row.fetchAll(db, sql: "SELECT id, name, effect_category, duration_attribute_id, discharge_attribute_id, range_attribute_id, falloff_attribute_id FROM dogma_effects WHERE id IN (\(elist))") {
                var e: [String: Any] = ["name": row["name"] as String, "cat": row["effect_category"] as Int, "mods": [[String: Any]]()]
                for (key, col) in [("dur", "duration_attribute_id"), ("dis", "discharge_attribute_id"), ("range", "range_attribute_id"), ("falloff", "falloff_attribute_id")] {
                    if let v: Int = row[col], v != 0 { e[key] = v }
                }
                effects[String(row["id"] as Int)] = e
            }
            for row in try Row.fetchAll(db, sql: "SELECT effect_id, domain, func, group_id, modified_attr_id, modifying_attr_id, operation, skill_type_id FROM dogma_modifiers WHERE effect_id IN (\(elist)) ORDER BY id") {
                let key = String(row["effect_id"] as Int)
                var m: [String: Any] = [
                    "domain": row["domain"] as String,
                    "func": row["func"] as String,
                    "attr": row["modified_attr_id"] as Int,
                    "src": row["modifying_attr_id"] as Int,
                    "op": row["operation"] as Int,
                ]
                if let g: Int = row["group_id"] { m["group"] = g }
                if let s: Int = row["skill_type_id"] { m["skill"] = s }
                var mods = effects[key]?["mods"] as? [[String: Any]] ?? []
                mods.append(m)
                effects[key]?["mods"] = mods
            }
        }
        return ["types": types, "dogma": dogma, "effects": effects]
    }
}

// MARK: - The app's ShipStats from the desktop engine's result

extension ShipStats {
    /// The fitting screen's numbers from the desktop engine. `flags` are the fitted modules' inventory
    /// flags in the order they were passed in the spec (for per-module fitting costs).
    public init(js s: JSFitStats, flags: [(flag: String, typeId: Int)]) {
        let pct = { (r: Double) in r * 100 }
        let d = s.defense
        let reloadMissile = s.offense.weapons.filter { $0.kind == "missile" }.reduce(0) { $0 + $1.dpsReload }
        self.init(
            shieldHP: d.shield.hp, shieldEHP: d.shield.ehp,
            shieldRechargeMs: d.shieldRechargeSec * 1000, peakShieldRegen: d.passiveShieldRegen,
            activeShieldBoostPerSec: d.shieldBoost,
            shieldEMRes: pct(d.shield.resist[0]), shieldExpRes: pct(d.shield.resist[3]),
            shieldKinRes: pct(d.shield.resist[2]), shieldThermRes: pct(d.shield.resist[1]),
            armorHP: d.armor.hp, armorEHP: d.armor.ehp,
            armorEMRes: pct(d.armor.resist[0]), armorExpRes: pct(d.armor.resist[3]),
            armorKinRes: pct(d.armor.resist[2]), armorThermRes: pct(d.armor.resist[1]),
            hullHP: d.hull.hp,
            hullEMRes: pct(d.hull.resist[0]), hullExpRes: pct(d.hull.resist[3]),
            hullKinRes: pct(d.hull.resist[2]), hullThermRes: pct(d.hull.resist[1]),
            totalEHP: d.ehp,
            capCapacity: s.capacitor.capacity, capRechargeMs: s.capacitor.rechargeSec * 1000,
            capRegenPerSec: s.capacitor.peakRecharge, capDrainPerSec: s.capacitor.usePerSecond,
            maxVelocity: s.navigation.maxVelocity,
            signatureRadius: s.navigation.signatureRadius,
            agility: s.navigation.agility,
            mass: s.navigation.mass,
            alignTime: s.navigation.alignSec,
            warpSpeed: s.navigation.warpSpeed,
            maxTargetRange: s.targeting.maxRange,
            scanResolution: s.targeting.scanResolution,
            maxLockedTargets: s.targeting.maxTargets,
            sensorStrength: s.targeting.sensorStrength,
            droneCapacity: s.ship.droneBay.total,
            droneBandwidth: s.ship.droneBandwidth.total,
            droneControlRange: s.targeting.droneControlRange ?? 0,
            pgTotal: s.ship.power.total, pgUsed: s.ship.power.used,
            cpuTotal: s.ship.cpu.total, cpuUsed: s.ship.cpu.used,
            highSlots: s.ship.slots["hi"] ?? 0,
            mediumSlots: s.ship.slots["med"] ?? 0,
            lowSlots: s.ship.slots["lo"] ?? 0,
            rigSlots: s.ship.slots["rig"] ?? 0,
            turretDPS: s.offense.turretDps, missileDPS: s.offense.missileDps,
            missileReloadDPS: reloadMissile,
            moduleCosts: s.modules.compactMap { m in
                guard m.index < flags.count else { return nil }
                return FittedModuleCost(flag: flags[m.index].flag, typeId: flags[m.index].typeId, pg: m.power, cpu: m.cpu)
            }
        )
        droneDPS = s.offense.droneDps
    }
}
