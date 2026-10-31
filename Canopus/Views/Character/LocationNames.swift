// Names of the places assets, contracts and transactions point at (the desktop's resolveLocations):
// stations and systems from /universe/names, player structures one by one where the pilot has docking
// access (ESI refuses the rest; those stay "Structure").

import Foundation
import EVEAuth

enum LocationNames {
    static func resolve(_ ids: some Sequence<Int>, service: CharacterService) async -> [Int: String] {
        let unique = Set(ids.filter { $0 > 0 })
        var out = (try? await MarketService().names(ids: unique.filter { $0 < 100_000_000 }.sorted())) ?? [:]
        for id in unique where id >= 1_000_000_000_000 {
            if let s = try? await service.structureInfo(id: id) { out[id] = s.name }
        }
        return out
    }
}
