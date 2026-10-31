// The in-game market tree, level by level (the desktop's marketChildren): groups with their icon and the
// number of published items under them, then the group's own items in the game's order — Tech I, Tech II,
// storyline, faction, deadspace, officer, Tech III, and by meta level inside each.

import Foundation
import Domain
import GRDB

public struct MarketNode: Identifiable, Sendable, Hashable {
    public let id: Int
    public let name: String
    public let iconId: Int?
    /// Published items anywhere under the group
    public let count: Int
}

public struct MarketTreeLevel: Sendable {
    public let groups: [MarketNode]
    public let types: [ItemType]
}

/// Parent → children and group → items, built once from the database.
private final class MarketIndex: @unchecked Sendable {
    struct Group { let parent: Int?; let name: String; let icon: Int? }
    let groups: [Int: Group]
    let children: [Int: [Int]]
    let types: [Int: [Int]]
    let count: [Int: Int]

    init(_ db: Database) throws {
        var groups: [Int: Group] = [:]
        var children: [Int: [Int]] = [:]
        for r in try Row.fetchAll(db, sql: "SELECT id, parent_id, name, icon_id FROM market_groups") {
            let id: Int = r["id"], parent: Int? = r["parent_id"]
            groups[id] = Group(parent: parent, name: SDENames.name("market_group", id, r["name"]), icon: r["icon_id"])
            children[parent ?? 0, default: []].append(id)
        }
        var types: [Int: [Int]] = [:]
        for r in try Row.fetchAll(db, sql: "SELECT id, market_group_id FROM types WHERE published = 1 AND market_group_id IS NOT NULL") {
            types[r["market_group_id"], default: []].append(r["id"])
        }
        var count: [Int: Int] = [:]
        func countOf(_ id: Int) -> Int {
            if let n = count[id] { return n }
            let n = (types[id]?.count ?? 0) + (children[id] ?? []).reduce(0) { $0 + countOf($1) }
            count[id] = n
            return n
        }
        for id in groups.keys { _ = countOf(id) }
        self.groups = groups; self.children = children; self.types = types; self.count = count
    }

    nonisolated(unsafe) static var shared: MarketIndex?
    static let lock = NSLock()
}

/// Some Russian SDE names contain Latin look-alike letters ("Cооружения"), which would sort them first.
func marketSortKey(_ s: String) -> String {
    guard s.range(of: "[а-яё]", options: [.regularExpression, .caseInsensitive]) != nil else { return s }
    let map: [Character: Character] = ["A": "А", "B": "В", "C": "С", "E": "Е", "H": "Н", "K": "К", "M": "М", "O": "О", "P": "Р",
                                       "T": "Т", "X": "Х", "a": "а", "c": "с", "e": "е", "o": "о", "p": "р", "x": "х", "y": "у"]
    return String(s.map { map[$0] ?? $0 })
}

/// Tech I, Tech II, storyline, faction, deadspace, officer, Tech III — the game's order of meta groups.
private func metaRank(_ meta: Int?) -> Int {
    guard let meta else { return 0 }
    return [1: 0, 2: 1, 3: 2, 4: 3, 6: 4, 5: 5, 14: 6][meta] ?? 7
}

extension SDERepository {
    private func marketIndex() async throws -> MarketIndex {
        if let cached = MarketIndex.lock.withLock({ MarketIndex.shared }) { return cached }
        let built = try await dbReader.read { try MarketIndex($0) }
        MarketIndex.lock.withLock { MarketIndex.shared = built }
        return built
    }

    /// One level of the market tree (nil = the root): non-empty subgroups by name, then the group's items.
    public func marketLevel(parent: Int?) async throws -> MarketTreeLevel {
        let idx = try await marketIndex()
        let groups = (idx.children[parent ?? 0] ?? [])
            .filter { (idx.count[$0] ?? 0) > 0 }
            .compactMap { id in idx.groups[id].map { MarketNode(id: id, name: $0.name, iconId: $0.icon, count: idx.count[id] ?? 0) } }
            .sorted { marketSortKey($0.name).localizedStandardCompare(marketSortKey($1.name)) == .orderedAscending }
        let ids = parent.flatMap { idx.types[$0] } ?? []
        guard !ids.isEmpty else { return MarketTreeLevel(groups: groups, types: []) }
        let list = ids.map(String.init).joined(separator: ",")
        let (types, levels) = try await dbReader.read { db in
            let types = try TypeRecord.fetchAll(db, sql: "SELECT * FROM types WHERE id IN (\(list))").map { $0.toDomain() }
            var levels: [Int: Double] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT type_id, value FROM type_attributes WHERE attribute_id = 633 AND type_id IN (\(list))") {
                levels[r["type_id"]] = r["value"]
            }
            return (types, levels)
        }
        let sorted = types.sorted { a, b in
            let ra = metaRank(a.metaGroupId), rb = metaRank(b.metaGroupId)
            if ra != rb { return ra < rb }
            let la = levels[a.id] ?? 0, lb = levels[b.id] ?? 0
            if la != lb { return la < lb }
            return marketSortKey(a.name).localizedStandardCompare(marketSortKey(b.name)) == .orderedAscending
        }
        return MarketTreeLevel(groups: groups, types: sorted)
    }

    /// Market groups from the root down to the item's own group (to open the tree at an item).
    public func marketPath(typeId: Int) async throws -> [Int] {
        let idx = try await marketIndex()
        guard let start = try await dbReader.read({ db in
            try Int.fetchOne(db, sql: "SELECT market_group_id FROM types WHERE id = ?", arguments: [typeId])
        }) else { return [] }
        var path: [Int] = []
        var g: Int? = start
        while let id = g, path.count < 12 { path.insert(id, at: 0); g = idx.groups[id]?.parent }
        return path
    }
}

extension SDERepository {
    /// A game UI icon's file on CCP's resource CDN (importer 4), as the desktop loads it; nil on an older database.
    public func iconURL(id: Int) async throws -> URL? {
        try await dbReader.read { db in
            guard try db.tableExists("icons") else { return nil }
            return try String.fetchOne(db, sql: "SELECT path FROM icons WHERE id = ?", arguments: [id])
                .flatMap { URL(string: "https://resources.eveonline.com/\($0)") }
        }
    }
}
