import Foundation

// MARK: - Skill Queue

public struct ESISkillQueueItem: Decodable, Sendable {
    public let queuePosition: Int
    public let skillId: Int
    public let finishedLevel: Int
    public let startDate: Date?
    public let finishDate: Date?
    public let trainingStartSp: Int?
    public let levelStartSp: Int?
    public let levelEndSp: Int?
}

// MARK: - Skills

public struct ESISkillsResponse: Decodable, Sendable {
    public let totalSp: Int
    public let unallocatedSp: Int?
    public let skills: [ESISkillItem]
}

public struct ESISkillItem: Decodable, Sendable {
    public let skillId: Int
    public let activeSkillLevel: Int
    public let skillpointsInSkill: Int
    public let trainedSkillLevel: Int
}

// MARK: - Character public info

public struct ESICharacterInfo: Decodable, Sendable {
    public let name: String
    public let corporationId: Int
    public let allianceId: Int?
    public let securityStatus: Double?
    public let description: String?
    public let birthday: Date?
    public let gender: String?
    public let raceId: Int?
}

// MARK: - Corporation

public struct ESICorporationInfo: Decodable, Sendable {
    public let name: String
    public let ticker: String
    public let allianceId: Int?
    public let memberCount: Int?
}

// MARK: - Alliance

public struct ESIAllianceInfo: Decodable, Sendable {
    public let name: String
    public let ticker: String
}

// MARK: - Assets

public struct ESIAsset: Decodable, Sendable, Identifiable {
    public var id: Int { itemId }
    public let itemId: Int
    public let typeId: Int
    public let locationId: Int
    public let locationFlag: String
    public let locationType: String
    public let quantity: Int
    public let isSingleton: Bool
    public let isBlueprintCopy: Bool?
}

// MARK: - Industry Jobs

public struct ESIIndustryJob: Decodable, Sendable, Identifiable {
    public var id: Int { jobId }
    public let jobId: Int
    public let activityId: Int
    public let blueprintTypeId: Int
    public let productTypeId: Int?
    public let runs: Int
    public let duration: Int
    public let cost: Double?
    public let startDate: Date
    public let endDate: Date
    public let facilityId: Int
    public let installerId: Int
    public let status: String
    public let completedDate: Date?
    public let successfulRuns: Int?
}

// MARK: - Market Orders

public struct ESIMarketOrder: Decodable, Sendable, Identifiable {
    public var id: Int { orderId }
    public let orderId: Int
    public let typeId: Int
    public let regionId: Int
    public let locationId: Int
    public let range: String?
    public let isBuyOrder: Bool?
    public let price: Double
    public let volumeTotal: Int
    public let volumeRemain: Int
    public let minVolume: Int?
    public let issued: Date
    public let duration: Int
    public let state: String
}

// MARK: - Contracts

public struct ESIContract: Decodable, Sendable, Identifiable {
    public var id: Int { contractId }
    public let contractId: Int
    public let issuerId: Int
    public let assigneeId: Int
    public let acceptorId: Int
    public let type: String
    public let status: String
    public let title: String?
    public let forCorporation: Bool
    public let availability: String
    public let dateIssued: Date
    public let dateExpired: Date
    public let dateCompleted: Date?
    public let price: Double?
    public let reward: Double?
    public let collateral: Double?
    public let volume: Double?
}

// MARK: - Server Status

public struct ESIServerStatus: Decodable, Sendable {
    public let players: Int
    public let serverVersion: String
    public let startTime: Date
}

// MARK: - Clones & Implants

public struct ESIClonesInfo: Decodable, Sendable {
    public let homeLocation: ESIHomeLocation?
    public let lastCloneJumpDate: Date?
    public let lastStationChangeDate: Date?
}

public struct ESIHomeLocation: Decodable, Sendable {
    public let locationId: Int
    public let locationType: String
}

// MARK: - Loyalty Points

public struct ESILoyaltyPoint: Decodable, Sendable, Identifiable {
    public var id: Int { corporationId }
    public let corporationId: Int
    public let loyaltyPoints: Int
}

// MARK: - Wallet Journal

public struct ESIWalletEntry: Decodable, Sendable, Identifiable {
    public let id: Int
    public let date: Date
    public let refType: String
    public let amount: Double?
    public let balance: Double?
    public let description: String?
    public let firstPartyId: Int?
    public let secondPartyId: Int?
}

// MARK: - Market (M4)

public struct ESIMarketPrice: Decodable, Sendable {
    public let typeId: Int
    public let adjustedPrice: Double?
    public let averagePrice: Double?
}

/// One day of regional price history. `date` is "YYYY-MM-DD" string (not Date)
/// because ESI returns date-only format incompatible with JSONDecoder.esi.
public struct ESIMarketHistory: Decodable, Sendable {
    public let date: String
    public let average: Double
    public let highest: Double
    public let lowest: Double
    public let orderCount: Int
    public let volume: Int
}

/// A single regional market order (GET /markets/{region}/orders/).
public struct ESIRegionalOrder: Decodable, Sendable, Identifiable {
    public var id: Int { orderId }
    public let orderId: Int
    public let typeId: Int
    public let locationId: Int
    public let systemId: Int
    public let isBuyOrder: Bool
    public let price: Double
    public let volumeRemain: Int
    public let volumeTotal: Int
    public let minVolume: Int
    public let range: String
    public let issued: Date
    public let duration: Int
}

