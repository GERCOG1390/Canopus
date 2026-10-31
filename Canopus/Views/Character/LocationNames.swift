// Names of the places assets, contracts and transactions point at (the desktop's resolveLocations):
// stations and systems from /universe/names, player structures one by one where the pilot has docking
// access (ESI refuses the rest; those stay "Structure").

import Foundation
import EVEAuth

enum LocationNames {
    /// Structures ESI refused this session (no docking access, or an item id, not a structure): asking
    /// again only spends the ESI error budget (100 errors a minute, then every call is blocked).
    nonisolated(unsafe) private static var refused: Set<Int> = []

    static func resolve(_ ids: some Sequence<Int>, service: CharacterService) async -> [Int: String] {
        let unique = Set(ids.filter { $0 > 0 })
        // /universe/names fails the whole batch on one id it doesn't know (asset safety is 2004, say):
        // only systems and stations go there.
        let named = unique.filter { (30_000_000..<33_000_000).contains($0) || (60_000_000..<64_000_000).contains($0) }
        var out = (try? await MarketService().names(ids: named.sorted())) ?? [:]
        for id in unique where id >= 1_000_000_000_000 && !refused.contains(id) {
            if let s = try? await service.structureInfo(id: id) { out[id] = s.name } else { refused.insert(id) }
        }
        return out
    }
}
