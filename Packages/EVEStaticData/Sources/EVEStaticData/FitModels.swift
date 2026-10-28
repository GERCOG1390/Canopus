// Fitting models the screens use. The numbers come from the desktop's dogma engine (DogmaJS.swift); the
// old Swift engine was removed.

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

// MARK: - Results

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
    public let activeShieldBoostPerSec: Double
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
    public let agility: Double
    public let mass: Double
    /// Align time in seconds: −ln(0.25) × mass(kg) × agility / 1_000_000
    public let alignTime: Double
    /// Warp speed in AU/s
    public let warpSpeed: Double

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

    // Fitting layout after hull/subsystem modifiers
    public let highSlots: Double
    public let mediumSlots: Double
    public let lowSlots: Double
    public let rigSlots: Double

    // Offense
    public let turretDPS: Double
    public let missileDPS: Double
    public let missileReloadDPS: Double
    public var droneDPS: Double = 0

    // Per-module fitting costs after skills, hull, subsystem, script and charge modifiers.
    public let moduleCosts: [FittedModuleCost]
}

/// What a module can do when activated, by the desktop's rules: it starts active when it has a timed
/// activatable effect and isn't a one-shot (disallowRepeatingActivation); overload when it has an
/// overload effect.
public struct ModuleActivation: Sendable {
    public let activatable: Bool
    public let overloadable: Bool

    public var defaultState: ModuleState { activatable ? .active : .online }
}
