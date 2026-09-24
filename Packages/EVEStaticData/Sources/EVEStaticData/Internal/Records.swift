import GRDB
import Domain

// MARK: - Category

struct CategoryRecord: Codable, FetchableRecord, TableRecord, Sendable {
    static let databaseTableName = "categories"
    let id: Int
    let name: String
    let published: Bool

    func toDomain() -> ItemCategory {
        ItemCategory(id: id, name: name, published: published)
    }
}

// MARK: - Group

struct GroupRecord: Codable, FetchableRecord, TableRecord, Sendable {
    static let databaseTableName = "groups"
    let id: Int
    let categoryId: Int
    let name: String
    let published: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, published
        case categoryId = "category_id"
    }

    func toDomain() -> ItemGroup {
        ItemGroup(id: id, categoryId: categoryId, name: name, published: published)
    }
}

// MARK: - Market Group

struct MarketGroupRecord: Codable, FetchableRecord, TableRecord, Sendable {
    static let databaseTableName = "market_groups"
    let id: Int
    let parentId: Int?
    let name: String
    let description: String?
    let iconId: Int?
    let hasTypes: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case parentId = "parent_id"
        case iconId = "icon_id"
        case hasTypes = "has_types"
    }

    func toDomain() -> MarketGroup {
        MarketGroup(id: id, parentId: parentId, name: name, description: description, iconId: iconId, hasTypes: hasTypes)
    }
}

// MARK: - Type

struct TypeRecord: Codable, FetchableRecord, TableRecord, Sendable {
    static let databaseTableName = "types"
    let id: Int
    let groupId: Int
    let marketGroupId: Int?
    let name: String
    let description: String?
    let mass: Double?
    let volume: Double?
    let capacity: Double?
    let portionSize: Int?
    let basePrice: Double?
    let published: Bool
    let metaGroupId: Int?
    let variationParentId: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, description, mass, volume, capacity, published
        case groupId = "group_id"
        case marketGroupId = "market_group_id"
        case portionSize = "portion_size"
        case basePrice = "base_price"
        case metaGroupId = "meta_group_id"
        case variationParentId = "variation_parent_id"
    }

    func toDomain() -> ItemType {
        ItemType(
            id: id, groupId: groupId, marketGroupId: marketGroupId,
            name: name, typeDescription: description, mass: mass,
            volume: volume, capacity: capacity, portionSize: portionSize,
            basePrice: basePrice, published: published, metaGroupId: metaGroupId,
            variationParentId: variationParentId
        )
    }
}

// MARK: - Type Traits

struct TypeTraitRecord: Codable, FetchableRecord, TableRecord, Sendable {
    static let databaseTableName = "type_traits"
    let typeId: Int
    let skillId: Int?
    let bonus: Double?
    let unitId: Int?
    let text: String
    let sort: Int

    enum CodingKeys: String, CodingKey {
        case typeId = "type_id"
        case skillId = "skill_id"
        case bonus
        case unitId = "unit_id"
        case text
        case sort
    }

    func toDomain() -> TypeTrait {
        TypeTrait(typeId: typeId, skillId: skillId, bonus: bonus, unitId: unitId, text: text, sort: sort)
    }
}

// MARK: - DogmaAttribute

struct DogmaAttributeRecord: Codable, FetchableRecord, TableRecord, Sendable {
    static let databaseTableName = "dogma_attributes"
    let id: Int
    let name: String
    let displayName: String?
    let unitId: Int?
    let iconId: Int?
    let highIsGood: Bool
    let stackable: Bool
    let defaultValue: Double?
    let published: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, published, stackable
        case displayName = "display_name"
        case unitId = "unit_id"
        case iconId = "icon_id"
        case highIsGood = "high_is_good"
        case defaultValue = "default_value"
    }

    func toDomain() -> DogmaAttribute {
        DogmaAttribute(
            id: id, name: name, displayName: displayName, unitId: unitId, iconId: iconId,
            highIsGood: highIsGood, stackable: stackable,
            defaultValue: defaultValue, published: published
        )
    }
}
