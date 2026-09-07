import Foundation

// MARK: - Module State

public enum ModuleState: String, CaseIterable, Sendable {
    case offline  = "OFFLINE"
    case online   = "ONLINE"
    case active   = "ACTIVE"
    case overload = "OVERLOAD"

    public var isOnline: Bool { self != .offline }
    public var isActive: Bool { self == .active || self == .overload }
}

// MARK: - Type Profile

/// Attributes, effect IDs, group and skill requirements for one SDE type.
public struct TypeProfile: Sendable {
    public let attrs: [Int: Double]
    public let effectIds: Set<Int>
    /// group_id from the types table — used for LocationGroupModifier matching.
    public let groupId: Int
    /// Skill type IDs required to use this module — used for LocationRequiredSkillModifier.
    public let requiredSkillIds: Set<Int>

    public static let empty = TypeProfile(attrs: [:], effectIds: [])

    public init(attrs: [Int: Double], effectIds: Set<Int>, groupId: Int = 0, requiredSkillIds: Set<Int> = []) {
        self.attrs = attrs
        self.effectIds = effectIds
        self.groupId = groupId
        self.requiredSkillIds = requiredSkillIds
    }
}

// MARK: - Modifier Row

/// One row from the dogma_modifiers table — describes how an effect transforms attributes.
public struct ModifierRow: Sendable {
    /// "shipID" | "charID" | "itemID"
    public let domain: String
    /// "ItemModifier" | "LocationGroupModifier" | "LocationRequiredSkillModifier" | "OwnerRequiredSkillModifier"
    public let function_: String
    /// Target group ID for LocationGroupModifier
    public let groupId: Int?
    public let modifiedAttrId: Int
    public let modifyingAttrId: Int
    /// -1=PreAssignment 0=PreMul 2=ModAdd 3=ModSub 4=PostMul 5=PostDiv 6=PostPercent 7=PostAssignment
    public let operation: Int
    /// Skill type ID required/scaling for LocationRequiredSkillModifier / OwnerRequiredSkillModifier
    public let skillTypeId: Int?
    /// effect_category from dogma_effects: 0/4=online, 1=active, 5=overload
    public let effectCategory: Int

    public init(domain: String, function_: String, groupId: Int?, modifiedAttrId: Int,
                modifyingAttrId: Int, operation: Int, skillTypeId: Int?, effectCategory: Int = 4) {
        self.domain = domain
        self.function_ = function_
        self.groupId = groupId
        self.modifiedAttrId = modifiedAttrId
        self.modifyingAttrId = modifyingAttrId
        self.operation = operation
        self.skillTypeId = skillTypeId
        self.effectCategory = effectCategory
    }
}

// MARK: - Module Input

public struct FittedModuleInput: Sendable {
    public let flag: String
    public let typeId: Int
    public let state: ModuleState
    public let chargeTypeId: Int?
    /// Attribute map of the loaded charge (missile / ammo), if any.
    public let chargeAttrs: [Int: Double]?
    /// Full profile of the loaded charge, including effect IDs for self modifiers.
    public let chargeProfile: TypeProfile?
    /// Required skill IDs of the loaded charge — used for legacy missile skill damage bonuses.
    public let chargeRequiredSkillIds: Set<Int>
    /// Launcher magazine capacity and charge volume in m³, used for sustained DPS with reload.
    public let moduleCapacity: Double
    public let chargeVolume: Double

    public init(flag: String, typeId: Int, state: ModuleState,
                chargeTypeId: Int? = nil,
                chargeAttrs: [Int: Double]? = nil,
                chargeProfile: TypeProfile? = nil,
                chargeRequiredSkillIds: Set<Int> = [],
                moduleCapacity: Double = 0,
                chargeVolume: Double = 0) {
        self.flag = flag
        self.typeId = typeId
        self.state = state
        self.chargeTypeId = chargeTypeId
        self.chargeAttrs = chargeAttrs
        self.chargeProfile = chargeProfile
        self.chargeRequiredSkillIds = chargeRequiredSkillIds
        self.moduleCapacity = moduleCapacity
        self.chargeVolume = chargeVolume
    }
}

public struct FittedModuleCost: Sendable, Identifiable {
    public var id: String { flag }
    public let flag: String
    public let typeId: Int
    public let pg: Double
    public let cpu: Double

    public init(flag: String, typeId: Int, pg: Double, cpu: Double) {
        self.flag = flag
        self.typeId = typeId
        self.pg = pg
        self.cpu = cpu
    }
}

// MARK: - Ship Stats

public struct ShipStats: Sendable {
    // Shield
    public let shieldHP: Double
    public let shieldEHP: Double
    public let shieldRechargeMs: Double
    public let peakShieldRegen: Double
    public let shieldEMRes: Double
    public let shieldExpRes: Double
    public let shieldKinRes: Double
    public let shieldThermRes: Double

    // Armor
    public let armorHP: Double
    public let armorEHP: Double
    public let armorEMRes: Double
    public let armorExpRes: Double
    public let armorKinRes: Double
    public let armorThermRes: Double

    // Hull + totals
    public let hullHP: Double
    public let hullEMRes: Double
    public let hullExpRes: Double
    public let hullKinRes: Double
    public let hullThermRes: Double
    public let totalEHP: Double

    // Capacitor
    public let capCapacity: Double
    public let capRechargeMs: Double
    public let capRegenPerSec: Double
    public let capDrainPerSec: Double

    // Mobility
    public let maxVelocity: Double
    public let signatureRadius: Double

    // Targeting
    public let maxTargetRange: Double
    public let scanResolution: Double
    public let maxLockedTargets: Double
    public let sensorStrength: Double

    // Drones
    public let droneCapacity: Double
    public let droneBandwidth: Double
    public let droneControlRange: Double

    // Resources
    public let pgTotal: Double
    public let pgUsed: Double
    public let cpuTotal: Double
    public let cpuUsed: Double

    // Offense
    public let turretDPS: Double
    public let missileDPS: Double
    public let missileReloadDPS: Double

    // Per-module fitting costs after skills, hull, subsystem, script and charge modifiers.
    public let moduleCosts: [FittedModuleCost]
}

// MARK: - Dogma Engine

public struct DogmaEngine: Sendable {

    // Attribute IDs verified against the bundled SDE dogma_attributes table
    private enum A {
        static let capNeed          = 6
        static let hullHP           = 9
        static let pgOutput         = 11
        static let powerLoad        = 30
        static let cargoCapacity    = 38
        static let maxVelocity      = 37
        static let maxRange         = 54
        static let maxTargetRange   = 76
        static let cpuOutput        = 48
        static let cpu              = 50
        static let turretRoFMs      = 51
        static let chargeRate       = 56
        static let capRechargeMs    = 55
        static let dmgMultiplier    = 64
        static let agility          = 70
        static let duration         = 73
        static let emDmg            = 114
        static let expDmg           = 116
        static let kinDmg           = 117
        static let thermDmg         = 118
        static let maxLockedTargets = 192
        static let scanRadar        = 208
        static let scanLadar        = 209
        static let scanMagnetometric = 210
        static let scanGravimetric  = 211
        static let shieldHP         = 263
        static let armorHP          = 265
        static let droneCapacity    = 283
        static let armorEMRes       = 267
        static let armorExpRes      = 268
        static let armorKinRes      = 269
        static let armorThermRes    = 270
        static let shieldEMRes      = 271
        static let shieldExpRes     = 272
        static let shieldKinRes     = 273
        static let shieldThermRes   = 274
        static let skillLevel       = 280
        static let shieldRechargeMs = 479
        static let capCapacity      = 482
        static let signatureRadius  = 552
        static let warpSpeedMultiplier = 600
        static let scanResolution   = 564
        static let drawback         = 1138
        static let rigDrawbackBonus = 1139
        static let reloadTimeMs     = 1795
        static let scanGeneric      = 1169
        static let droneBandwidth   = 1271
        static let cpuNeedBonus     = 310
        static let droneControlDistance = 458
        static let missileDmgMul    = 212  // missileDamageMultiplier on charges — modified by BCS
        static let hullEMRes        = 974
        static let hullExpRes       = 975
        static let hullKinRes       = 976
        static let hullThermRes     = 977
        static let legacyHullKinRes = 109
        static let legacyHullThermRes = 110
        static let legacyHullExpRes = 111
        static let legacyHullEMRes  = 113
    }

