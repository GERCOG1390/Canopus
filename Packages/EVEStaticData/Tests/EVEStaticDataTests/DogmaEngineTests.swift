import Testing
import Foundation
@testable import EVEStaticData

@Suite("DogmaEngine")
struct DogmaEngineTests {

    @Test func launchersWithoutCapacitorNeedAreActiveModules() {
        #expect(DogmaEngine.isActiveModule([
            51: 6_400,
            56: 1,
            604: 772,
        ]))
        #expect(!DogmaEngine.isActiveModule([
            30: 160,
            50: 45,
            263: 2_600,
        ]))
    }

    @Test func strategicCruiserSubsystemBonusesScaleWithSubsystemSkillLevel() {
        let caldariOffensiveSystems = 30549
        let heavyAssaultMissiles = 25719
        let missileLauncherOperation = 3319
        let tenguOffensiveSubsystem = 45601
        let heavyAssaultLauncher = 25715

        let ship = TypeProfile(attrs: [11: 420, 48: 310], effectIds: [])
        let subsystem = TypeProfile(
            attrs: [
                1444: -7.5,
                1510: 5,
                2669: -25,
            ],
            effectIds: [3772, 4122, 4248, 6900],
            groupId: 956
        )
        let launcher = TypeProfile(
            attrs: [
                30: 113,
                50: 50,
                51: 6_400,
            ],
            effectIds: [],
            groupId: 771,
            requiredSkillIds: [missileLauncherOperation, heavyAssaultMissiles]
        )
        let skill = TypeProfile(
            attrs: [280: 0],
            effectIds: [3846, 4209]
        )
        let modifiers: [Int: [ModifierRow]] = [
            3846: [
                ModifierRow(domain: "shipID", function_: "LocationGroupModifier", groupId: 956,
                            modifiedAttrId: 1444, modifyingAttrId: 280, operation: 0,
                            skillTypeId: nil),
            ],
            4209: [
                ModifierRow(domain: "shipID", function_: "LocationGroupModifier", groupId: 956,
                            modifiedAttrId: 1510, modifyingAttrId: 280, operation: 0,
                            skillTypeId: nil),
            ],
            4122: [
                ModifierRow(domain: "shipID", function_: "LocationGroupModifier", groupId: 771,
                            modifiedAttrId: 51, modifyingAttrId: 1444, operation: 6,
                            skillTypeId: nil),
            ],
            4248: [
                ModifierRow(domain: "charID", function_: "OwnerRequiredSkillModifier", groupId: nil,
                            modifiedAttrId: 117, modifyingAttrId: 1510, operation: 6,
                            skillTypeId: heavyAssaultMissiles),
            ],
            6900: [
                ModifierRow(domain: "shipID", function_: "LocationGroupModifier", groupId: 771,
                            modifiedAttrId: 30, modifyingAttrId: 2669, operation: 6,
                            skillTypeId: nil),
                ModifierRow(domain: "shipID", function_: "LocationGroupModifier", groupId: 771,
                            modifiedAttrId: 50, modifyingAttrId: 2669, operation: 6,
                            skillTypeId: nil),
            ],
        ]

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [
                tenguOffensiveSubsystem: subsystem,
                heavyAssaultLauncher: launcher,
            ],
            modules: [
                FittedModuleInput(flag: "SubSystemSlot2", typeId: tenguOffensiveSubsystem, state: .online),
                FittedModuleInput(
                    flag: "HiSlot0",
                    typeId: heavyAssaultLauncher,
                    state: .active,
                    chargeAttrs: [117: 100],
                    chargeRequiredSkillIds: [heavyAssaultMissiles]
                ),
            ],
            characterSkills: [caldariOffensiveSystems: 5, heavyAssaultMissiles: 5],
            skillProfiles: [caldariOffensiveSystems: skill],
            effectModifiers: modifiers
        )

        #expect(abs(stats.pgUsed - 84.75) < 0.001)
        #expect(abs(stats.cpuUsed - 37.5) < 0.001)
        #expect(abs(stats.missileDPS - 31.25) < 0.001)
    }

    @Test func subsystemRateOfFireBonusDoesNotStackPenaltyWithDamageMods() {
        let heavyAssaultMissiles = 25719
        let tenguOffensiveSubsystem = 45_601
        let heavyAssaultLauncher = 25_715
        let ballisticControl = 15_681
        let ship = TypeProfile(
            attrs: [
                263: 1_000,
                479: 1_000_000,
            ],
            effectIds: []
        )
        let subsystem = TypeProfile(
            attrs: [1444: -25],
            effectIds: [3772, 4122]
        )
        let launcher = TypeProfile(
            attrs: [51: 10_000],
            effectIds: [],
            groupId: 771,
            requiredSkillIds: [heavyAssaultMissiles]
        )
        let damageMod = TypeProfile(
            attrs: [204: 0.9],
            effectIds: [889]
        )
        let modifiers: [Int: [ModifierRow]] = [
            4122: [
                ModifierRow(domain: "shipID", function_: "LocationGroupModifier", groupId: 771,
                            modifiedAttrId: 51, modifyingAttrId: 1444, operation: 6,
                            skillTypeId: nil),
            ],
            889: [
                ModifierRow(domain: "shipID", function_: "LocationRequiredSkillModifier", groupId: nil,
                            modifiedAttrId: 51, modifyingAttrId: 204, operation: 4,
                            skillTypeId: heavyAssaultMissiles),
            ],
        ]

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [
                tenguOffensiveSubsystem: subsystem,
                heavyAssaultLauncher: launcher,
                ballisticControl: damageMod,
            ],
            modules: [
                FittedModuleInput(flag: "SubSystemSlot2", typeId: tenguOffensiveSubsystem, state: .online),
                FittedModuleInput(
                    flag: "HiSlot0",
                    typeId: heavyAssaultLauncher,
                    state: .active,
                    chargeAttrs: [117: 100],
                    chargeRequiredSkillIds: [heavyAssaultMissiles]
                ),
                FittedModuleInput(flag: "LowSlot0", typeId: ballisticControl, state: .online),
            ],
            effectModifiers: modifiers
        )

        #expect(abs(stats.missileDPS - (100 / 6.75)) < 0.001)
    }

    @Test func postDivOperationDividesTargetAttributeBySourceValue() {
        let ship = TypeProfile(
            attrs: [
                37: 100,
                263: 1_000,
                479: 1_000_000,
            ],
            effectIds: []
        )
        let modeModule = TypeProfile(
            attrs: [2003: 0.5],
            effectIds: [6017]
        )
        let modifiers: [Int: [ModifierRow]] = [
            6017: [
                ModifierRow(domain: "shipID", function_: "ItemModifier", groupId: nil,
                            modifiedAttrId: 37, modifyingAttrId: 2003, operation: 5,
                            skillTypeId: nil),
            ],
        ]

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [34_216: modeModule],
            modules: [FittedModuleInput(flag: "ModeSlot0", typeId: 34_216, state: .online)],
            effectModifiers: modifiers
        )

        #expect(abs(stats.maxVelocity - 200) < 0.001)
    }

    @Test func modAddIsAppliedBeforePostPercentSkillBonuses() {
        let engineering = 3_411
        let ship = TypeProfile(
            attrs: [
                11: 420,
                263: 1_000,
                479: 1_000_000,
            ],
            effectIds: []
        )
        let reactorModule = TypeProfile(
            attrs: [9001: 190],
            effectIds: [90_010]
        )
        let skill = TypeProfile(
            attrs: [9002: 25],
            effectIds: [90_011]
        )
        let modifiers: [Int: [ModifierRow]] = [
            90_010: [
                ModifierRow(domain: "shipID", function_: "ItemModifier", groupId: nil,
                            modifiedAttrId: 11, modifyingAttrId: 9001, operation: 2,
                            skillTypeId: nil),
            ],
            90_011: [
                ModifierRow(domain: "shipID", function_: "ItemModifier", groupId: nil,
                            modifiedAttrId: 11, modifyingAttrId: 9002, operation: 6,
                            skillTypeId: nil),
            ],
        ]

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [90_012: reactorModule],
            modules: [FittedModuleInput(flag: "LowSlot0", typeId: 90_012, state: .online)],
            characterSkills: [engineering: 5],
            skillProfiles: [engineering: skill],
            effectModifiers: modifiers
        )

        #expect(abs(stats.pgTotal - 762.5) < 0.001)
    }

    @Test func assignmentOperationsSetShipAttributeAtExpectedPhase() {
        let ship = TypeProfile(
            attrs: [
                37: 100,
                263: 1_000,
                479: 1_000_000,
            ],
            effectIds: []
        )
        let module = TypeProfile(
            attrs: [
                9001: 120,
                9002: 450,
            ],
            effectIds: [90001, 90002]
        )
        let modifiers: [Int: [ModifierRow]] = [
            90001: [
                ModifierRow(domain: "shipID", function_: "ItemModifier", groupId: nil,
                            modifiedAttrId: 37, modifyingAttrId: 9001, operation: -1,
                            skillTypeId: nil),
                ModifierRow(domain: "shipID", function_: "ItemModifier", groupId: nil,
                            modifiedAttrId: 37, modifyingAttrId: 9001, operation: 6,
                            skillTypeId: nil),
            ],
            90002: [
                ModifierRow(domain: "shipID", function_: "ItemModifier", groupId: nil,
                            modifiedAttrId: 37, modifyingAttrId: 9002, operation: 7,
                            skillTypeId: nil),
            ],
        ]

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [90_001: module],
            modules: [FittedModuleInput(flag: "LowSlot0", typeId: 90_001, state: .online)],
            effectModifiers: modifiers
        )

        #expect(abs(stats.maxVelocity - 450) < 0.001)
    }

    @Test func chargeItemModifiersAreAppliedBeforeMissileDamageCalculation() {
        let ship = TypeProfile(
            attrs: [
                263: 1_000,
                479: 1_000_000,
            ],
            effectIds: []
        )
        let launcher = TypeProfile(
            attrs: [51: 10_000],
            effectIds: []
        )
        let charge = TypeProfile(
            attrs: [
                117: 100,
                9001: 50,
            ],
            effectIds: [91001]
        )
        let modifiers: [Int: [ModifierRow]] = [
            91001: [
                ModifierRow(domain: "itemID", function_: "ItemModifier", groupId: nil,
                            modifiedAttrId: 117, modifyingAttrId: 9001, operation: 6,
                            skillTypeId: nil),
            ],
        ]

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [90_100: launcher],
            modules: [
                FittedModuleInput(
                    flag: "HiSlot0",
                    typeId: 90_100,
                    state: .active,
                    chargeTypeId: 90_101,
                    chargeAttrs: charge.attrs,
                    chargeProfile: charge
                ),
            ],
            effectModifiers: modifiers
        )

        #expect(abs(stats.missileDPS - 15) < 0.001)
    }

    @Test func chargeOtherIdModifiersAreAppliedToHostModuleAttributes() {
        let ship = TypeProfile(
            attrs: [
                263: 1_000,
                479: 1_000_000,
            ],
            effectIds: []
        )
        let launcher = TypeProfile(
            attrs: [51: 10_000],
            effectIds: []
        )
        let charge = TypeProfile(
            attrs: [
                117: 100,
                9001: 0.5,
            ],
            effectIds: [92001]
        )
        let modifiers: [Int: [ModifierRow]] = [
            92001: [
                ModifierRow(domain: "otherID", function_: "ItemModifier", groupId: nil,
                            modifiedAttrId: 51, modifyingAttrId: 9001, operation: 4,
                            skillTypeId: nil),
            ],
        ]

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [90_200: launcher],
            modules: [
                FittedModuleInput(
                    flag: "HiSlot0",
                    typeId: 90_200,
                    state: .active,
                    chargeTypeId: 90_201,
                    chargeAttrs: charge.attrs,
                    chargeProfile: charge
                ),
            ],
            effectModifiers: modifiers
        )

        #expect(abs(stats.missileDPS - 20) < 0.001)
    }

    @Test func turretDamageModsUseStackingPenalty() {
        let turretGroup = 53
        let ship = TypeProfile(
            attrs: [
                263: 1_000,
                479: 1_000_000,
            ],
            effectIds: []
        )
        let turret = TypeProfile(
            attrs: [
                51: 10_000,
                64: 1,
                117: 100,
            ],
            effectIds: [],
            groupId: turretGroup
        )
        let damageMod = TypeProfile(
            attrs: [9001: 10],
            effectIds: [90_020]
        )
        let modifiers: [Int: [ModifierRow]] = [
            90_020: [
                ModifierRow(domain: "shipID", function_: "LocationGroupModifier", groupId: turretGroup,
                            modifiedAttrId: 64, modifyingAttrId: 9001, operation: 6,
                            skillTypeId: nil),
            ],
        ]

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [
                90_021: turret,
                90_022: damageMod,
                90_023: damageMod,
            ],
            modules: [
                FittedModuleInput(flag: "HiSlot0", typeId: 90_021, state: .active),
                FittedModuleInput(flag: "LowSlot0", typeId: 90_022, state: .online),
                FittedModuleInput(flag: "LowSlot1", typeId: 90_023, state: .online),
            ],
            effectModifiers: modifiers
        )

        let secondPenalty = exp(-pow(1.0 / 2.67, 2))
        let expectedDPS = 10 * 1.1 * (1 + 0.1 * secondPenalty)
        #expect(abs(stats.turretDPS - expectedDPS) < 0.001)
    }

    @Test func hullLocationRequiredSkillModifiersAffectModuleFittingCost() {
        let astrometrics = 3412
        let tengu = TypeProfile(
            attrs: [
                1989: -99,
                263: 1_000,
                479: 1_000_000,
            ],
            effectIds: [6009]
        )
        let probeLauncher = TypeProfile(
            attrs: [50: 15],
            effectIds: [],
            requiredSkillIds: [astrometrics]
        )
        let modifiers: [Int: [ModifierRow]] = [
            6009: [
                ModifierRow(domain: "shipID", function_: "LocationRequiredSkillModifier", groupId: nil,
                            modifiedAttrId: 50, modifyingAttrId: 1989, operation: 6,
                            skillTypeId: astrometrics),
            ],
        ]

        let stats = DogmaEngine.calculate(
            shipProfile: tengu,
            moduleProfiles: [17_938: probeLauncher],
            modules: [FittedModuleInput(flag: "HiSlot6", typeId: 17_938, state: .online)],
            effectModifiers: modifiers
        )

        #expect(abs(stats.cpuUsed - 0.15) < 0.001)
    }

    @Test func legacyCpuNeedSkillEffectAffectsModulesRequiringThatSkill() {
        let weaponUpgrades = 3318
        let ballisticControl = 15_681
        let ship = TypeProfile(
            attrs: [
                263: 1_000,
                479: 1_000_000,
            ],
            effectIds: []
        )
        let module = TypeProfile(
            attrs: [50: 24],
            effectIds: [],
            requiredSkillIds: [weaponUpgrades]
        )
        let skill = TypeProfile(
            attrs: [280: 0, 310: -5],
            effectIds: [211, 672]
        )
        let modifiers: [Int: [ModifierRow]] = [
            211: [
                ModifierRow(domain: "itemID", function_: "ItemModifier", groupId: nil,
                            modifiedAttrId: 310, modifyingAttrId: 280, operation: 0,
                            skillTypeId: nil),
            ],
            672: [
                ModifierRow(domain: "itemID", function_: "ItemModifier", groupId: nil,
                            modifiedAttrId: 50, modifyingAttrId: 280, operation: 0,
                            skillTypeId: nil),
            ],
        ]

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [ballisticControl: module],
            modules: [FittedModuleInput(flag: "LowSlot0", typeId: ballisticControl, state: .online)],
            characterSkills: [weaponUpgrades: 5],
            skillProfiles: [weaponUpgrades: skill],
            effectModifiers: modifiers
        )

        #expect(abs(stats.cpuUsed - 18) < 0.001)
    }

    @Test func postMulLocationRequiredSkillModifierAffectsModuleFittingCost() {
        let cloaking = 11_579
        let cloak = 11_319
        let ship = TypeProfile(
            attrs: [
                263: 1_000,
                479: 1_000_000,
            ],
            effectIds: []
        )
        let module = TypeProfile(
            attrs: [50: 100],
            effectIds: [],
            requiredSkillIds: [cloaking]
        )
        let skill = TypeProfile(
            attrs: [649: 0.5],
            effectIds: [896]
        )
        let modifiers: [Int: [ModifierRow]] = [
            896: [
                ModifierRow(domain: "shipID", function_: "LocationRequiredSkillModifier", groupId: nil,
                            modifiedAttrId: 50, modifyingAttrId: 649, operation: 4,
                            skillTypeId: cloaking),
            ],
        ]

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [cloak: module],
            modules: [FittedModuleInput(flag: "HiSlot0", typeId: cloak, state: .online)],
            characterSkills: [cloaking: 1],
            skillProfiles: [cloaking: skill],
            effectModifiers: modifiers
        )

        #expect(abs(stats.cpuUsed - 50) < 0.001)
    }

    @Test func moduleItemModifiersAffectOwnFittingCost() {
        let moduleTypeId = 90_300
        let ship = TypeProfile(
            attrs: [
                263: 1_000,
                479: 1_000_000,
            ],
            effectIds: []
        )
        let module = TypeProfile(
            attrs: [
                50: 20,
                1870: 5,
            ],
            effectIds: [5261]
        )
        let modifiers: [Int: [ModifierRow]] = [
            5261: [
                ModifierRow(domain: "itemID", function_: "ItemModifier", groupId: nil,
                            modifiedAttrId: 50, modifyingAttrId: 1870, operation: 2,
                            skillTypeId: nil),
            ],
        ]

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [moduleTypeId: module],
            modules: [FittedModuleInput(flag: "HiSlot0", typeId: moduleTypeId, state: .online)],
            effectModifiers: modifiers
        )

        #expect(abs(stats.cpuUsed - 25) < 0.001)
    }

    @Test func locationModifierAffectsAllModuleFittingCosts() {
        let ship = TypeProfile(
            attrs: [
                202: 0.8,
                263: 1_000,
                479: 1_000_000,
            ],
            effectIds: [87]
        )
        let module = TypeProfile(
            attrs: [50: 100],
            effectIds: []
        )
        let modifiers: [Int: [ModifierRow]] = [
            87: [
                ModifierRow(domain: "shipID", function_: "LocationModifier", groupId: nil,
                            modifiedAttrId: 50, modifyingAttrId: 202, operation: 4,
                            skillTypeId: nil),
            ],
        ]

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [90_400: module],
            modules: [FittedModuleInput(flag: "MedSlot0", typeId: 90_400, state: .online)],
            effectModifiers: modifiers
        )

        #expect(abs(stats.cpuUsed - 80) < 0.001)
    }

    @Test func ownerRequiredChargeDamageBonusDoesNotLeakAcrossMissileTypes() {
        let heavyMissiles = 3324
        let heavyAssaultMissiles = 25_719
        let heavyLauncher = 90_500
        let hamLauncher = 90_501
        let ship = TypeProfile(
            attrs: [
                263: 1_000,
                479: 1_000_000,
            ],
            effectIds: []
        )
        let launcher = TypeProfile(
            attrs: [51: 10_000],
            effectIds: []
        )
        let heavyMissileSkill = TypeProfile(
            attrs: [9001: 50],
            effectIds: [90_502]
        )
        let modifiers: [Int: [ModifierRow]] = [
            90_502: [
                ModifierRow(domain: "charID", function_: "OwnerRequiredSkillModifier", groupId: nil,
                            modifiedAttrId: 117, modifyingAttrId: 9001, operation: 6,
                            skillTypeId: heavyMissiles),
            ],
        ]

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [
                heavyLauncher: launcher,
                hamLauncher: launcher,
            ],
            modules: [
                FittedModuleInput(
                    flag: "HiSlot0",
                    typeId: heavyLauncher,
                    state: .active,
                    chargeAttrs: [117: 100],
                    chargeRequiredSkillIds: [heavyMissiles]
                ),
                FittedModuleInput(
                    flag: "HiSlot1",
                    typeId: hamLauncher,
                    state: .active,
                    chargeAttrs: [117: 100],
                    chargeRequiredSkillIds: [heavyAssaultMissiles]
                ),
            ],
            characterSkills: [
                heavyMissiles: 5,
                heavyAssaultMissiles: 5,
            ],
            skillProfiles: [
                heavyMissiles: heavyMissileSkill,
            ],
            effectModifiers: modifiers
        )

        #expect(abs(stats.missileDPS - 25) < 0.001)
    }

    @Test func structureResonanceAttributesContributeToHullResistsAndEHP() {
        let ship = TypeProfile(
            attrs: [
                9: 1_000,
                109: 0.67,
                110: 0.67,
                111: 0.67,
                113: 0.67,
                263: 0,
                265: 0,
                479: 1_000_000,
            ],
            effectIds: []
        )

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [:],
            modules: []
        )

        #expect(abs(stats.hullEMRes - 33) < 0.001)
        #expect(abs(stats.hullExpRes - 33) < 0.001)
        #expect(abs(stats.hullKinRes - 33) < 0.001)
        #expect(abs(stats.hullThermRes - 33) < 0.001)
        #expect(abs(stats.totalEHP - (1_000 / 0.67)) < 0.001)
    }

    @Test func missileReloadDPSAccountsForMagazineAndReloadTime() {
        let ship = TypeProfile(
            attrs: [
                263: 1_000,
                479: 1_000_000,
            ],
            effectIds: []
        )
        let launcher = TypeProfile(
            attrs: [
                51: 1_000,
                56: 1,
                1795: 10_000,
            ],
            effectIds: []
        )

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [90_600: launcher],
            modules: [
                FittedModuleInput(
                    flag: "HiSlot0",
                    typeId: 90_600,
                    state: .active,
                    chargeAttrs: [117: 100],
                    moduleCapacity: 0.30,
                    chargeVolume: 0.10
                ),
            ]
        )

        #expect(abs(stats.missileDPS - 100) < 0.001)
        #expect(abs(stats.missileReloadDPS - 23.076923) < 0.001)
    }

    @Test func shieldRiggingReducesShieldRigSignatureDrawback() {
        let shieldRigging = 26_261
        let shieldRig = 90_700
        let ship = TypeProfile(
            attrs: [
                263: 1_000,
                479: 1_000_000,
                552: 100,
            ],
            effectIds: []
        )
        let rig = TypeProfile(
            attrs: [
                1138: 10,
            ],
            effectIds: [2716],
            groupId: 774
        )
        let skill = TypeProfile(
            attrs: [
                1139: -10,
            ],
            effectIds: []
        )

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [
                shieldRig: rig,
            ],
            modules: [
                FittedModuleInput(flag: "RigSlot0", typeId: shieldRig, state: .online),
            ],
            characterSkills: [
                shieldRigging: 5,
            ],
            skillProfiles: [
                shieldRigging: skill,
            ]
        )

        #expect(abs(stats.signatureRadius - 105) < 0.001)
    }

    @Test func launcherRiggingReducesLauncherRigCpuDrawback() {
        let launcherRigging = 26_260
        let bayLoadingRig = 90_710
        let hamLauncher = 90_711
        let ship = TypeProfile(
            attrs: [
                263: 1_000,
                479: 1_000_000,
            ],
            effectIds: []
        )
        let rig = TypeProfile(
            attrs: [
                1138: 10,
            ],
            effectIds: [2714],
            groupId: 779
        )
        let launcher = TypeProfile(
            attrs: [
                50: 100,
            ],
            effectIds: [],
            groupId: 771
        )
        let skill = TypeProfile(
            attrs: [
                1139: -10,
            ],
            effectIds: []
        )

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [
                bayLoadingRig: rig,
                hamLauncher: launcher,
            ],
            modules: [
                FittedModuleInput(flag: "RigSlot0", typeId: bayLoadingRig, state: .online),
                FittedModuleInput(flag: "HiSlot0", typeId: hamLauncher, state: .online),
            ],
            characterSkills: [
                launcherRigging: 5,
            ],
            skillProfiles: [
                launcherRigging: skill,
            ]
        )

        #expect(abs(stats.cpuUsed - 105) < 0.001)
    }

    @Test func implantItemModifiersAffectShipAttributes() {
        let implant = 90_720
        let ship = TypeProfile(
            attrs: [
                263: 1_000,
                479: 1_000_000,
            ],
            effectIds: []
        )
        let shieldHpImplant = TypeProfile(
            attrs: [
                337: 5,
            ],
            effectIds: [446]
        )
        let modifiers: [Int: [ModifierRow]] = [
            446: [
                ModifierRow(domain: "shipID", function_: "ItemModifier", groupId: nil,
                            modifiedAttrId: 263, modifyingAttrId: 337, operation: 6,
                            skillTypeId: nil),
            ],
        ]

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [:],
            modules: [],
            implantProfiles: [
                implant: shieldHpImplant,
            ],
            effectModifiers: modifiers
        )

        #expect(abs(stats.shieldHP - 1_050) < 0.001)
    }

    @Test func implantLocationRequiredModifiersAffectModuleFittingCost() {
        let missileLauncherOperation = 3_319
        let implant = 90_730
        let launcher = 90_731
        let ship = TypeProfile(
            attrs: [
                263: 1_000,
                479: 1_000_000,
            ],
            effectIds: []
        )
        let cpuImplant = TypeProfile(
            attrs: [
                310: -5,
            ],
            effectIds: [677]
        )
        let hamLauncher = TypeProfile(
            attrs: [
                50: 100,
            ],
            effectIds: [],
            groupId: 771,
            requiredSkillIds: [missileLauncherOperation]
        )
        let modifiers: [Int: [ModifierRow]] = [
            677: [
                ModifierRow(domain: "shipID", function_: "LocationRequiredSkillModifier", groupId: nil,
                            modifiedAttrId: 50, modifyingAttrId: 310, operation: 6,
                            skillTypeId: missileLauncherOperation),
            ],
        ]

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [
                launcher: hamLauncher,
            ],
            modules: [
                FittedModuleInput(flag: "HiSlot0", typeId: launcher, state: .online),
            ],
            implantProfiles: [
                implant: cpuImplant,
            ],
            effectModifiers: modifiers
        )

        #expect(abs(stats.cpuUsed - 95) < 0.001)
    }

    @Test func implantSetBonusScalesImplantShipModifierAttributes() {
        let snakeAlpha = 90_740
        let snakeOmega = 90_741
        let ship = TypeProfile(
            attrs: [
                37: 100,
                263: 1_000,
                479: 1_000_000,
            ],
            effectIds: []
        )
        let alpha = TypeProfile(
            attrs: [
                315: 10,
            ],
            effectIds: [394],
            groupId: 300
        )
        let omega = TypeProfile(
            attrs: [
                802: 2,
            ],
            effectIds: [1261],
            groupId: 300
        )
        let modifiers: [Int: [ModifierRow]] = [
            394: [
                ModifierRow(domain: "shipID", function_: "ItemModifier", groupId: nil,
                            modifiedAttrId: 37, modifyingAttrId: 315, operation: 6,
                            skillTypeId: nil),
            ],
            1261: [
                ModifierRow(domain: "charID", function_: "LocationGroupModifier", groupId: 300,
                            modifiedAttrId: 315, modifyingAttrId: 802, operation: 0,
                            skillTypeId: nil),
            ],
        ]

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [:],
            modules: [],
            implantProfiles: [
                snakeAlpha: alpha,
                snakeOmega: omega,
            ],
            effectModifiers: modifiers
        )

        #expect(abs(stats.maxVelocity - 120) < 0.001)
    }

    @Test func implantSetBonusScalesImplantLocationRequiredModifierAttributes() {
        let missileLauncherOperation = 3_319
        let implantAlpha = 90_750
        let implantOmega = 90_751
        let launcher = 90_752
        let ship = TypeProfile(
            attrs: [
                263: 1_000,
                479: 1_000_000,
            ],
            effectIds: []
        )
        let alpha = TypeProfile(
            attrs: [
                310: -5,
            ],
            effectIds: [677],
            groupId: 300
        )
        let omega = TypeProfile(
            attrs: [
                9001: 2,
            ],
            effectIds: [90_753],
            groupId: 300
        )
        let hamLauncher = TypeProfile(
            attrs: [
                50: 100,
            ],
            effectIds: [],
            groupId: 771,
            requiredSkillIds: [missileLauncherOperation]
        )
        let modifiers: [Int: [ModifierRow]] = [
            677: [
                ModifierRow(domain: "shipID", function_: "LocationRequiredSkillModifier", groupId: nil,
                            modifiedAttrId: 50, modifyingAttrId: 310, operation: 6,
                            skillTypeId: missileLauncherOperation),
            ],
            90_753: [
                ModifierRow(domain: "charID", function_: "LocationGroupModifier", groupId: 300,
                            modifiedAttrId: 310, modifyingAttrId: 9001, operation: 0,
                            skillTypeId: nil),
            ],
        ]

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [
                launcher: hamLauncher,
            ],
            modules: [
                FittedModuleInput(flag: "HiSlot0", typeId: launcher, state: .online),
            ],
            implantProfiles: [
                implantAlpha: alpha,
                implantOmega: omega,
            ],
            effectModifiers: modifiers
        )

        #expect(abs(stats.cpuUsed - 90) < 0.001)
    }

    @Test func shipSkillScaledHullItemModifiersAffectShipAttributes() {
        let caldariBattlecruiser = 33_096
        let ship = TypeProfile(
            attrs: [
                263: 1_000,
                271: 1.0,
                479: 1_000_000,
                745: -4,
            ],
            effectIds: [5_335]
        )
        let skill = TypeProfile(
            attrs: [280: 0],
            effectIds: [5_287]
        )
        let modifiers: [Int: [ModifierRow]] = [
            5_287: [
                ModifierRow(domain: "shipID", function_: "ItemModifier", groupId: nil,
                            modifiedAttrId: 745, modifyingAttrId: 280, operation: 0,
                            skillTypeId: nil),
            ],
            5_335: [
                ModifierRow(domain: "shipID", function_: "ItemModifier", groupId: nil,
                            modifiedAttrId: 271, modifyingAttrId: 745, operation: 6,
                            skillTypeId: nil),
            ],
        ]

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [:],
            modules: [],
            characterSkills: [caldariBattlecruiser: 5],
            skillProfiles: [caldariBattlecruiser: skill],
            effectModifiers: modifiers
        )

        #expect(abs(stats.shieldEMRes - 20) < 0.001)
    }

    @Test func rapidLaunchHardwiringDoesNotStackWithBallisticControls() {
        let missileLauncherOperation = 3_319
        let launcher = 90_760
        let ballisticControl = 90_761
        let implant = 90_762
        let ship = TypeProfile(
            attrs: [
                263: 1_000,
                479: 1_000_000,
            ],
            effectIds: []
        )
        let launcherProfile = TypeProfile(
            attrs: [
                51: 1_000,
            ],
            effectIds: [],
            groupId: 771,
            requiredSkillIds: [missileLauncherOperation]
        )
        let bcs = TypeProfile(
            attrs: [
                204: 0.9,
            ],
            effectIds: [889]
        )
        let rapidLaunchImplant = TypeProfile(
            attrs: [
                293: -5,
            ],
            effectIds: [1763]
        )
        let modifiers: [Int: [ModifierRow]] = [
            889: [
                ModifierRow(domain: "shipID", function_: "LocationRequiredSkillModifier", groupId: nil,
                            modifiedAttrId: 51, modifyingAttrId: 204, operation: 4,
                            skillTypeId: missileLauncherOperation),
            ],
            1763: [
                ModifierRow(domain: "shipID", function_: "LocationRequiredSkillModifier", groupId: nil,
                            modifiedAttrId: 51, modifyingAttrId: 293, operation: 6,
                            skillTypeId: missileLauncherOperation),
            ],
        ]

        let secondStackPenalty = exp(-pow(1.0 / 2.67, 2))
        let stackedBCS = 0.9 * (1.0 + (0.9 - 1.0) * secondStackPenalty)
        let expectedCycleSeconds = 1.0 * stackedBCS * 0.95
        let expectedDPS = 100.0 / expectedCycleSeconds

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [
                launcher: launcherProfile,
                ballisticControl: bcs,
            ],
            modules: [
                FittedModuleInput(flag: "HiSlot0", typeId: launcher, state: .active,
                                  chargeAttrs: [117: 100],
                                  chargeRequiredSkillIds: [missileLauncherOperation]),
                FittedModuleInput(flag: "LoSlot0", typeId: ballisticControl, state: .online),
                FittedModuleInput(flag: "LoSlot1", typeId: ballisticControl, state: .online),
            ],
            implantProfiles: [
                implant: rapidLaunchImplant,
            ],
            effectModifiers: modifiers
        )

        #expect(abs(stats.missileDPS - expectedDPS) < 0.001)
    }

    @Test func hullResistancesUseShipHullResonanceAttributes() {
        let ship = TypeProfile(
            attrs: [
                9: 1_000,
                263: 1_000,
                479: 1_000_000,
                974: 0.67,
                975: 0.50,
                976: 0.40,
                977: 0.30,
            ],
            effectIds: []
        )

        let stats = DogmaEngine.calculate(shipProfile: ship, moduleProfiles: [:], modules: [])

        #expect(abs(stats.hullEMRes - 33) < 0.001)
        #expect(abs(stats.hullExpRes - 50) < 0.001)
        #expect(abs(stats.hullKinRes - 60) < 0.001)
        #expect(abs(stats.hullThermRes - 70) < 0.001)
    }

    @Test func shieldCompensationSkillScalesPassiveShieldAmplifierResistance() {
        let emShieldCompensation = 12_365
        let emShieldAmplifier = 90_770
        let ship = TypeProfile(
            attrs: [
                263: 1_000,
                271: 1.0,
                479: 1_000_000,
            ],
            effectIds: []
        )
        let skill = TypeProfile(
            attrs: [
                280: 0,
                958: 5,
            ],
            effectIds: [1897, 2053]
        )
        let amplifier = TypeProfile(
            attrs: [
                984: -40,
            ],
            effectIds: [2052],
            groupId: 295
        )
        let modifiers: [Int: [ModifierRow]] = [
            1897: [
                ModifierRow(domain: "itemID", function_: "ItemModifier", groupId: nil,
                            modifiedAttrId: 958, modifyingAttrId: 280, operation: 0,
                            skillTypeId: nil),
            ],
            2053: [
                ModifierRow(domain: "shipID", function_: "LocationGroupModifier", groupId: 295,
                            modifiedAttrId: 984, modifyingAttrId: 958, operation: 6,
                            skillTypeId: nil),
            ],
            2052: [
                ModifierRow(domain: "shipID", function_: "ItemModifier", groupId: nil,
                            modifiedAttrId: 271, modifyingAttrId: 984, operation: 6,
                            skillTypeId: nil),
            ],
        ]

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [
                emShieldAmplifier: amplifier,
            ],
            modules: [
                FittedModuleInput(flag: "MedSlot0", typeId: emShieldAmplifier, state: .online),
            ],
            characterSkills: [
                emShieldCompensation: 5,
            ],
            skillProfiles: [
                emShieldCompensation: skill,
            ],
            effectModifiers: modifiers
        )

        #expect(abs(stats.shieldEMRes - 50) < 0.001)
    }

    @Test func damageControlDoesNotStackPenaltyWithShieldHardeners() {
        let hardener = 90_780
        let damageControl = 90_781
        let ship = TypeProfile(
            attrs: [
                263: 1_000,
                271: 1.0,
                479: 1_000_000,
            ],
            effectIds: []
        )
        let multispectrumHardener = TypeProfile(
            attrs: [
                984: -30,
            ],
            effectIds: [5230]
        )
        let damageControlProfile = TypeProfile(
            attrs: [
                271: 0.875,
            ],
            effectIds: [2302]
        )
        let modifiers: [Int: [ModifierRow]] = [
            5230: [
                ModifierRow(domain: "shipID", function_: "ItemModifier", groupId: nil,
                            modifiedAttrId: 271, modifyingAttrId: 984, operation: 6,
                            skillTypeId: nil),
            ],
            2302: [
                ModifierRow(domain: "shipID", function_: "ItemModifier", groupId: nil,
                            modifiedAttrId: 271, modifyingAttrId: 271, operation: 0,
                            skillTypeId: nil),
            ],
        ]

        let secondStackPenalty = exp(-pow(1.0 / 2.67, 2))
        let hardenerStack = 0.7 * (1.0 + (0.7 - 1.0) * secondStackPenalty)
        let expectedResist = (1.0 - hardenerStack * 0.875) * 100.0

        let stats = DogmaEngine.calculate(
            shipProfile: ship,
            moduleProfiles: [
                hardener: multispectrumHardener,
                damageControl: damageControlProfile,
            ],
            modules: [
                FittedModuleInput(flag: "MedSlot0", typeId: hardener, state: .active),
                FittedModuleInput(flag: "MedSlot1", typeId: hardener, state: .active),
                FittedModuleInput(flag: "LoSlot0", typeId: damageControl, state: .online),
            ],
            effectModifiers: modifiers
        )

        #expect(abs(stats.shieldEMRes - expectedResist) < 0.001)
    }
}
