import Foundation

// Mirror of the app's WidgetData — must remain JSON-compatible.
struct WidgetData: Codable {
    let characterId: Int
    let characterName: String
    let activeSkillName: String?
    let activeSkillLevel: Int?
    let activeSkillFinishDate: Date?
    let queueCount: Int
    let updatedAt: Date

    static let appGroupID = "group.AlexPlumbing.Canopus"
    static let fileName = "widgetData.json"

    static func load() -> WidgetData? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(WidgetData.self, from: data)
        else { return nil }
        return decoded
    }

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }
}