    private static let chargeDamageAttrIds: Set<Int> = [A.emDmg, A.expDmg, A.kinDmg, A.thermDmg]

    // Attributes with stackable=0 from SDE — stacking penalty applies when multiple modules modify them.
    private static let stackPenaltyAttrs: Set<Int> = [
        A.shieldEMRes, A.shieldExpRes, A.shieldKinRes, A.shieldThermRes,
        A.armorEMRes,  A.armorExpRes,  A.armorKinRes,  A.armorThermRes,
        A.hullEMRes,   A.hullExpRes,   A.hullKinRes,   A.hullThermRes,
        A.legacyHullEMRes, A.legacyHullExpRes, A.legacyHullKinRes, A.legacyHullThermRes,
        A.maxVelocity, A.turretRoFMs,  A.dmgMultiplier, A.signatureRadius,
        A.missileDmgMul,
    ]

    // Legacy missile damage effects — no modifierInfo in SDE.
    // Skills with these effects apply attr292 as +% to ALL charge damage attrs
    // for charges requiring the skill itself.
    private static let legacyMissileDmgEffects: Set<Int> = [660, 661, 662, 668]
    // Legacy RoF effect — no modifierInfo. Skills with this effect apply attr293
    // as +% to RoF of modules requiring the skill.
    private static let legacyRoFEffect = 1851
    private static let damageControlEffect = 2302
    // Legacy CPU effect — Weapon Upgrades stores the per-level percentage in
    // attr310, while effect 672 only exposes an itemID cpu/skillLevel modifier.
    private static let legacyCpuNeedSkillEffects: Set<Int> = [672]

    private static let rigDrawbackSkillByGroup: [Int: Int] = [
        773: 26253, // Armor Rigging
        774: 26261, // Shield Rigging
        775: 26258, // Energy Weapon Rigging
        776: 26259, // Hybrid Weapon Rigging
        777: 26257, // Projectile Weapon Rigging
        778: 26255, // Drones Rigging
        779: 26260, // Launcher Rigging
        782: 26254, // Astronautics Rigging
        786: 26256, // Electronic Superiority Rigging
    ]

    private static let rigShipDrawbackEffectTargets: [Int: (attrId: Int, sign: Double)] = [
        2712: (A.armorHP, -1),              // drawbackArmorHP
        2713: (A.cpuOutput, -1),            // drawbackCPUOutput
        2716: (A.signatureRadius, 1),       // drawbackSigRad
        2717: (A.agility, 1),               // drawbackAgility
        2718: (A.shieldHP, -1),             // drawbackShieldCapacity
        3528: (A.capRechargeMs, 1),         // drawbackCapacitorRecharge
        5868: (A.cargoCapacity, -1),        // drawbackCargoCapacity
        5951: (A.warpSpeedMultiplier, -1),  // drawbackWarpSpeed
    ]

    private static let rigModuleDrawbackEffectTargets: [Int: (attrId: Int, groupIds: Set<Int>)] = [
        2706: (A.powerLoad, [53]), // drawbackPowerNeedLasers
        2707: (A.powerLoad, [74]), // drawbackPowerNeedHybrids
        2708: (A.powerLoad, [55]), // drawbackPowerNeedProjectiles
        2714: (A.cpu, [
            56,   // Missile Launcher
            506,  // Missile Launcher Cruise
            507,  // Missile Launcher Rocket
            508,  // Missile Launcher Torpedo
            509,  // Missile Launcher Light
            510,  // Missile Launcher Heavy
            511,  // Missile Launcher Rapid Light
            512,  // Missile Launcher Defender
            524,  // Missile Launcher XL Torpedo
            771,  // Missile Launcher Heavy Assault
            862,  // Missile Launcher Bomb
            1245, // Missile Launcher Rapid Heavy
            1673, // Missile Launcher Rapid Torpedo
            1674, // Missile Launcher XL Cruise
        ]), // drawbackCPUNeedLaunchers
        5267: (A.powerLoad, [
            62,   // Armor Repair Unit
            1199, // Ancillary Armor Repairer
        ]), // drawbackRepairSystemsPGNeed
        5268: (A.powerLoad, [
            62,   // Capital Armor Repairers are in Armor Repair Unit
            1199, // Ancillary Armor Repairer
        ]), // drawbackCapRepPGNeed
    ]

    public static func isActiveModule(_ attrs: [Int: Double]) -> Bool {
        if (attrs[A.duration] ?? 0) > 0 {
            return true
        }

        let usesCharge = [604, 605, 606, 609].contains { (attrs[$0] ?? 0) > 0 }
        let hasWeaponCycle = (attrs[A.turretRoFMs] ?? 0) > 0 && ((attrs[A.chargeRate] ?? 0) > 0 || usesCharge)
        let hasDirectDamage = chargeDamageAttrIds.contains { (attrs[$0] ?? 0) > 0 }
        return hasWeaponCycle || hasDirectDamage
    }

    private static func stackPenalty(_ i: Int) -> Double {
        let order = Double(i)
        return exp(-pow(order / 2.67, 2))
    }

    private static func stackedProduct(_ muls: [Double]) -> Double {
        let sorted = muls.sorted { abs($0 - 1.0) > abs($1 - 1.0) }
        return sorted.enumerated().reduce(1.0) { acc, pair in
            acc * (1.0 + (pair.element - 1.0) * stackPenalty(pair.offset))
        }
    }

    private static func multiplier(value: Double, operation: Int) -> Double? {
        guard value != 0 else { return nil }
        switch operation {
        case 0, 4: return value
        case 5:    return 1.0 / value
        case 6:    return 1.0 + value / 100.0
        default:   return nil
        }
    }

