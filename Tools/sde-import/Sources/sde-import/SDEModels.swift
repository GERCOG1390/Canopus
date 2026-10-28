import Foundation

// Codable structs matching CCP's official SDE YAML export (fsd/*.yaml, downloaded
// from https://eve-static-data-export.s3-eu-west-1.amazonaws.com/tranquility/sde.zip).
//
// Every fsd/*.yaml file is a single top-level YAML mapping keyed by the entity's
// numeric ID — the ID is never repeated as a field inside the entity itself
// (except a few files that redundantly echo it, which we ignore). Callers decode
// each file as [String: T] and convert the string key to Int themselves.
//
// Files (all under <input>/fsd/):
//   categories.yaml, groups.yaml, types.yaml
//   dogmaAttributes.yaml, dogmaEffects.yaml, typeDogma.yaml
//   marketGroups.yaml

struct LocalizedString: Decodable {
    let en: String?
    let de: String?
    let fr: String?
    let ja: String?
    let ko: String?
    let ru: String?
    let zh: String?
    let es: String?
    let it: String?

    var english: String { en ?? "" }
}

// MARK: - Categories
// 2:
//   name: {en: Celestial, ...}
//   published: true

struct SDECategory: Decodable {
    let name: LocalizedString?
    let published: Bool?
}

// MARK: - Groups
// 18:
//   categoryID: 4
//   name: {en: Mineral, ...}
//   published: true

struct SDEGroup: Decodable {
    let categoryID: Int?
    let name: LocalizedString?
    let published: Bool?
}

// MARK: - Types
//
// types.yaml and typeDogma.yaml are ~150MB/~26MB with tens of thousands of
// entries — too large for Yams' Codable path to decode in reasonable time
// (see SDEImporter.importTypes/importTypeDogma). Those two are parsed via a
// direct Node-tree walk instead, so no Decodable structs are needed for them.

struct SDETypeBonusRecord {
    let typeId: Int
    let skillId: Int?
    let bonus: Double?
    let unitId: Int?
    let text: String
    let sort: Int
}

// MARK: - Market Groups
// 4:
//   parentGroupID: ...
//   nameID: {en: Ships, ...}
//   descriptionID: {...}
//   hasTypes: false
//   iconID: 1443
//
// Note the "ID" suffix on the localized fields here — unlike categories/groups/types,
// which use plain "name"/"description".

struct SDEMarketGroup: Decodable {
    let parentGroupID: Int?
    let nameID: LocalizedString?
    let descriptionID: LocalizedString?
    let iconID: Int?
    let hasTypes: Bool?
}

// MARK: - Dogma Attributes
// 3:
//   name: damage
//   displayNameID: {en: Item Damage, ...}
//   highIsGood: false
//   stackable: true
//   published: true
//   unitID: 113

struct SDEDogmaAttribute: Decodable {
    let name: String?
    let displayNameID: LocalizedString?
    let unitID: Int?
    let iconID: Int?
    let highIsGood: Bool?
    let stackable: Bool?
    let defaultValue: Double?
    let published: Bool?
}

// MARK: - Dogma Effects
// 4:
//   name: shieldBoosting          (effectName in the legacy export)
//   effectCategoryID: 1           (effectCategory in the legacy export)
//   isOffensive: false
//   isAssistance: false
//   durationAttributeID: 73
//   modifierInfo: [{domain: shipID, func: ItemModifier, ...}]

struct SDEModifierInfo: Decodable {
    let domain: String?
    let `func`: String?
    let groupID: Int?
    let modifiedAttributeID: Int?
    let modifyingAttributeID: Int?
    let operation: Int?
    let skillTypeID: Int?
}

struct SDEDogmaEffect: Decodable {
    let effectName: String?
    let effectCategory: Int?
    let isOffensive: Bool?
    let isAssistance: Bool?
    let durationAttributeID: Int?
    let dischargeAttributeID: Int?
    let rangeAttributeID: Int?
    let falloffAttributeID: Int?
    let trackingSpeedAttributeID: Int?
    let fittingUsageChanceAttributeID: Int?
    let modifierInfo: [SDEModifierInfo]?

    private enum CodingKeys: String, CodingKey {
        case effectName, name, effectCategory, effectCategoryID, isOffensive, isAssistance, durationAttributeID,
             dischargeAttributeID, rangeAttributeID, falloffAttributeID, trackingSpeedAttributeID,
             fittingUsageChanceAttributeID, modifierInfo
    }

    /// The developers.eveonline.com SDE (2025+) renamed effectName → name and effectCategory →
    /// effectCategoryID; the legacy S3 export used the old names. Both are read.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        effectName = try c.decodeIfPresent(String.self, forKey: .name) ?? c.decodeIfPresent(String.self, forKey: .effectName)
        effectCategory = try c.decodeIfPresent(Int.self, forKey: .effectCategoryID) ?? c.decodeIfPresent(Int.self, forKey: .effectCategory)
        isOffensive = try c.decodeIfPresent(Bool.self, forKey: .isOffensive)
        isAssistance = try c.decodeIfPresent(Bool.self, forKey: .isAssistance)
        durationAttributeID = try c.decodeIfPresent(Int.self, forKey: .durationAttributeID)
        dischargeAttributeID = try c.decodeIfPresent(Int.self, forKey: .dischargeAttributeID)
        rangeAttributeID = try c.decodeIfPresent(Int.self, forKey: .rangeAttributeID)
        falloffAttributeID = try c.decodeIfPresent(Int.self, forKey: .falloffAttributeID)
        trackingSpeedAttributeID = try c.decodeIfPresent(Int.self, forKey: .trackingSpeedAttributeID)
        fittingUsageChanceAttributeID = try c.decodeIfPresent(Int.self, forKey: .fittingUsageChanceAttributeID)
        modifierInfo = try c.decodeIfPresent([SDEModifierInfo].self, forKey: .modifierInfo)
    }
}

// MARK: - Map (mapRegions / mapConstellations / mapSolarSystems / mapStargates)
// 30000001:
//   constellationID: 20000001
//   name: {en: Tanoo, ...}
//   position: {x: -8.85e+16, y: 4.23e+16, z: -4.45e+16}
//   regionID: 10000001
//   securityStatus: 0.858324
// 50000001:
//   destination: {solarSystemID: 30000778, stargateID: 50000482}
//   solarSystemID: 30000777

struct SDEMapPosition: Decodable {
    let x: Double
    let y: Double
    let z: Double
}

struct SDEMapRegion: Decodable {
    let name: LocalizedString?
}

struct SDEMapConstellation: Decodable {
    let regionID: Int
    let name: LocalizedString?
}

struct SDEMapSolarSystem: Decodable {
    let constellationID: Int
    let name: LocalizedString?
    let position: SDEMapPosition?
    let securityStatus: Double?
}

struct SDEMapStargate: Decodable {
    struct Destination: Decodable { let solarSystemID: Int }
    let solarSystemID: Int
    let destination: Destination
}
