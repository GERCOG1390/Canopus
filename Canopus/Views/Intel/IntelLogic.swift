// Intel logic ported from the desktop (lib/intel.ts): pilot lookups with a threat rating from standings
// and zKillboard activity, and the parsers for Local, D-scan and fleet lists copied from the game.

import SwiftUI
import EVEAuth

enum Threat: String, CaseIterable {
    case hostile, high, medium, unknown, low, friendly

    var label: LocalizedStringKey {
        switch self {
        case .hostile: "Hostile"
        case .high: "Dangerous"
        case .medium: "Watch"
        case .low: "Calm"
        case .friendly: "Friendly"
        case .unknown: "…"
        }
    }

    /// Segments lit in the five-segment meter.
    var bars: Int {
        switch self {
        case .hostile: 5
        case .high: 4
        case .medium: 3
        case .low: 1
        case .friendly, .unknown: 0
        }
    }

    var color: Color {
        switch self {
        case .hostile: Color(hex: 0xF07A66)
        case .high: Color(hex: 0xF0965A)
        case .medium: C.warn
        case .low, .unknown: C.muted
        case .friendly: C.accentText
        }
    }
}

enum Relation { case me, corp, alliance, blue, red, neutral }

struct PilotIntel: Identifiable {
    let id: Int
    let name: String
    var corpId: Int?
    var allianceId: Int?
    var corpName: String?
    var corpTicker: String?
    var allianceName: String?
    var allianceTicker: String?
    var birthday: Date?
    var relation: Relation = .neutral
    /// nil while loading; .some(nil) when zKillboard has nothing.
    var zkb: ZKBCharacterStats??
    var threat: Threat = .unknown
}

/// Who the pilot is: id, corporation and alliance (standings need the contacts scopes, which the
/// iOS login doesn't have yet, so blue / red come later).
struct Me {
    let id: Int
    let corpId: Int?
    let allianceId: Int?
}

enum IntelLogic {
    static func relation(_ p: PilotIntel, me: Me?) -> Relation {
        guard let me else { return .neutral }
        if p.id == me.id { return .me }
        if let c = p.corpId, c == me.corpId { return .corp }
        if let a = p.allianceId, a == me.allianceId { return .alliance }
        return .neutral
    }

    /// Heuristic danger rating from standings and recent zKillboard activity.
    static func threat(_ p: PilotIntel) -> Threat {
        switch p.relation {
        case .me, .corp, .alliance, .blue: return .friendly
        case .red: return .hostile
        case .neutral: break
        }
        guard let loaded = p.zkb else { return .unknown }
        guard let z = loaded else { return .low }
        if (z.activeWeek >= 3 || z.recentKills >= 15) && z.danger >= 50 { return .high }
        if z.activeWeek >= 1 || z.recentKills >= 3 || (z.kills >= 100 && z.danger >= 60) { return .medium }
        return .low
    }

