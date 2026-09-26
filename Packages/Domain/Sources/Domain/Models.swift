import Foundation

// MARK: - SDE Types

public struct ItemCategory: Identifiable, Sendable, Hashable {
    public let id: Int
    public let name: String
    public let published: Bool

    public init(id: Int, name: String, published: Bool) {
        self.id = id; self.name = name; self.published = published
    }
}

public struct ItemGroup: Identifiable, Sendable, Hashable {
    public let id: Int
    public let categoryId: Int
    public let name: String
    public let published: Bool

    public init(id: Int, categoryId: Int, name: String, published: Bool) {
        self.id = id; self.categoryId = categoryId; self.name = name; self.published = published
    }
}

public struct MarketGroup: Identifiable, Sendable, Hashable {
    public let id: Int
    public let parentId: Int?
    public let name: String
    public let description: String?
    public let iconId: Int?
    public let hasTypes: Bool

    public init(id: Int, parentId: Int?, name: String, description: String?, iconId: Int?, hasTypes: Bool) {
        self.id = id
        self.parentId = parentId
        self.name = name
        self.description = description
        self.iconId = iconId
        self.hasTypes = hasTypes
    }
}

public struct ItemType: Identifiable, Sendable, Hashable {
    public let id: Int
    public let groupId: Int
    public let marketGroupId: Int?
    public let name: String
    public let typeDescription: String?
    public let mass: Double?
    public let volume: Double?
    public let capacity: Double?
    public let portionSize: Int?
    public let basePrice: Double?
    public let published: Bool
    public let metaGroupId: Int?
    public let variationParentId: Int?

    public init(
        id: Int, groupId: Int, marketGroupId: Int?, name: String,
        typeDescription: String?, mass: Double?, volume: Double?, capacity: Double?,
        portionSize: Int?, basePrice: Double?, published: Bool, metaGroupId: Int?, variationParentId: Int?
    ) {
        self.id = id; self.groupId = groupId; self.marketGroupId = marketGroupId
        self.name = name; self.typeDescription = typeDescription; self.mass = mass
        self.volume = volume; self.capacity = capacity; self.portionSize = portionSize
        self.basePrice = basePrice; self.published = published; self.metaGroupId = metaGroupId
        self.variationParentId = variationParentId
    }
}

public struct TypeInfluence: Identifiable, Sendable, Hashable {
    public var id: Int { type.id }
    public let type: ItemType
    public let categoryName: String
    public let groupName: String
    public let modifiedAttributes: [String]

    public init(type: ItemType, categoryName: String, groupName: String, modifiedAttributes: [String]) {
        self.type = type
        self.categoryName = categoryName
        self.groupName = groupName
        self.modifiedAttributes = modifiedAttributes
    }
}

public struct SkillInfluence: Identifiable, Sendable, Hashable {
    public var id: Int { skill.id }
    public let skill: ItemType
    public let affectedGroups: [String]
    public let modifiedAttributes: [String]

    public init(skill: ItemType, affectedGroups: [String], modifiedAttributes: [String]) {
        self.skill = skill
        self.affectedGroups = affectedGroups
        self.modifiedAttributes = modifiedAttributes
    }
}

public struct TypeTrait: Identifiable, Sendable, Hashable {
    public var id: String { "\(typeId):\(skillId ?? 0):\(sort):\(text)" }
    public let typeId: Int
    public let skillId: Int?
    public let bonus: Double?
    public let unitId: Int?
    public let text: String
    public let sort: Int

    public init(typeId: Int, skillId: Int?, bonus: Double?, unitId: Int?, text: String, sort: Int) {
        self.typeId = typeId
        self.skillId = skillId
        self.bonus = bonus
        self.unitId = unitId
        self.text = text
        self.sort = sort
    }
}

public struct DogmaAttribute: Identifiable, Sendable, Hashable {
    public let id: Int
    public let name: String
    public let displayName: String?
    public let unitId: Int?
    public let iconId: Int?
    public let highIsGood: Bool
    public let stackable: Bool
    public let defaultValue: Double?
    public let published: Bool

    public init(
        id: Int, name: String, displayName: String?, unitId: Int?,
        iconId: Int? = nil, highIsGood: Bool, stackable: Bool, defaultValue: Double?, published: Bool
    ) {
        self.id = id; self.name = name; self.displayName = displayName; self.unitId = unitId; self.iconId = iconId
        self.highIsGood = highIsGood; self.stackable = stackable
        self.defaultValue = defaultValue; self.published = published
    }
}

public struct TypeAttributeDetail: Identifiable, Sendable {
    public var id: Int { attributeId }
    public let typeId: Int
    public let attributeId: Int
    public let value: Double
    public let attribute: DogmaAttribute?

    public init(typeId: Int, attributeId: Int, value: Double, attribute: DogmaAttribute?) {
        self.typeId = typeId; self.attributeId = attributeId
        self.value = value; self.attribute = attribute
    }
}

