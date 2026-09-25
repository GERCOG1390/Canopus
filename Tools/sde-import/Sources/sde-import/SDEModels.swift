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
//   effectName: shieldBoosting
//   effectCategory: 1
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
}