// MARK: - Character location

public struct ESICharacterLocation: Decodable, Sendable {
    public let solarSystemId: Int
    public let stationId: Int?
    public let structureId: Int?
}

// MARK: - Character attributes

public struct ESICharacterAttributes: Decodable, Sendable {
    public let perception: Int
    public let memory: Int
    public let willpower: Int
    public let intelligence: Int
    public let charisma: Int
    public let lastRemapDate: Date?
    public let accruedRemapCooldownDate: Date?
    public let bonusRemaps: Int?
}

// MARK: - Employment history

public struct ESIEmploymentHistoryItem: Decodable, Sendable, Identifiable {
    public var id: Int { recordId }
    public let recordId: Int
    public let corporationId: Int
    public let startDate: Date
    public let isDeleted: Bool?
}

// MARK: - Current ship

public struct ESICurrentShip: Decodable, Sendable {
    public let shipItemId: Int
    public let shipName: String
    public let shipTypeId: Int
}

// MARK: - Universe locations

public struct ESIStationInfo: Decodable, Sendable {
    public let name: String
    public let systemId: Int
}

public struct ESISystemInfo: Decodable, Sendable {
    public let name: String
    public let securityStatus: Double?
}

public struct ESIStructureInfo: Decodable, Sendable {
    public let name: String
    public let solarSystemId: Int
}

// MARK: - Fittings

public struct ESIFitting: Decodable, Sendable, Identifiable {
    public let fittingId: Int
    public var id: Int { fittingId }
    public let name: String
    public let description: String
    public let shipTypeId: Int
    public let items: [ESIFittingItem]
}

public struct ESIFittingItem: Decodable, Sendable, Identifiable {
    public var id: String { "\(typeId)-\(flag)" }
    public let typeId: Int
    public let flag: String   // e.g. "HiSlot0", "MedSlot2", "DroneBay", "Cargo"
    public let quantity: Int

    public init(typeId: Int, flag: String, quantity: Int) {
        self.typeId = typeId
        self.flag = flag
        self.quantity = quantity
    }
}

// MARK: - Kill Mails

public struct ESIKillMail: Decodable, Sendable {
    public let killmailId: Int
    public let killmailTime: Date
    public let solarSystemId: Int
    public let victim: ESIKillVictim
    public let attackers: [ESIKillAttacker]
}

public struct ESIKillVictim: Decodable, Sendable {
    public let characterId: Int?
    public let corporationId: Int?
    public let allianceId: Int?
    public let shipTypeId: Int
    public let damageTaken: Int
}

public struct ESIKillAttacker: Decodable, Sendable {
    public let characterId: Int?
    public let corporationId: Int?
    public let finalBlow: Bool
    public let damageDone: Int
    public let shipTypeId: Int?
    public let weaponTypeId: Int?
    public let securityStatus: Double
}

// MARK: - Wallet Transactions

public struct ESIWalletTransaction: Decodable, Sendable, Identifiable {
    public var id: Int { transactionId }
    public let transactionId: Int
    public let date: Date
    public let typeId: Int
    public let unitPrice: Double
    public let quantity: Int
    public let clientId: Int
    public let locationId: Int
    public let isBuy: Bool
    public let isPersonal: Bool
    public let journalRefId: Int
}

// MARK: - Mining Ledger

public struct ESIMiningEntry: Decodable, Sendable, Identifiable {
    public var id: String { "\(date)-\(solarSystemId)-\(typeId)" }
    public let date: String          // "YYYY-MM-DD"
    public let solarSystemId: Int
    public let typeId: Int
    public let quantity: Int
}

// MARK: - EVE Mail

public struct ESIMailHeader: Decodable, Sendable, Identifiable, Hashable {
    public var id: Int { mailId }
    public let mailId: Int
    public let from: Int
    public let subject: String
    public let timestamp: Date
    public let isRead: Bool?
    public let labels: [Int]?
    public let recipients: [ESIMailRecipient]
}

public struct ESIMailRecipient: Decodable, Sendable, Hashable {
    public let recipientId: Int
    public let recipientType: String
}

public struct ESIMailBody: Decodable, Sendable {
    public let body: String
    public let from: Int
    public let read: Bool?
    public let subject: String
    public let timestamp: Date
    public let recipients: [ESIMailRecipient]
    public let labels: [Int]?
}

public struct ESIMailLabel: Decodable, Sendable, Identifiable {
    public var id: Int { labelId }
    public let labelId: Int
    public let name: String?
    public let unreadCount: Int?
    public let color: String?
}

public struct ESIMailLabelsResponse: Decodable, Sendable {
    public let labels: [ESIMailLabel]
    public let totalUnreadCount: Int?
}

// MARK: - Universe name resolution

public struct ESINameResult: Decodable, Sendable {
    public let id: Int
    public let name: String
    public let category: String
}

// MARK: - JSON Decoder

extension JSONDecoder {
    /// Decoder configured for ESI responses: snake_case keys, ISO8601 dates.
    public static let esi: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let short = ISO8601DateFormatter()
        short.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let s = try container.decode(String.self)
            if let d = full.date(from: s) { return d }
            if let d = short.date(from: s) { return d }
            throw DecodingError.dataCorruptedError(in: container,
                debugDescription: "Unrecognised date: \(s)")
        }
        return d
    }()
}