public struct DogmaModifierDetail: Identifiable, Sendable, Hashable {
    public var id: String {
        "\(effectId):\(domain):\(function):\(operation):\(modifiedAttrId):\(modifyingAttrId):\(groupId ?? -1):\(skillTypeId ?? -1)"
    }

    public let effectId: Int
    public let domain: String
    public let function: String
    public let groupId: Int?
    public let modifiedAttrId: Int
    public let modifiedAttrName: String?
    public let modifyingAttrId: Int
    public let modifyingAttrName: String?
    public let operation: Int
    public let skillTypeId: Int?
    public let skillName: String?

    public init(
        effectId: Int,
        domain: String,
        function: String,
        groupId: Int?,
        modifiedAttrId: Int,
        modifiedAttrName: String?,
        modifyingAttrId: Int,
        modifyingAttrName: String?,
        operation: Int,
        skillTypeId: Int?,
        skillName: String?
    ) {
        self.effectId = effectId
        self.domain = domain
        self.function = function
        self.groupId = groupId
        self.modifiedAttrId = modifiedAttrId
        self.modifiedAttrName = modifiedAttrName
        self.modifyingAttrId = modifyingAttrId
        self.modifyingAttrName = modifyingAttrName
        self.operation = operation
        self.skillTypeId = skillTypeId
        self.skillName = skillName
    }
}

public struct TypeEffectDetail: Identifiable, Sendable, Hashable {
    public var id: Int { effectId }
    public let typeId: Int
    public let effectId: Int
    public let name: String
    public let displayName: String?
    public let effectCategory: Int
    public let modifiers: [DogmaModifierDetail]

    public init(
        typeId: Int,
        effectId: Int,
        name: String,
        displayName: String?,
        effectCategory: Int,
        modifiers: [DogmaModifierDetail]
    ) {
        self.typeId = typeId
        self.effectId = effectId
        self.name = name
        self.displayName = displayName
        self.effectCategory = effectCategory
        self.modifiers = modifiers
    }
}

// MARK: - Character / Skills

public struct CharacterSkillEntry: Identifiable, Sendable, Hashable {
    public var id: Int { skillId }
    public let skillId: Int
    public let activeSkillLevel: Int
    public let trainedSkillLevel: Int
    public let skillpointsInSkill: Int

    public init(skillId: Int, activeSkillLevel: Int, trainedSkillLevel: Int, skillpointsInSkill: Int) {
        self.skillId = skillId; self.activeSkillLevel = activeSkillLevel
        self.trainedSkillLevel = trainedSkillLevel; self.skillpointsInSkill = skillpointsInSkill
    }
}

public struct CharacterSkillsState: Sendable {
    public let totalSP: Int
    public let unallocatedSP: Int
    public let skills: [CharacterSkillEntry]

    public init(totalSP: Int, unallocatedSP: Int, skills: [CharacterSkillEntry]) {
        self.totalSP = totalSP; self.unallocatedSP = unallocatedSP; self.skills = skills
    }
}

public struct SkillQueueEntry: Identifiable, Sendable {
    public var id: Int { queuePosition }
    public let queuePosition: Int
    public let skillId: Int
    public let finishedLevel: Int
    public let startDate: Date?
    public let finishDate: Date?
    public let trainingStartSP: Int
    public let levelStartSP: Int
    public let levelEndSP: Int
    public let skillName: String?   // resolved from SDE, may be nil if lookup fails

    public init(
        queuePosition: Int, skillId: Int, finishedLevel: Int,
        startDate: Date?, finishDate: Date?,
        trainingStartSP: Int, levelStartSP: Int, levelEndSP: Int,
        skillName: String? = nil
    ) {
        self.queuePosition = queuePosition; self.skillId = skillId
        self.finishedLevel = finishedLevel; self.startDate = startDate
        self.finishDate = finishDate; self.trainingStartSP = trainingStartSP
        self.levelStartSP = levelStartSP; self.levelEndSP = levelEndSP
        self.skillName = skillName
    }

    public var isActive: Bool { startDate != nil && finishDate != nil && (finishDate! > Date()) }

    /// 0…1 training progress based on wall-clock time.
    public var progress: Double {
        guard let start = startDate, let finish = finishDate, finish > start else { return 0 }
        return max(0, min(1, Date().timeIntervalSince(start) / finish.timeIntervalSince(start)))
    }

    /// Remaining time as a friendly string.
    public var remainingText: String {
        guard let finish = finishDate else { return "Paused" }
        let remaining = finish.timeIntervalSinceNow
        if remaining <= 0 { return "Done" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = remaining > 86400
            ? [.day, .hour]
            : (remaining > 3600 ? [.hour, .minute] : [.minute, .second])
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: remaining) ?? "–"
    }
}