    private static func applyModifiers(
        sourceAttrs: [Int: Double],
        targetAttrs: [Int: Double],
        effectIds: Set<Int>,
        domain: String,
        state: ModuleState,
        effectModifiers: [Int: [ModifierRow]]
    ) -> [Int: Double] {
        var result = targetAttrs
        var pendingAdd: [Int: Double] = [:]
        var pendingMulStack: [Int: [Double]] = [:]
        var pendingMulDirect: [Int: [Double]] = [:]
        var pendingPreAssign: [Int: Double] = [:]
        var pendingPostAssign: [Int: Double] = [:]

        for effectId in effectIds {
            for m in effectModifiers[effectId] ?? [] {
                guard m.domain == domain,
                      m.function_ == "ItemModifier",
                      effectFires(category: m.effectCategory, state: state) else { continue }
                let val = sourceAttrs[m.modifyingAttrId] ?? 0
                guard val != 0 else { continue }
                let stacks = stackPenaltyAttrs.contains(m.modifiedAttrId)
                switch m.operation {
                case -1:
                    pendingPreAssign[m.modifiedAttrId] = val
                case 2:
                    pendingAdd[m.modifiedAttrId, default: 0] += val
                case 3:
                    pendingAdd[m.modifiedAttrId, default: 0] -= val
                case 0, 4, 5, 6:
                    guard let factor = multiplier(value: val, operation: m.operation) else { continue }
                    if stacks { pendingMulStack[m.modifiedAttrId, default: []].append(factor) }
                    else      { pendingMulDirect[m.modifiedAttrId, default: []].append(factor) }
                case 7:
                    pendingPostAssign[m.modifiedAttrId] = val
                default:
                    break
                }
            }
        }

        for (id, value) in pendingPreAssign { result[id] = value }
        for (id, sum) in pendingAdd { result[id, default: 0] += sum }
        for (id, muls) in pendingMulStack { result[id, default: 1] *= stackedProduct(muls) }
        for (id, muls) in pendingMulDirect { result[id, default: 1] *= muls.reduce(1.0, *) }
        for (id, value) in pendingPostAssign { result[id] = value }
        return result
    }

    private static func applyItemModifiers(
        attrs: [Int: Double],
        effectIds: Set<Int>,
        state: ModuleState,
        effectModifiers: [Int: [ModifierRow]]
    ) -> [Int: Double] {
        applyModifiers(
            sourceAttrs: attrs,
            targetAttrs: attrs,
            effectIds: effectIds,
            domain: "itemID",
            state: state,
            effectModifiers: effectModifiers
        )
    }

    /// Returns whether a module effect fires at the given module state.
    private static func effectFires(category: Int, state: ModuleState) -> Bool {
        switch category {
        case 0, 4: return state.isOnline      // passive / online
        case 1:    return state.isActive      // active
        case 5:    return state == .overload  // overload
        default:   return state.isOnline
        }
    }

    // MARK: - Main entry point

