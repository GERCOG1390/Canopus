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
    static let defaultsKey = "canopus.widgetData"

    func save() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID),
              let data = try? JSONEncoder().encode(self)
        else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    static func load() -> WidgetData? {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID),
              let data = defaults.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode(WidgetData.self, from: data)
        else { return nil }
        return decoded
    }
}
