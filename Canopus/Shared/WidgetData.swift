import Foundation

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

    func save() {
        guard let url = Self.fileURL,
              let data = try? JSONEncoder().encode(self)
        else { return }
        try? data.write(to: url, options: [.atomic])
    }

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