    /// Calculate fitted ship statistics.
    ///
    /// - Parameters:
    ///   - shipProfile:       Raw attribute map + effect IDs for the ship hull.
    ///   - moduleProfiles:    Attribute maps + effect IDs + group/skills, keyed by typeId.
    ///   - modules:           Per-slot module instances with state and loaded charge.
    ///   - characterSkills:   Character's trained skill levels (skillTypeId → 0–5).
    ///   - skillProfiles:     TypeProfile for each skill the character has trained.
    ///   - implantProfiles:   TypeProfile for each implant currently plugged in.
    ///   - effectModifiers:   ModifierRow arrays from dogma_modifiers, keyed by effectId.
    ///                        Must include ship, skill, module AND implant effect IDs.
    public static func calculate(
        shipProfile: TypeProfile,
        moduleProfiles: [Int: TypeProfile],
        modules: [FittedModuleInput],
        characterSkills: [Int: Int] = [:],
        skillProfiles: [Int: TypeProfile] = [:],
        implantProfiles: [Int: TypeProfile] = [:],
        effectModifiers: [Int: [ModifierRow]] = [:]
    ) -> ShipStats {

        // ── Phase A: Skill attribute scaling ────────────────────────────────────
        // Part 1 — PreMul (op=0, modifying=skillLevel=280):
        //   Scales each skill's own attrs by level, and scales hull bonus attrs
        //   on the ship that the skill PreMuls (e.g. HAC bonus attr on Cerberus).
        // Part 2 — PostPercent/PostMul/ModAdd from skills to ship attrs:
        //   Applies skill bonuses like PG output (+5%/level), CPU output, cap, etc.
        var effectiveShipBonusAttrs = shipProfile.attrs
        var effectiveSkillAttrs: [Int: [Int: Double]] = [:]

        for (skillId, level) in characterSkills where level > 0 {
            guard let sp = skillProfiles[skillId] else { continue }
            var skillAttrs = sp.attrs
            for effectId in sp.effectIds {
                for m in effectModifiers[effectId] ?? [] {
                    guard m.operation == 0, m.modifyingAttrId == A.skillLevel else { continue }
                    if m.domain == "itemID", m.function_ == "ItemModifier" {
                        if let base = sp.attrs[m.modifiedAttrId] {
                            skillAttrs[m.modifiedAttrId] = base * Double(level)
                        }
                    } else if m.domain == "shipID", m.function_ == "ItemModifier" {
                        if let base = shipProfile.attrs[m.modifiedAttrId] {
                            effectiveShipBonusAttrs[m.modifiedAttrId] = base * Double(level)
                        }
                    }
                }
            }
            effectiveSkillAttrs[skillId] = skillAttrs
        }

        var effectiveModuleAttrsByType = moduleProfiles.mapValues(\.attrs)
        for (skillId, level) in characterSkills where level > 0 {
            guard let sp = skillProfiles[skillId] else { continue }
            let sAttrs = effectiveSkillAttrs[skillId] ?? sp.attrs
            for effectId in sp.effectIds {
                for m in effectModifiers[effectId] ?? [] {
                    guard m.domain == "shipID",
                          m.function_ == "LocationGroupModifier",
                          let groupId = m.groupId else { continue }

                    for (typeId, profile) in moduleProfiles where profile.groupId == groupId {
                        let val = m.modifyingAttrId == A.skillLevel
                            ? Double(level)
                            : sAttrs[m.modifyingAttrId] ?? 0
                        guard val != 0 else { continue }

                        switch m.operation {
                        case -1:
                            effectiveModuleAttrsByType[typeId, default: [:]][m.modifiedAttrId] = val
                        case 2:
                            effectiveModuleAttrsByType[typeId, default: [:]][m.modifiedAttrId, default: 0] += val
                        case 3:
                            effectiveModuleAttrsByType[typeId, default: [:]][m.modifiedAttrId, default: 0] -= val
                        case 0, 4, 5, 6:
                            guard let factor = multiplier(value: val, operation: m.operation) else { continue }
                            effectiveModuleAttrsByType[typeId, default: [:]][m.modifiedAttrId, default: 0] *= factor
                        case 7:
                            effectiveModuleAttrsByType[typeId, default: [:]][m.modifiedAttrId] = val
                        default:
                            break
                        }
                    }
                }
            }
        }

        var effectiveImplantAttrs = implantProfiles.mapValues(\.attrs)
        for (_, sourceProfile) in implantProfiles {
            for effectId in sourceProfile.effectIds {
                for m in effectModifiers[effectId] ?? [] {
                    guard m.domain == "charID",
                          m.operation == 0,
                          let factor = multiplier(value: sourceProfile.attrs[m.modifyingAttrId] ?? 0, operation: m.operation) else { continue }

                    for (targetTypeId, targetProfile) in implantProfiles {
                        let matches: Bool
                        if m.function_ == "LocationGroupModifier",
                           let groupId = m.groupId,
                           targetProfile.groupId == groupId {
                            matches = true
                        } else if m.function_ == "LocationRequiredSkillModifier" {
                            matches = m.skillTypeId.map { targetProfile.requiredSkillIds.contains($0) } ?? true
                        } else {
                            matches = false
                        }

                        guard matches,
                              targetProfile.attrs[m.modifiedAttrId] != nil else { continue }
                        effectiveImplantAttrs[targetTypeId, default: [:]][m.modifiedAttrId, default: 0] *= factor
                    }
                }
            }
        }

        // ── Phase B: Apply module → ship attribute modifiers (DB-driven) ────────
        // Replaces the old hardcoded effect table. Reads ALL module effects from
        // effectModifiers and applies domain=shipID ItemModifier entries to ship attrs.
        var pgUsed   = 0.0
        var cpuUsed  = 0.0
        var capDrain = 0.0
        var moduleCosts: [FittedModuleCost] = []

        // ── Pre-Phase: Per-module attribute modifier lookups ─────────────────────
        // EVE applies LocationRequiredSkillModifier (from skills) and LocationGroupModifier
        // (from the ship hull) to individual MODULE attributes — power(30), cpu(50),
        // capacitorNeed(6), duration(73), dmgMultiplier(64), etc.
        // Pre-compute these once so Phase B and D can apply them per-module efficiently.

        // [modifiedAttrId → [requiredSkillTypeId → cumulative factor]]  (skills, NOT stacking penalized)
        var skillLocReqMuls: [Int: [Int: Double]] = [:]
        var locationMuls: [Int: Double] = [:]
        for (skillId, level) in characterSkills where level > 0 {
            guard let sp = skillProfiles[skillId] else { continue }
            let sAttrs = effectiveSkillAttrs[skillId] ?? sp.attrs
            for effectId in sp.effectIds {
                for m in effectModifiers[effectId] ?? [] {
                    guard m.domain == "shipID",
                          [0, 4, 5, 6].contains(m.operation) else { continue }
                    let val = sAttrs[m.modifyingAttrId] ?? 0
                    guard let factor = multiplier(value: val, operation: m.operation) else { continue }
                    if m.function_ == "LocationRequiredSkillModifier", let reqSkill = m.skillTypeId {
                        skillLocReqMuls[m.modifiedAttrId, default: [:]][reqSkill, default: 1.0] *= factor
                    } else if m.function_ == "LocationModifier" {
                        locationMuls[m.modifiedAttrId, default: 1.0] *= factor
                    }
                }

                if legacyCpuNeedSkillEffects.contains(effectId),
                   let bonus = sAttrs[A.cpuNeedBonus],
                   let factor = multiplier(value: bonus, operation: 6) {
                    skillLocReqMuls[A.cpu, default: [:]][skillId, default: 1.0] *= factor
                }
            }
        }

        // [modifiedAttrId → [moduleGroupId → cumulative factor]]  (ship hull, stacking penalized with modules)
        var shipLocGrpMuls: [Int: [Int: Double]] = [:]
        var shipLocReqMuls: [Int: [Int: Double]] = [:]
        for effectId in shipProfile.effectIds {
            for m in effectModifiers[effectId] ?? [] {
                guard m.domain == "shipID",
                      [0, 4, 5, 6].contains(m.operation) else { continue }
                let val = effectiveShipBonusAttrs[m.modifyingAttrId] ?? 0
                guard let factor = multiplier(value: val, operation: m.operation) else { continue }
                if m.function_ == "LocationGroupModifier", let gid = m.groupId {
                    shipLocGrpMuls[m.modifiedAttrId, default: [:]][gid, default: 1.0] *= factor
                } else if m.function_ == "LocationRequiredSkillModifier", let reqSkill = m.skillTypeId {
                    shipLocReqMuls[m.modifiedAttrId, default: [:]][reqSkill, default: 1.0] *= factor
                } else if m.function_ == "LocationModifier" {
                    locationMuls[m.modifiedAttrId, default: 1.0] *= factor
                }
            }
        }

        // [modifiedAttrId → [moduleGroupId → cumulative factor]]
        // Online fitted modules/subsystems can also modify attributes of other modules
        // by group. T3 subsystem fitting reductions live here, not on the hull.
        var moduleLocGrpMuls: [Int: [Int: Double]] = [:]
        for source in modules where source.state.isOnline {
            guard let sourceProfile = moduleProfiles[source.typeId] else { continue }
            let sourceAttrs = effectiveModuleAttrsByType[source.typeId] ?? sourceProfile.attrs
            for effectId in sourceProfile.effectIds {
                if let drawbackTarget = rigModuleDrawbackEffectTargets[effectId] {
                    let drawback = effectiveRigDrawbackPercent(for: sourceProfile, attrs: sourceAttrs)
                    if drawback != 0 {
                        let factor = 1.0 + drawback / 100.0
                        for groupId in drawbackTarget.groupIds {
                            moduleLocGrpMuls[drawbackTarget.attrId, default: [:]][groupId, default: 1.0] *= factor
                        }
                    }
                }

                for m in effectModifiers[effectId] ?? [] {
                    guard m.domain == "shipID",
                          let factor = multiplier(value: sourceAttrs[m.modifyingAttrId] ?? 0, operation: m.operation),
                          effectFires(category: m.effectCategory, state: source.state) else { continue }
                    if m.function_ == "LocationGroupModifier", let gid = m.groupId {
                        moduleLocGrpMuls[m.modifiedAttrId, default: [:]][gid, default: 1.0] *= factor
                    } else if m.function_ == "LocationModifier" {
                        locationMuls[m.modifiedAttrId, default: 1.0] *= factor
                    }
                }
            }
        }

        var implantLocReqMuls: [Int: [Int: Double]] = [:]
        for (implantTypeId, implant) in implantProfiles {
            let implantAttrs = effectiveImplantAttrs[implantTypeId] ?? implant.attrs
            for effectId in implant.effectIds {
                for m in effectModifiers[effectId] ?? [] {
                    guard m.domain == "shipID",
                          m.function_ == "LocationRequiredSkillModifier",
                          [0, 4, 5, 6].contains(m.operation),
                          let reqSkill = m.skillTypeId,
                          let factor = multiplier(value: implantAttrs[m.modifyingAttrId] ?? 0, operation: m.operation) else { continue }
                    implantLocReqMuls[m.modifiedAttrId, default: [:]][reqSkill, default: 1.0] *= factor
                }
            }
        }

        // Returns the effective multiplier for a module attribute given its group and required skills.
        func modAttrFactor(_ attrId: Int, groupId: Int, reqSkills: Set<Int>) -> Double {
            var f = locationMuls[attrId] ?? 1.0
            f *= shipLocGrpMuls[attrId]?[groupId] ?? 1.0
            f *= moduleLocGrpMuls[attrId]?[groupId] ?? 1.0
            if let reqMap = shipLocReqMuls[attrId] {
                for sk in reqSkills { f *= reqMap[sk] ?? 1.0 }
            }
            if let reqMap = skillLocReqMuls[attrId] {
                for sk in reqSkills { f *= reqMap[sk] ?? 1.0 }
            }
            if let reqMap = implantLocReqMuls[attrId] {
                for sk in reqSkills { f *= reqMap[sk] ?? 1.0 }
            }
            return f
        }

        func effectiveChargeAttrs(for mod: FittedModuleInput) -> [Int: Double]? {
            guard var attrs = mod.chargeAttrs else { return nil }
            if let profile = mod.chargeProfile {
                attrs = applyItemModifiers(
                    attrs: attrs,
                    effectIds: profile.effectIds,
                    state: mod.state,
                    effectModifiers: effectModifiers
                )
            }
            return attrs
        }

        func effectiveModuleAttrs(for mod: FittedModuleInput) -> [Int: Double] {
            var attrs = effectiveModuleAttrsByType[mod.typeId] ?? moduleProfiles[mod.typeId]?.attrs ?? [:]
            if let profile = moduleProfiles[mod.typeId] {
                attrs = applyItemModifiers(
                    attrs: attrs,
                    effectIds: profile.effectIds,
                    state: mod.state,
                    effectModifiers: effectModifiers
                )
            }
            if let chargeProfile = mod.chargeProfile,
               let chargeAttrs = effectiveChargeAttrs(for: mod) {
                attrs = applyModifiers(
                    sourceAttrs: chargeAttrs,
                    targetAttrs: attrs,
                    effectIds: chargeProfile.effectIds,
                    domain: "otherID",
                    state: mod.state,
                    effectModifiers: effectModifiers
                )
            }
            return attrs
        }

        func effectiveRigDrawbackPercent(for profile: TypeProfile, attrs: [Int: Double]) -> Double {
            let baseDrawback = attrs[A.drawback] ?? 0
            guard baseDrawback != 0,
                  let skillId = rigDrawbackSkillByGroup[profile.groupId],
                  let level = characterSkills[skillId],
                  level > 0,
                  let skillProfile = skillProfiles[skillId] else {
                return baseDrawback
            }

            let perLevel = skillProfile.attrs[A.rigDrawbackBonus] ?? 0
            guard perLevel != 0 else { return baseDrawback }
            let reduction = perLevel * Double(level)
            return baseDrawback * (1.0 + reduction / 100.0)
        }

        // Collect pending modifications, keyed by attrId
        var pendingAdd: [Int: Double]    = [:]  // op=2 additions
        var pendingMulStack: [Int: [Double]] = [:]  // stackable=0 multipliers
        var pendingMulDirect: [Int: [Double]] = [:]  // stackable=1 multipliers
        var pendingPreAssign: [Int: Double] = [:]  // op=-1
        var pendingPostAssign: [Int: Double] = [:] // op=7

        // Skill → ship PostPercent/PostMul/ModAdd effects collected here (not in Phase A) so
        // they apply after all ModAdd contributions — matching EVE's attribute calculation order
        // (ModAdd first, then PostPercent). Skills are never stacking-penalized.
        for (skillId, level) in characterSkills where level > 0 {
            guard let sp = skillProfiles[skillId] else { continue }
            let sAttrs = effectiveSkillAttrs[skillId] ?? sp.attrs
            for effectId in sp.effectIds {
                for m in effectModifiers[effectId] ?? [] {
                    guard m.domain == "shipID", m.function_ == "ItemModifier",
                          m.operation != 0 else { continue }
                    let val = sAttrs[m.modifyingAttrId] ?? 0
                    guard val != 0 else { continue }
                    switch m.operation {
                    case -1: pendingPreAssign[m.modifiedAttrId] = val
                    case 2: pendingAdd[m.modifiedAttrId, default: 0] += val
                    case 3: pendingAdd[m.modifiedAttrId, default: 0] -= val
                    case 4, 5, 6:
                        if let factor = multiplier(value: val, operation: m.operation) {
                            pendingMulDirect[m.modifiedAttrId, default: []].append(factor)
                        }
                    case 7: pendingPostAssign[m.modifiedAttrId] = val
                    default: break
                    }
                }
            }
        }

        // Ship hull effects can modify the ship's own attributes after their
        // bonus attributes have been scaled by the relevant ship skill.
        // Example: Drake's Caldari Battlecruiser shield resistance bonus scales
        // attr745 in Phase A, then effects 5335-5338 apply it to shield resists.
        for effectId in shipProfile.effectIds {
            for m in effectModifiers[effectId] ?? [] {
                guard m.domain == "shipID", m.function_ == "ItemModifier",
                      m.operation != 0 else { continue }
                let val = effectiveShipBonusAttrs[m.modifyingAttrId] ?? 0
                guard val != 0 else { continue }
                switch m.operation {
                case -1:
                    pendingPreAssign[m.modifiedAttrId] = val
                case 2:
                    pendingAdd[m.modifiedAttrId, default: 0] += val
                case 3:
                    pendingAdd[m.modifiedAttrId, default: 0] -= val
                case 4, 5, 6:
                    if let factor = multiplier(value: val, operation: m.operation) {
                        pendingMulDirect[m.modifiedAttrId, default: []].append(factor)
                    }
                case 7:
                    pendingPostAssign[m.modifiedAttrId] = val
                default:
                    break
                }
            }
        }

        for (implantTypeId, implant) in implantProfiles {
            let implantAttrs = effectiveImplantAttrs[implantTypeId] ?? implant.attrs
            for effectId in implant.effectIds {
                for m in effectModifiers[effectId] ?? [] {
                    guard m.domain == "shipID", m.function_ == "ItemModifier",
                          m.operation != 0,
                          effectFires(category: m.effectCategory, state: .online) else { continue }
                    let val = implantAttrs[m.modifyingAttrId] ?? 0
                    guard val != 0 else { continue }
                    let stacks = stackPenaltyAttrs.contains(m.modifiedAttrId) && effectId != damageControlEffect
                    switch m.operation {
                    case -1:
                        pendingPreAssign[m.modifiedAttrId] = val
                    case 2:
                        pendingAdd[m.modifiedAttrId, default: 0] += val
                    case 3:
                        pendingAdd[m.modifiedAttrId, default: 0] -= val
                    case 4, 5, 6:
                        guard let factor = multiplier(value: val, operation: m.operation) else { continue }
                        if stacks {
                            pendingMulStack[m.modifiedAttrId, default: []].append(factor)
                        } else {
                            pendingMulDirect[m.modifiedAttrId, default: []].append(factor)
                        }
                    case 7:
                        pendingPostAssign[m.modifiedAttrId] = val
                    default:
                        break
                    }
                }
            }
        }

        for mod in modules {
            guard mod.state.isOnline else { continue }
            guard let mp = moduleProfiles[mod.typeId] else { continue }
            let mAttrs = effectiveModuleAttrs(for: mod)

            let pgF  = modAttrFactor(A.powerLoad, groupId: mp.groupId, reqSkills: mp.requiredSkillIds)
            let cpuF = modAttrFactor(A.cpu,       groupId: mp.groupId, reqSkills: mp.requiredSkillIds)
            let modPG = (mAttrs[A.powerLoad] ?? 0) * pgF
            let modCPU = (mAttrs[A.cpu] ?? 0) * cpuF
            pgUsed += modPG
            cpuUsed += modCPU
            moduleCosts.append(FittedModuleCost(flag: mod.flag, typeId: mod.typeId, pg: modPG, cpu: modCPU))

            if mod.state.isActive {
                let capF = modAttrFactor(A.capNeed,  groupId: mp.groupId, reqSkills: mp.requiredSkillIds)
                let durF = modAttrFactor(A.duration, groupId: mp.groupId, reqSkills: mp.requiredSkillIds)
                let cap  = (mAttrs[A.capNeed]  ?? 0) * capF
                let dur  = max(1, (mAttrs[A.duration] ?? 1) * durF)
                if cap > 0 { capDrain += cap / (dur / 1000.0) }
            }

            for effectId in mp.effectIds {
                if let drawbackTarget = rigShipDrawbackEffectTargets[effectId] {
                    let drawback = effectiveRigDrawbackPercent(for: mp, attrs: mAttrs)
                    if drawback != 0 {
                        let factor = 1.0 + drawbackTarget.sign * drawback / 100.0
                        if stackPenaltyAttrs.contains(drawbackTarget.attrId) {
                            pendingMulStack[drawbackTarget.attrId, default: []].append(factor)
                        } else {
                            pendingMulDirect[drawbackTarget.attrId, default: []].append(factor)
                        }
                    }
                }

                for m in effectModifiers[effectId] ?? [] {
                    guard m.domain == "shipID", m.function_ == "ItemModifier" else { continue }
                    guard effectFires(category: m.effectCategory, state: mod.state) else { continue }

                    let val = mAttrs[m.modifyingAttrId] ?? 0
                    let stacks = stackPenaltyAttrs.contains(m.modifiedAttrId) && effectId != damageControlEffect
                    switch m.operation {
                    case -1:
                        pendingPreAssign[m.modifiedAttrId] = val
                    case 2:    // ModAdd
                        pendingAdd[m.modifiedAttrId, default: 0] += val
                    case 3:
                        pendingAdd[m.modifiedAttrId, default: 0] -= val
                    case 0, 4, 5, 6:
                        guard let factor = multiplier(value: val, operation: m.operation) else { continue }
                        if stacks { pendingMulStack[m.modifiedAttrId, default: []].append(factor) }
                        else      { pendingMulDirect[m.modifiedAttrId, default: []].append(factor) }
                    case 7:
                        pendingPostAssign[m.modifiedAttrId] = val
                    default: break
                    }
                }
            }
        }

        // Start from hull base attrs; skill and module modifiers all applied via pending above.
        var a = effectiveShipBonusAttrs  // = shipProfile.attrs (Phase A only does op=0 on skills)
        for (id, value) in pendingPreAssign { a[id] = value }
        for (id, sum) in pendingAdd { a[id, default: 0] += sum }
        for (id, muls) in pendingMulStack  { a[id, default: 1] *= stackedProduct(muls) }
        for (id, muls) in pendingMulDirect { a[id, default: 1] *= muls.reduce(1.0, *) }
        for (id, value) in pendingPostAssign { a[id] = value }

        // ── Phase C: Per-module-type RoF multipliers ─────────────────────────────
        // Sources: ship effects (LocationGroup), skill effects (LocationRequired + legacy),
        //          module effects (LocationGroup / LocationRequired), implants.
        let activeTypeIds = Set(modules.filter { $0.state.isActive }.map(\.typeId))
        var rofMulsByTypeId: [Int: Double] = [:]

        for typeId in activeTypeIds {
            guard let mp = moduleProfiles[typeId] else { continue }
            // Skill bonuses (from skill entity) are NOT stacking penalized in EVE.
            // Ship/subsystem bonuses are hull configuration, not damage-mod stacking.
            // Fitted modules and implants use normal stacking where the target attr requires it.
            var directRofFactors: [Double] = []   // skills — multiply directly
            var stackedRofFactors: [Double] = []  // damage mods / implants — stacking

            func toFactor(_ val: Double, _ op: Int) -> Double? {
                multiplier(value: val, operation: op)
            }

            // 1. Ship effects → LocationGroupModifier (e.g. HAC RoF bonus) — direct
            for effectId in shipProfile.effectIds {
                for m in effectModifiers[effectId] ?? [] {
                    guard m.domain == "shipID", m.function_ == "LocationGroupModifier",
                          m.modifiedAttrId == A.turretRoFMs,
                          let gid = m.groupId, gid == mp.groupId else { continue }
                    if let f = toFactor(effectiveShipBonusAttrs[m.modifyingAttrId] ?? 0, m.operation) {
                        directRofFactors.append(f)
                    }
                }
            }

            // 2. Skill effects → LocationRequiredSkillModifier (e.g. RL, MLO) — direct (no penalty)
            //    and legacy self-RoF (HAMSpec) — also direct
            for (skillId, _) in characterSkills {
                guard let sp = skillProfiles[skillId] else { continue }
                let sAttrs = effectiveSkillAttrs[skillId] ?? sp.attrs
                for effectId in sp.effectIds {
                    for m in effectModifiers[effectId] ?? [] {
                        guard m.domain == "shipID", m.function_ == "LocationRequiredSkillModifier",
                              m.modifiedAttrId == A.turretRoFMs,
                              let reqSkill = m.skillTypeId,
                              mp.requiredSkillIds.contains(reqSkill) else { continue }
                        if let f = toFactor(sAttrs[m.modifyingAttrId] ?? 0, m.operation) {
                            directRofFactors.append(f)
                        }
                    }
                    // Legacy self-RoF (effect 1851) — fires for modules requiring this skill
                    if effectId == legacyRoFEffect, mp.requiredSkillIds.contains(skillId) {
                        let val = sAttrs[293] ?? 0
                        if val != 0 { directRofFactors.append(1.0 + val / 100.0) }
                    }
                }
            }

            // 3. Fitted module effects → LocationGroupModifier / LocationRequiredSkillModifier.
            // Subsystems act as ship configuration bonuses; regular fitted modules stack.
            for mod in modules where mod.state.isOnline {
                guard let sourceMp = moduleProfiles[mod.typeId] else { continue }
                let sourceAttrs = effectiveModuleAttrs(for: mod)
                let sourceIsSubsystem = sourceMp.effectIds.contains(3772)
                for effectId in sourceMp.effectIds {
                    for m in effectModifiers[effectId] ?? [] {
                        guard m.domain == "shipID", m.modifiedAttrId == A.turretRoFMs else { continue }
                        guard effectFires(category: m.effectCategory, state: mod.state) else { continue }
                        let val = sourceAttrs[m.modifyingAttrId] ?? 0
                        let matches: Bool
                        if m.function_ == "LocationGroupModifier",
                           let gid = m.groupId, gid == mp.groupId {
                            matches = true
                        } else if m.function_ == "LocationRequiredSkillModifier",
                                  let reqSkill = m.skillTypeId,
                                  mp.requiredSkillIds.contains(reqSkill) {
                            matches = true
                        } else {
                            matches = false
                        }
                        if matches, let f = toFactor(val, m.operation) {
                            if sourceIsSubsystem {
                                directRofFactors.append(f)
                            } else {
                                stackedRofFactors.append(f)
                            }
                        }
                    }
                }
            }

            // 4. Implant effects → LocationRequiredSkillModifier.
            // Hardwiring RoF bonuses are implant bonuses and do not share the
            // module damage-mod stacking penalty with BCS/gyros/heat sinks.
            for (implantTypeId, ip) in implantProfiles {
                let implantAttrs = effectiveImplantAttrs[implantTypeId] ?? ip.attrs
                for effectId in ip.effectIds {
                    for m in effectModifiers[effectId] ?? [] {
                        guard m.domain == "shipID", m.function_ == "LocationRequiredSkillModifier",
                              m.modifiedAttrId == A.turretRoFMs,
                              let reqSkill = m.skillTypeId,
                              mp.requiredSkillIds.contains(reqSkill) else { continue }
                        if let f = toFactor(implantAttrs[m.modifyingAttrId] ?? 0, m.operation) {
                            directRofFactors.append(f)
                        }
                    }
                }
            }

            let combinedRoF = directRofFactors.reduce(1.0, *)
                            * (stackedRofFactors.isEmpty ? 1.0 : stackedProduct(stackedRofFactors))
            if combinedRoF != 1.0 {
                rofMulsByTypeId[typeId] = combinedRoF
            }
        }

        // ── Phase D: Per-module turret damage multiplier (attr64) ───────────────
        // Modules like Gyrostabilizer / MFS / Heat Sink give LocationGroupModifier on attr64.
        var turretDmgMulsByTypeId: [Int: Double] = [:]

        for typeId in activeTypeIds {
            guard let mp = moduleProfiles[typeId] else { continue }
            var stackedDmgFactors: [Double] = []  // Gyros/MFS damage mods — stacking
            var directDmgFactors:  [Double] = []  // Skills and ship/subsystem bonuses

            // Module effects (e.g. Gyrostabilizer LocationGroupModifier on attr64)
            for mod in modules where mod.state.isOnline {
                guard let sourceMp = moduleProfiles[mod.typeId] else { continue }
                let sourceAttrs = effectiveModuleAttrs(for: mod)
                let sourceIsSubsystem = sourceMp.effectIds.contains(3772)
                for effectId in sourceMp.effectIds {
                    for m in effectModifiers[effectId] ?? [] {
                        guard m.domain == "shipID", m.modifiedAttrId == A.dmgMultiplier,
                              m.function_ == "LocationGroupModifier",
                              let gid = m.groupId, gid == mp.groupId else { continue }
                        guard effectFires(category: m.effectCategory, state: mod.state) else { continue }
                        let val = sourceAttrs[m.modifyingAttrId] ?? 0
                        guard val > 0 else { continue }
                        if let factor = multiplier(value: val, operation: m.operation) {
                            if sourceIsSubsystem {
                                directDmgFactors.append(factor)
                            } else {
                                stackedDmgFactors.append(factor)
                            }
                        }
                    }
                }
            }

            // Ship hull LocationGroupModifier on dmgMultiplier (e.g. Stabber +% projectile damage)
            if let hullF = shipLocGrpMuls[A.dmgMultiplier]?[mp.groupId], hullF != 1.0 {
                directDmgFactors.append(hullF)
            }

            // Skill LocationRequiredSkillModifier on dmgMultiplier (e.g. Large Projectile Turret +5%/level)
            if let reqMap = skillLocReqMuls[A.dmgMultiplier] {
                for reqSkill in mp.requiredSkillIds {
                    if let f = reqMap[reqSkill], f != 1.0 { directDmgFactors.append(f) }
                }
            }

            let combined = (stackedDmgFactors.isEmpty ? 1.0 : stackedProduct(stackedDmgFactors))
                         * directDmgFactors.reduce(1.0, *)
            if combined != 1.0 {
                turretDmgMulsByTypeId[typeId] = combined
            }
        }

        // ── Phase E: Charge damage multipliers keyed by required skill ──────────
        // Covers: skill OwnerRequired, ship OwnerRequired, implant OwnerRequired.
        // They are applied later per loaded charge, because mixed-launcher fits must
        // not leak a Heavy Missile-only bonus onto Heavy Assault Missile charges.
        // Per-module legacy missile skill bonuses are applied in the DPS loop.
        var chargeAttrMulsByRequiredSkill: [Int: [Int: Double]] = [:]

        func collectOwnerRequiredChargeMuls(
            effectIds: Set<Int>, attrs: [Int: Double],
            ownerSkillCheck: (Int) -> Bool
        ) {
            for effectId in effectIds {
                for m in effectModifiers[effectId] ?? [] {
                    guard m.domain == "charID",
                          m.function_ == "OwnerRequiredSkillModifier",
                          chargeDamageAttrIds.contains(m.modifiedAttrId),
                          m.operation == 6,
                          let reqSkill = m.skillTypeId,
                          ownerSkillCheck(reqSkill) else { continue }
                    let val = attrs[m.modifyingAttrId] ?? 0
                    if val != 0 {
                        chargeAttrMulsByRequiredSkill[reqSkill, default: [:]][m.modifiedAttrId, default: 1.0] *= 1.0 + val / 100.0
                    }
                }
            }
        }

        // Skill effects
        for (skillId, level) in characterSkills where level > 0 {
            guard let sp = skillProfiles[skillId] else { continue }
            let sAttrs = effectiveSkillAttrs[skillId] ?? sp.attrs
            collectOwnerRequiredChargeMuls(effectIds: sp.effectIds, attrs: sAttrs) {
                (characterSkills[$0] ?? 0) >= 1
            }
        }

        // Ship effects (e.g. Cerberus kinetic bonus via CC skill chain)
        collectOwnerRequiredChargeMuls(effectIds: shipProfile.effectIds, attrs: effectiveShipBonusAttrs) {
            (characterSkills[$0] ?? 0) >= 1
        }

        // Implant effects (e.g. Zainou HAM damage implant)
        for (implantTypeId, ip) in implantProfiles {
            collectOwnerRequiredChargeMuls(
                effectIds: ip.effectIds,
                attrs: effectiveImplantAttrs[implantTypeId] ?? ip.attrs
            ) {
                (characterSkills[$0] ?? 0) >= 1
            }
        }

        // ── Phase F: Missile damage multiplier from BCS / damage mods ───────────
        // BCS effect: domain=charID, ItemModifier, op=0 (PreMul), modified=212, modifying=213
        // This modifies the charge's missileDamageMultiplier (attr212, stackable=0).
        // Applied globally (BCS affects all charged launchers equally).
        var bcsFactors: [Double] = []

        for mod in modules where mod.state.isOnline {
            guard let sourceMp = moduleProfiles[mod.typeId] else { continue }
            let sourceAttrs = effectiveModuleAttrs(for: mod)
            for effectId in sourceMp.effectIds {
                for m in effectModifiers[effectId] ?? [] {
                    guard m.domain == "charID", m.function_ == "ItemModifier",
                          m.modifiedAttrId == A.missileDmgMul, m.operation == 0 else { continue }
                    guard effectFires(category: m.effectCategory, state: mod.state) else { continue }
                    let val = sourceAttrs[m.modifyingAttrId] ?? 1.0
                    if val > 0 { bcsFactors.append(val) }
                }
            }
        }
        // Stacking penalty for attr212 (stackable=0)
        let bcsMissileDmgMul = bcsFactors.isEmpty ? 1.0 : stackedProduct(bcsFactors)

        // ── DPS calculation ──────────────────────────────────────────────────────
        var turretDPS  = 0.0
        var missileDPS = 0.0
        var missileReloadDPS = 0.0

        for mod in modules {
            guard mod.state.isActive else { continue }
            let mAttrs = effectiveModuleAttrs(for: mod)
            var rof = mAttrs[A.turretRoFMs] ?? 0
            guard rof > 0 else { continue }

            rof *= rofMulsByTypeId[mod.typeId] ?? 1.0

            let baseDmg = (mAttrs[A.emDmg]   ?? 0) + (mAttrs[A.expDmg]  ?? 0)
                        + (mAttrs[A.kinDmg]  ?? 0) + (mAttrs[A.thermDmg] ?? 0)
            if baseDmg > 0 {
                // Turret weapon — damage is on the module itself.
                // Base dmgMultiplier from module × additional from Gyro/MFS (turretDmgMulsByTypeId).
                let dmgMul = (mAttrs[A.dmgMultiplier] ?? 1.0) * (turretDmgMulsByTypeId[mod.typeId] ?? 1.0)
                turretDPS += baseDmg * dmgMul / (rof / 1000.0)
            } else if let cAttrs = effectiveChargeAttrs(for: mod) {
                // Missile launcher — damage is on the charge.
                // Per-charge multipliers: global (skills, ship, implants) × BCS × legacy missile skill.
                var muls: [Int: Double] = [:]
                for reqSkill in mod.chargeRequiredSkillIds {
                    guard let reqMuls = chargeAttrMulsByRequiredSkill[reqSkill] else { continue }
                    for (attrId, factor) in reqMuls {
                        muls[attrId, default: 1.0] *= factor
                    }
                }

                // BCS / missile damage module stacking multiplier on attr212
                // attr212 default = 1.0, BCS multiplies it → final charge damage scaling
                if bcsMissileDmgMul != 1.0 {
                    for aid in chargeDamageAttrIds { muls[aid, default: 1.0] *= bcsMissileDmgMul }
                }

                // Legacy missile type skill bonus (e.g. HAMs +5%/level)
                let sp = skillProfiles
                for (skillId, level) in characterSkills where level > 0 {
                    guard mod.chargeRequiredSkillIds.contains(skillId),
                          let skillPr = sp[skillId],
                          skillPr.effectIds.contains(where: { legacyMissileDmgEffects.contains($0) }) else { continue }
                    let sAttrs = effectiveSkillAttrs[skillId] ?? skillPr.attrs
                    let bonus = sAttrs[292] ?? 0
                    if bonus != 0 {
                        let mul = 1.0 + bonus / 100.0
                        for aid in chargeDamageAttrIds { muls[aid, default: 1.0] *= mul }
                    }
                }

                // Module/subsystem OwnerRequiredSkillModifier charge damage bonuses
                // (e.g. Tengu Offensive subsystem +5% kinetic).
                // Each modifier row fires only if the CHARGE requires the row's skillTypeId —
                // this prevents triple-stacking when a subsystem covers multiple missile categories.
                for srcMod in modules where srcMod.state.isOnline {
                    guard let srcMp = moduleProfiles[srcMod.typeId] else { continue }
                    let srcAttrs = effectiveModuleAttrs(for: srcMod)
                    for effectId in srcMp.effectIds {
                        for m in effectModifiers[effectId] ?? [] {
                            guard m.domain == "charID",
                                  m.function_ == "OwnerRequiredSkillModifier",
                                  chargeDamageAttrIds.contains(m.modifiedAttrId),
                                  m.operation == 6,
                                  let reqSkill = m.skillTypeId,
                                  mod.chargeRequiredSkillIds.contains(reqSkill),
                                  (characterSkills[reqSkill] ?? 0) >= 1 else { continue }
                            let val = srcAttrs[m.modifyingAttrId] ?? 0
                            if val != 0 { muls[m.modifiedAttrId, default: 1.0] *= 1.0 + val / 100.0 }
                        }
                    }
                }

                let emDmg = (cAttrs[A.emDmg]    ?? 0) * (muls[A.emDmg]    ?? 1.0)
                let exDmg = (cAttrs[A.expDmg]   ?? 0) * (muls[A.expDmg]   ?? 1.0)
                let kiDmg = (cAttrs[A.kinDmg]   ?? 0) * (muls[A.kinDmg]   ?? 1.0)
                let thDmg = (cAttrs[A.thermDmg] ?? 0) * (muls[A.thermDmg] ?? 1.0)
                let chDmg = emDmg + exDmg + kiDmg + thDmg
                if chDmg > 0 {
                    let cycleSeconds = rof / 1000.0
                    let rawDPS = chDmg / cycleSeconds
                    missileDPS += rawDPS

                    let chargesPerCycle = max(1, mAttrs[A.chargeRate] ?? 1)
                    let cyclesPerReload = (mod.moduleCapacity > 0 && mod.chargeVolume > 0)
                        ? floor((mod.moduleCapacity / (mod.chargeVolume * chargesPerCycle)) + 0.000_001)
                        : 0
                    let reloadSeconds = (mAttrs[A.reloadTimeMs] ?? 0) / 1000.0
                    if cyclesPerReload > 0 && reloadSeconds > 0 {
                        let firingSeconds = cyclesPerReload * cycleSeconds
                        missileReloadDPS += rawDPS * firingSeconds / (firingSeconds + reloadSeconds)
                    } else {
                        missileReloadDPS += rawDPS
                    }
                }
            }
        }

        // ── Final ship stats ─────────────────────────────────────────────────────
        func get(_ id: Int, d: Double = 0) -> Double { a[id] ?? d }
        func res(_ id: Int, fallback fallbackId: Int? = nil) -> Double {
            let value = a[id] ?? fallbackId.flatMap { a[$0] } ?? 1.0
            return max(0, min(1, value))
        }
        func pct(_ r: Double) -> Double { (1.0 - r) * 100.0 }
        func ehp(_ hp: Double, _ rs: Double...) -> Double {
            let avg = rs.reduce(0, +) / Double(rs.count)
            return avg > 0 ? hp / avg : hp
        }

        let sHP  = get(A.shieldHP)
        let sRch = max(1, get(A.shieldRechargeMs, d: 1_000_000))
        let sEMR = res(A.shieldEMRes);  let sExR = res(A.shieldExpRes)
        let sKiR = res(A.shieldKinRes); let sThR = res(A.shieldThermRes)
        let sEHP = ehp(sHP, sEMR, sExR, sKiR, sThR)
        let peakShRegen = sHP * 2.5 / (sRch / 1000.0)

        let aHP  = get(A.armorHP)
        let aEMR = res(A.armorEMRes);  let aExR = res(A.armorExpRes)
        let aKiR = res(A.armorKinRes); let aThR = res(A.armorThermRes)
        let aEHP = ehp(aHP, aEMR, aExR, aKiR, aThR)

        let hHP  = get(A.hullHP)
        let hEMR = res(A.legacyHullEMRes, fallback: A.hullEMRes)
        let hExR = res(A.legacyHullExpRes, fallback: A.hullExpRes)
        let hKiR = res(A.legacyHullKinRes, fallback: A.hullKinRes)
        let hThR = res(A.legacyHullThermRes, fallback: A.hullThermRes)
        let hEHP = ehp(hHP, hEMR, hExR, hKiR, hThR)

        let capCap  = get(A.capCapacity)
        let capRch  = max(1, get(A.capRechargeMs))
        let capRegen = capCap > 0 ? capCap * 2.5 / (capRch / 1000.0) : 0
        let sensorStrength = [
            get(A.scanRadar),
            get(A.scanLadar),
            get(A.scanMagnetometric),
            get(A.scanGravimetric),
            get(A.scanGeneric),
        ].max() ?? 0

        return ShipStats(
            shieldHP: sHP, shieldEHP: sEHP,
            shieldRechargeMs: sRch, peakShieldRegen: peakShRegen,
            shieldEMRes: pct(sEMR), shieldExpRes: pct(sExR),
            shieldKinRes: pct(sKiR), shieldThermRes: pct(sThR),
            armorHP: aHP, armorEHP: aEHP,
            armorEMRes: pct(aEMR), armorExpRes: pct(aExR),
            armorKinRes: pct(aKiR), armorThermRes: pct(aThR),
            hullHP: hHP,
            hullEMRes: pct(hEMR), hullExpRes: pct(hExR),
            hullKinRes: pct(hKiR), hullThermRes: pct(hThR),
            totalEHP: sEHP + aEHP + hEHP,
            capCapacity: capCap, capRechargeMs: capRch,
            capRegenPerSec: capRegen, capDrainPerSec: capDrain,
            maxVelocity: get(A.maxVelocity),
            signatureRadius: get(A.signatureRadius),
            maxTargetRange: get(A.maxTargetRange),
            scanResolution: get(A.scanResolution),
            maxLockedTargets: get(A.maxLockedTargets),
            sensorStrength: sensorStrength,
            droneCapacity: get(A.droneCapacity),
            droneBandwidth: get(A.droneBandwidth),
            droneControlRange: get(A.droneControlDistance),
            pgTotal: get(A.pgOutput), pgUsed: pgUsed,
            cpuTotal: get(A.cpuOutput), cpuUsed: cpuUsed,
            turretDPS: turretDPS, missileDPS: missileDPS,
            missileReloadDPS: missileReloadDPS,
            moduleCosts: moduleCosts
        )
    }
}
