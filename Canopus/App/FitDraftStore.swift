// The fit being built, kept outside the screens (the desktop's FittingProvider with its localStorage
// draft): when SwiftUI rebuilds the fitting screen — another page picked on iPad, the phone turned,
// the app sent to the background — the fit comes back as it was instead of being lost.

import Foundation
import Observation
import EVEAuth
import EVEStaticData

struct FitDraft: Codable, Equatable {
    struct Item: Codable, Equatable { let typeId: Int; let flag: String; let quantity: Int }
    struct Config: Codable, Equatable { let state: String; let chargeTypeId: Int? }

    let fittingId: Int
    let name: String
    let description: String
    let shipTypeId: Int
    var items: [Item]
    var configs: [String: Config]
    var droneActive: [Int: Int]
    var typeNames: [Int: String]
    /// The fit's own implants and boosters when the pilot changed them (nil: the character's).
    var implants: [Int]? = nil

    var fitting: ESIFitting {
        ESIFitting(fittingId: fittingId, name: name, description: description, shipTypeId: shipTypeId,
                   items: items.map { ESIFittingItem(typeId: $0.typeId, flag: $0.flag, quantity: $0.quantity) })
    }

    var moduleConfigs: [String: ModuleConfig] {
        configs.compactMapValues { c in ModuleState(rawValue: c.state).map { ModuleConfig(state: $0, chargeTypeId: c.chargeTypeId) } }
    }
}

@Observable
final class FitDraftStore {
    static let shared = FitDraftStore()

    private static let key = "fitDraft.v1"

    /// The fit last edited; replaced when another fit is opened.
    private(set) var draft: FitDraft?
    /// Whether the fitting screen was open, and from which fittings list (a list instance that is rebuilt
    /// gets a new id, so an open fit there was closed by SwiftUI, not by the pilot).
    var openFrom: UUID?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key) {
            draft = try? JSONDecoder().decode(FitDraft.self, from: data)
        }
        openFrom = UserDefaults.standard.string(forKey: Self.key + ".open").flatMap(UUID.init(uuidString:))
        #if DEBUG
        // Debug builds: `-fitDraftDrop MedSlot3` takes a module out of the saved draft, as if the pilot had
        // removed it before the screen was rebuilt (checks that the reopened fit is the draft).
        if let flag = UserDefaults.standard.string(forKey: "fitDraftDrop"), var d = draft {
            d.items.removeAll { $0.flag == flag }
            d.configs[flag] = nil
            draft = d
        }
        #endif
    }

    func save(_ d: FitDraft) {
        guard d != draft else { return }
        draft = d
        if let data = try? JSONEncoder().encode(d) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    func setOpen(_ list: UUID?) {
        openFrom = list
        UserDefaults.standard.set(list?.uuidString, forKey: Self.key + ".open")
    }

    /// The saved state of this fit, when it is the one being built.
    func draft(for fittingId: Int) -> FitDraft? { draft?.fittingId == fittingId ? draft : nil }
}

/// One fittings list for as long as SwiftUI keeps it (held in @State): registered while alive.
final class FitListToken {
    let id = UUID()
    nonisolated(unsafe) static var live: Set<UUID> = []
    init() { Self.live.insert(id) }
    deinit { Self.live.remove(id) }
}