    static func sorted(_ list: [PilotIntel]) -> [PilotIntel] {
        let order = Threat.allCases
        return list.sorted {
            let a = order.firstIndex(of: $0.threat)!, b = order.firstIndex(of: $1.threat)!
            if a != b { return a < b }
            let ka = ($0.zkb ?? nil)?.recentKills ?? 0, kb = ($1.zkb ?? nil)?.recentKills ?? 0
            if ka != kb { return ka > kb }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Pilots by name; `update` is called as data arrives: identities and affiliations first, then
    /// corporations and alliances, then zKillboard (four at a time: zKillboard asks to be gentle).
    @MainActor
    static func scan(names: [String], me: Me?, update: @escaping ([PilotIntel]) -> Void) async throws -> (pilots: [PilotIntel], unknown: [String]) {
        let esi = PublicESI.shared
        let found = try await esi.characterIds(names: names)
        let known = Set(found.map { $0.name.lowercased() })
        let unknown = names.filter { !known.contains($0.lowercased()) }
        let aff = try await esi.affiliations(found.map(\.id))
        var pilots = found.map { c -> PilotIntel in
            var p = PilotIntel(id: c.id, name: c.name, corpId: aff[c.id]?.corporationId, allianceId: aff[c.id]?.allianceId)
            p.relation = relation(p, me: me)
            p.threat = threat(p)
            return p
        }
        update(pilots)

        for corp in Set(pilots.compactMap(\.corpId)) {
            guard let c = await esi.corporation(corp) else { continue }
            for i in pilots.indices where pilots[i].corpId == corp { pilots[i].corpName = c.name; pilots[i].corpTicker = c.ticker }
        }
        for alliance in Set(pilots.compactMap(\.allianceId)) {
            guard let a = await esi.alliance(alliance) else { continue }
            for i in pilots.indices where pilots[i].allianceId == alliance { pilots[i].allianceName = a.name; pilots[i].allianceTicker = a.ticker }
        }
        update(pilots)

        // Friendlies need no threat lookup.
        let queue = pilots.indices.filter { pilots[$0].threat != .friendly }
        for start in stride(from: 0, to: queue.count, by: 4) {
            try Task.checkCancellation()
            let batch = Array(queue[start..<min(start + 4, queue.count)])
            let results = await withTaskGroup(of: (Int, ZKBCharacterStats?, Date?).self) { group in
                for i in batch {
                    let id = pilots[i].id
                    group.addTask { (i, await esi.zkbStats(id), await esi.character(id)?.birthday) }
                }
                var out: [(Int, ZKBCharacterStats?, Date?)] = []
                for await r in group { out.append(r) }
                return out
            }
            for (i, z, birthday) in results {
                pilots[i].zkb = .some(z)
                pilots[i].birthday = birthday
                pilots[i].threat = threat(pilots[i])
            }
            update(pilots)
        }
        for i in pilots.indices where pilots[i].zkb == nil { pilots[i].zkb = .some(nil) }
        update(pilots)
        return (pilots, unknown)
    }

    static func parseLocal(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    // MARK: D-scan and fleet

    struct ScanRow {
        let typeId: Int
        let name: String
        let typeName: String
        /// km; nil when off grid / unknown.
        let distanceKm: Double?
    }

    /// Grid is roughly 8 000 km across.
    static let onGridKm = 8000.0

    /// "11190\tName\tSabre\t1 234 km" rows; distances in the client's locale.
    static func parseDscan(_ text: String) -> [ScanRow] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let c = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard c.count >= 3, let id = Int(c[0].trimmingCharacters(in: .whitespaces)) else { return nil }
            return ScanRow(typeId: id, name: c[1].trimmingCharacters(in: .whitespaces), typeName: c[2].trimmingCharacters(in: .whitespaces),
                           distanceKm: c.count > 3 ? distance(c[3]) : nil)
        }
    }

    private static func distance(_ raw: String) -> Double? {
        let pattern = #"([\d\s.,  ]+)\s*(km|км|m|м|AU|а\.\s?е\.)"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let nr = Range(m.range(at: 1), in: raw), let ur = Range(m.range(at: 2), in: raw) else { return nil }
        var digits = raw[nr].replacingOccurrences(of: #"[\s  ]"#, with: "", options: .regularExpression)
        digits = digits.replacingOccurrences(of: #",(?=\d{3}\b)"#, with: "", options: .regularExpression).replacingOccurrences(of: ",", with: ".")
        guard let n = Double(digits) else { return nil }
        switch raw[ur].lowercased() {
        case "km", "км": return n
        case "m", "м": return n / 1000
        default: return n * 149_597_870.7
        }
    }

    /// Fleet window rows (tab-separated): the pilot and whichever cell names a ship.
    static func parseFleet(_ text: String) -> [[String]] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.split(separator: "\t").map { $0.trimmingCharacters(in: .whitespaces) } }
            .filter { $0.count >= 2 }
    }
}
