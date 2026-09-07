import Foundation

// Codable structs matching CCP's SDE JSONL format (build 3489895+).
//
// Primary ID of every entity is stored in "_key".
// Cross-references (groupID, categoryID, etc.) use CCP's original numeric IDs.
//
// Files (all in the root of the extracted zip):
//   categories.jsonl, groups.jsonl, types.jsonl
//   dogmaAttributes.jsonl, dogmaEffects.jsonl, typeDogma.jsonl
//   marketGroups.jsonl

struct LocalizedString: Codable {
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
// {"_key": 1, "name": {"en": "Owner", ...}, "published": false}

struct SDECategory: Codable {
    let id: Int
    let name: LocalizedString?
    let published: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "_key"
        case name, published
    }
}

// MARK: - Groups
// {"_key": 18, "categoryID": 4, "name": {"en": "Mineral", ...}, "published": true}

struct SDEGroup: Codable {
    let id: Int
    let categoryID: Int?
    let name: LocalizedString?
    let published: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "_key"
        case categoryID, name, published
    }
}

// MARK: - Types
// {"_key": 34, "groupID": 18, "name": {"en": "Tritanium"}, "published": true, "mass": 0.0, ...}

struct SDEType: Codable {
    let id: Int
    let groupID: Int?
    let name: LocalizedString?
    let description: LocalizedString?
    let mass: Double?
    let volume: Double?
    let capacity: Double?
    let portionSize: Int?
    let basePrice: Double?
    let marketGroupID: Int?
    let metaGroupID: Int?
    let variationParentTypeID: Int?
    let factionID: Int?
    let raceID: Int?
    let packagedVolume: Double?
    let published: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "_key"
        case groupID, name, description, mass, volume, capacity
        case portionSize, basePrice, marketGroupID, metaGroupID
        case variationParentTypeID, factionID, raceID, packagedVolume, published
    }
}

// MARK: - Market Groups
// {"_key": 4, "name": {"en": "Ships"}, "description": {...}, "hasTypes": false, "iconID": 1443}

struct SDEMarketGroup: Codable {
    let id: Int
    let parentGroupID: Int?
    let name: LocalizedString?
    let description: LocalizedString?
    let iconID: Int?
    let hasTypes: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "_key"
        case parentGroupID, name, description, iconID, hasTypes
    }
}

// MARK: - Dogma Attributes
// {"_key": 3, "name": "damage", "displayName": {"en": "Item Damage", ...},
//  "highIsGood": false, "stackable": true, "published": true, "unitID": 113}

struct SDEDogmaAttribute: Codable {
    let id: Int
    let name: String?
    let displayName: LocalizedString?
    let unitID: Int?
    let iconID: Int?
    let highIsGood: Bool?
    let stackable: Bool?
    let defaultValue: Double?
    let published: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "_key"
        case name, displayName, unitID, iconID
        case highIsGood, stackable, defaultValue, published
    }
}

// MARK: - Dogma Effects
// {"_key": 4, "name": "shieldBoosting", "effectCategoryID": 1,
//  "isOffensive": false, "isAssistance": false, "durationAttributeID": 73,
//  "modifierInfo": [{"domain":"shipID","func":"ItemModifier",...}], ...}

struct SDEModifierInfo: Codable {
    let domain: String?
    let `func`: String?
    let groupID: Int?
    let modifiedAttributeID: Int?
    let modifyingAttributeID: Int?
    let operation: Int?
    let skillTypeID: Int?
}

struct SDEDogmaEffect: Codable {
    let id: Int
    let name: String?
    let effectCategoryID: Int?
    let isOffensive: Bool?
    let isAssistance: Bool?
    let durationAttributeID: Int?
    let dischargeAttributeID: Int?
    let rangeAttributeID: Int?
    let falloffAttributeID: Int?
    let trackingSpeedAttributeID: Int?
    let fittingUsageChanceAttributeID: Int?
    let modifierInfo: [SDEModifierInfo]?

    enum CodingKeys: String, CodingKey {
        case id = "_key"
        case name, effectCategoryID, isOffensive, isAssistance
        case durationAttributeID, dischargeAttributeID, rangeAttributeID
        case falloffAttributeID, trackingSpeedAttributeID, fittingUsageChanceAttributeID
        case modifierInfo
    }
}

// MARK: - Type Dogma
// {"_key": 18, "dogmaAttributes": [{"attributeID": 182, "value": 1.0}], "dogmaEffects": [...]}

struct SDETypeDogma: Codable {
    let id: Int
    let dogmaAttributes: [SDEDogmaAttributeValue]?
    let dogmaEffects: [SDEDogmaEffectRef]?

    enum CodingKeys: String, CodingKey {
        case id = "_key"
        case dogmaAttributes, dogmaEffects
    }
}

struct SDEDogmaAttributeValue: Codable {
    let attributeID: Int
    let value: Double
}

struct SDEDogmaEffectRef: Codable {
    let effectID: Int
    let isDefault: Bool?
}
