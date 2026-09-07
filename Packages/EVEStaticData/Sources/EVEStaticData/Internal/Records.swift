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

    enum CodingKeys: String, CodingKey {
        case id, name, description, mass, volume, capacity, published
        case groupId = "group_id"
        case marketGroupId = "market_group_id"
        case portionSize = "portion_size"
        case basePrice = "base_price"
        case metaGroupId = "meta_group_id"
    }

    func toDomain() -> ItemType {
        ItemType(
            id: id, groupId: groupId, marketGroupId: marketGroupId,
            name: name, typeDescription: description, mass: mass,
            volume: volume, capacity: capacity, portionSize: portionSize,
            basePrice: basePrice, published: published, metaGroupId: metaGroupId
        )
    }
}

// MARK: - DogmaAttribute

struct DogmaAttributeRecord: Codable, FetchableRecord, TableRecord, Sendable {
    static let databaseTableName = "dogma_attributes"
    let id: Int
    let name: String
    let displayName: String?
    let unitId: Int?
    let highIsGood: Bool
    let stackable: Bool
    let defaultValue: Double?
    let published: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, published, stackable
        case displayName = "display_name"
        case unitId = "unit_id"
        case highIsGood = "high_is_good"
        case defaultValue = "default_value"
    }

    func toDomain() -> DogmaAttribute {
        DogmaAttribute(
            id: id, name: name, displayName: displayName, unitId: unitId,
            highIsGood: highIsGood, stackable: stackable,
            defaultValue: defaultValue, published: published
        )
    }
}
