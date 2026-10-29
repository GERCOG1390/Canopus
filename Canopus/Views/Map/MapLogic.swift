// The map's own logic, ported from the desktop: alliance colours for sovereignty (GalaxyMap.tsx), jump
// bridge lists (sde parseBridges) and routes over gates plus bridges (sde routeLocal).

import Foundation
import simd
import EVEStaticData

/// The player's Ansiblex network: the pasted text, the pairs found in it, and the alliance capital.
struct BridgeStore: Codable, Equatable {
    var text = ""
    var list: [GalaxyPair] = []
    var capital: Int?

    private static let key = "map.bridges"

    static func load() -> BridgeStore {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(BridgeStore.self, from: $0) } ?? BridgeStore()
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) }
    }
}

enum MapLogic {
    /// The biggest alliances get clearly different colours; the rest a stable hue from their id.
    static let topColors: [UInt32] = [0x4E9BFF, 0xFF6B6B, 0xFFD43B, 0x51CF66, 0xCC5DE8, 0xFF922B, 0x22B8CF, 0xF06595, 0x94D82D, 0x845EF7]

    static func color(hex: UInt32) -> SIMD4<Float> {
        SIMD4(Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255, 1)
    }

    static func hashedColor(_ id: Int) -> SIMD4<Float> {
        let h = (Double(id) * 0.618033988749895).truncatingRemainder(dividingBy: 1)
        return hsl(h < 0 ? h + 1 : h, 0.55, 0.6)
    }

    private static func hsl(_ h: Double, _ s: Double, _ l: Double) -> SIMD4<Float> {
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
        func channel(_ t0: Double) -> Float {
            let t = t0 < 0 ? t0 + 1 : t0 > 1 ? t0 - 1 : t0
            if t < 1 / 6 { return Float(p + (q - p) * 6 * t) }
            if t < 1 / 2 { return Float(q) }
            if t < 2 / 3 { return Float(p + (q - p) * (2 / 3 - t) * 6) }
            return Float(p)
        }
        return SIMD4(channel(h + 1 / 3), channel(h), channel(h - 1 / 3), 1)
    }

    // MARK: Bridges

    /// Bridges from pasted text, one per line: "1DQ1-A » 8WA-Z6", Dotlan's "1DQ1-A @ 3-4 » 8WA-Z6 @ 1-1",
    /// or structure names; a line is a bridge when two systems are named in it.
    static func parseBridges(_ text: String, galaxy g: GalaxyData) -> (bridges: [GalaxyPair], unknown: [String]) {
        var byName: [String: Int] = [:]
        var maxWords = 1
        for i in 0..<g.count {
            let n = g.names[i].lowercased()
            byName[n] = g.ids[i]
            maxWords = max(maxWords, n.split(separator: " ").count)
        }
        let separators = CharacterSet(charactersIn: " \t,;:!?()[]{}<>\"*|/\\»«→=")
        var bridges: [GalaxyPair] = [], unknown: [String] = [], seen = Set<String>()
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let words = line.components(separatedBy: separators).filter { !$0.isEmpty }
            var found: [Int] = []
            var i = 0
            while i < words.count && found.count < 2 {
                var matched = 0
                var n = min(maxWords, words.count - i)
                while n >= 1 && matched == 0 {
                    if let id = byName[words[i..<i + n].joined(separator: " ").lowercased()], !found.contains(id) {
                        found.append(id)
                        matched = n
                    }
                    n -= 1
                }
                i += max(matched, 1)
            }
            guard found.count == 2 else { unknown.append(line); continue }
            let key = found.sorted().map(String.init).joined(separator: "-")
            if seen.insert(key).inserted { bridges.append(GalaxyPair(a: found[0], b: found[1])) }
        }
        return (bridges, unknown)
    }

    static func lightYears(_ g: GalaxyData, _ a: Int, _ b: Int) -> Float? {
        guard let i = g.index[a], let j = g.index[b] else { return nil }
        return simd_length(g.positions[i] - g.positions[j])
    }

    // MARK: Routes over gates and bridges

    /// Dijkstra over stargates plus the bridges, with the game's preferences: "secure" avoids systems
    /// below 0.45, "insecure" avoids highsec. Avoided systems are never entered (the ends always can be).
    static func route(_ g: GalaxyData, from: Int, to: Int, flag: String, bridges: [GalaxyPair], avoid: [Int]) -> (ids: [Int], bridgeHops: Int)? {
        guard let s = g.index[from], let t = g.index[to] else { return nil }
        var extra: [Int: [Int]] = [:]
        for b in bridges {
            guard let i = g.index[b.a], let j = g.index[b.b] else { continue }
            extra[i, default: []].append(j)
            extra[j, default: []].append(i)
        }
        let avoided = Set(avoid.compactMap { g.index[$0] }).subtracting([s, t])
        func cost(_ i: Int) -> Double {
            let high = (g.security[i] * 10).rounded() / 10 >= 0.5
            switch flag {
            case "secure": return high ? 1 : 1000
            case "insecure": return high ? 1000 : 1
            default: return 1
            }
        }
        var dist = [Double](repeating: .infinity, count: g.count)
        var prev = [(from: Int, bridge: Bool)?](repeating: nil, count: g.count)
        var heap = Heap()
        dist[s] = 0
        heap.push((0, s))
        while let (c, i) = heap.pop() {
            if i == t { break }
            if c > dist[i] { continue }
            for (n, bridge) in g.neighbors[i].map({ ($0, false) }) + (extra[i] ?? []).map({ ($0, true) }) where !avoided.contains(n) {
                let nc = c + cost(n)
                if nc < dist[n] {
                    dist[n] = nc
                    prev[n] = (i, bridge)
                    heap.push((nc, n))
                }
            }
        }
        guard dist[t].isFinite else { return nil }
        var ids = [g.ids[t]], hops = 0, at = t
        while at != s, let p = prev[at] {
            if p.bridge { hops += 1 }
            ids.append(g.ids[p.from])
            at = p.from
        }
        return (ids.reversed(), hops)
    }

    /// A binary min-heap of (cost, system index).
    private struct Heap {
        private var items: [(Double, Int)] = []

        mutating func push(_ x: (Double, Int)) {
            items.append(x)
            var i = items.count - 1
            while i > 0 {
                let p = (i - 1) / 2
                if items[p].0 <= items[i].0 { break }
                items.swapAt(p, i)
                i = p
            }
        }

        mutating func pop() -> (Double, Int)? {
            guard let top = items.first else { return nil }
            let last = items.removeLast()
            if !items.isEmpty {
                items[0] = last
                var i = 0
                while true {
                    let l = 2 * i + 1, r = l + 1
                    var m = i
                    if l < items.count && items[l].0 < items[m].0 { m = l }
                    if r < items.count && items[r].0 < items[m].0 { m = r }
                    if m == i { break }
                    items.swapAt(m, i)
                    i = m
                }
            }
            return top
        }
    }
}
