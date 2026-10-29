// Live kill radar (the desktop's main/radar.ts): follows zKillboard's live killmail feed (R2Z2) and keeps
// the player kills of the last hour near the pilot (within a radius of jumps from where the character is,
// from ESI) or on the route planned on the map, marking gate camps, bubbles and smartbombs. Polling follows
// zKillboard's rules: the next file every ~100 ms while there are kills, 6 s after a 404. It runs while the
// app is open.

import Foundation
import Observation
import Domain
import EVEAuth
import EVEStaticData

struct RadarOrg: Hashable {
    let id: Int
    let isAlliance: Bool
    var name: String
}

struct RadarKill: Identifiable {
    let id: Int
    let time: Date
    let systemId: Int
    let system: String
    let security: Double
    /// Jumps from the pilot (nil when only on the route).
    let jumps: Int?
    let onRoute: Bool
    let victimShip: Int
    let victimShipName: String
    let victimGroup: String?
    let victimOrg: RadarOrg?
    let value: Double
    let attackers: Int
    /// The kill happened at a stargate: where the gate leads.
    let gate: (to: Int, toName: String)?
    let bubbles: Bool
    let smartbombs: Bool
    /// Several kills at the same gate within 20 minutes, or a big gang there.
    var camp: Bool
    let killers: [(org: RadarOrg, n: Int)]
    let attackerTypes: [(id: Int, n: Int)]
    let weapons: [(id: Int, n: Int)]
}

@MainActor
@Observable
final class RadarStore {
    static let shared = RadarStore()

    var enabled = UserDefaults.standard.bool(forKey: "radar.enabled") {
        didSet { UserDefaults.standard.set(enabled, forKey: "radar.enabled"); apply() }
    }
    /// Watch systems up to this many jumps from the pilot (0 = only the current one).
    var radius = UserDefaults.standard.object(forKey: "radar.radius") == nil ? 3 : UserDefaults.standard.integer(forKey: "radar.radius") {
        didSet { UserDefaults.standard.set(radius, forKey: "radar.radius"); rewatch() }
    }
    var watchRoute = UserDefaults.standard.object(forKey: "radar.route") as? Bool ?? true {
        didSet { UserDefaults.standard.set(watchRoute, forKey: "radar.route"); rewatch() }
    }
    /// The route planned on the map, in order.
    var route: [Int] = [] { didSet { if route != oldValue { rewatch() } } }

    private(set) var here: (id: Int, name: String)?
    private(set) var kills: [RadarKill] = []
    private(set) var seen = 0
    private(set) var watchedCount = 0
    private(set) var running = false
    private(set) var error: String?

    private var env: AppEnvironment?
    private var galaxy: GalaxyData?
    private var watched: [Int: Int] = [:]
    private var routeSet: Set<Int> = []
    private var recent: [R2Kill] = []
    private var loop: Task<Void, Never>?
    private var locator: Task<Void, Never>?
    private var typeNames: [Int: String] = [:]
    private var typeGroup: [Int: Int] = [:]
    private var groupNames: [Int: String] = [:]
    private var orgNames: [Int: String] = [:]
    private var systemGates: [Int: Set<Int>] = [:]
    private var gateTarget: [Int: Int] = [:]

    private static let keep: TimeInterval = 3600
    private static let campWindow: TimeInterval = 1200
    private static let bubbleGroups: Set<Int> = [541, 894]
    private static let smartbombGroup = 72
    private static let feed = "https://r2z2.zkillboard.com/ephemeral"

    /// Starts or stops the feed to match the settings.
    func attach(_ env: AppEnvironment) {
        self.env = env
        apply()
    }

    private func apply() {
        if enabled, loop == nil {
            loop = Task { await run() }
            locator = Task { await locate() }
        } else if !enabled {
            loop?.cancel(); loop = nil
            locator?.cancel(); locator = nil
            running = false
        }
    }

    // MARK: Where the pilot is

    /// The character's system from ESI, every 30 seconds while the radar runs.
    private func locate() async {
        while !Task.isCancelled {
            if let svc = env?.characterStore.selectedService, let loc = try? await svc.location(), loc.solarSystemId != here?.id {
                await loadGalaxy()
                let name = galaxy.flatMap { g in g.index[loc.solarSystemId].map { g.names[$0] } } ?? String(loc.solarSystemId)
                here = (loc.solarSystemId, name)
                rewatch()
            }
            try? await Task.sleep(for: .seconds(30))
        }
    }

    private func loadGalaxy() async {
        if galaxy == nil, let repo = env?.repository { galaxy = try? await repo.galaxy() }
    }

    /// Systems within `radius` jumps of the pilot, with their distance.
    private func rewatch() {
        watched = [:]
        if let here, let g = galaxy, let start = g.index[here.id] {
            var frontier = [start]
            var dist = [start: 0]
            for d in 1...max(1, radius) where radius > 0 {
                var next: [Int] = []
                for i in frontier { for n in g.neighbors[i] where dist[n] == nil { dist[n] = d; next.append(n) } }
                frontier = next
            }
            for (i, d) in dist { watched[g.ids[i]] = d }
        }
        routeSet = watchRoute ? Set(route) : []
        watchedCount = watched.count
        Task { await rebuild() }
    }

    // MARK: Feed

    private func run() async {
        running = true
        error = nil
        await loadGalaxy()
        var seq: Int?
        while !Task.isCancelled {
            do {
                if seq == nil {
                    struct Seq: Decodable { let sequence: Int }
                    let (data, status) = try await fetch("\(Self.feed)/sequence.json")
                    guard status == 200, let data else { throw RadarError.status(status) }
                    seq = try JSONDecoder().decode(Seq.self, from: data).sequence
                }
                let (data, status) = try await fetch("\(Self.feed)/\(seq!).json")
                if status == 200, let data {
                    error = nil
                    if let k = try? JSONDecoder.esi.decode(R2Kill.self, from: data) { await handle(k) }
                    seq! += 1
                    try await Task.sleep(for: .milliseconds(100))
                } else if status == 404 {
                    // No newer kill yet: wait as the feed asks.
                    try await Task.sleep(for: .seconds(6))
                } else {
                    throw RadarError.status(status)
                }
            } catch {
                if Task.isCancelled { break }
                self.error = error.localizedDescription
                seq = nil
                try? await Task.sleep(for: .seconds(30))
            }
        }
        running = false
    }

    private func fetch(_ url: String) async throws -> (Data?, Int) {
        var req = URLRequest(url: URL(string: url)!)
        req.setValue(EVEConstants.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (status == 200 ? data : nil, status)
    }

    private func handle(_ k: R2Kill) async {
        seen += 1
        // Killmails reach zKillboard late now and then: only the last hour is news.
        guard k.zkb.npc != true, Date().timeIntervalSince(k.esi.killmailTime) <= Self.keep else { return }
        recent.append(k)
        if recent.count > 2000 || recent.count % 50 == 0 {
            recent = Array(recent.filter { Date().timeIntervalSince($0.esi.killmailTime) <= Self.keep }.suffix(2000))
        }
        await build(k)
    }

    private var rebuilding = 0

    /// The watched area changed: the list is rebuilt from the last hour of kills.
    private func rebuild() async {
        rebuilding += 1
        let run = rebuilding
        kills = []
        for k in recent.sorted(by: { $0.esi.killmailTime < $1.esi.killmailTime }) {
            guard run == rebuilding else { return }
            await build(k)
        }
    }

    /// The radar entry for a kill in a watched system or on the route; added to the list.
    private func build(_ k: R2Kill) async {
        let sys = k.esi.solarSystemId
        let jumps = watched[sys]
        let onRoute = routeSet.contains(sys)
        guard jumps != nil || onRoute else { return }
        let attackers = k.esi.attackers
        await loadTypes(Set([k.esi.victim.shipTypeId] + attackers.compactMap(\.shipTypeId) + attackers.compactMap(\.weaponTypeId)))

        var gate: (to: Int, toName: String)?
        if let loc = k.zkb.locationID, await gates(of: sys).contains(loc), let to = await leadsTo(loc) {
            gate = (to, galaxy.flatMap { g in g.index[to].map { g.names[$0] } } ?? String(to))
        }
        let v = k.esi.victim
        let killerIds = tally(attackers.map { $0.allianceId ?? $0.corporationId }).prefix(2)
        await nameOrgs([v.allianceId ?? v.corporationId ?? 0] + killerIds.map(\.id))
        let killers = killerIds.map { kid -> (org: RadarOrg, n: Int) in
            let a = attackers.first { ($0.allianceId ?? $0.corporationId) == kid.id }
            return (org(a?.allianceId, a?.allianceId == nil ? a?.corporationId : nil) ?? RadarOrg(id: kid.id, isAlliance: false, name: ""), kid.n)
        }
        let time = k.esi.killmailTime
        let recentAtGate = gate.map { g in kills.filter { $0.systemId == sys && $0.gate?.to == g.to && Date().timeIntervalSince($0.time) < Self.campWindow }.count } ?? 0
        let info = galaxy.flatMap { g in g.index[sys].map { (g.names[$0], g.security[$0]) } }
        var kill = RadarKill(
            id: k.killmailId, time: time, systemId: sys, system: info?.0 ?? String(sys), security: info?.1 ?? 0,
            jumps: jumps, onRoute: onRoute,
            victimShip: v.shipTypeId, victimShipName: typeNames[v.shipTypeId] ?? "#\(v.shipTypeId)",
            victimGroup: typeGroup[v.shipTypeId].flatMap { groupNames[$0] },
            victimOrg: org(v.allianceId, v.corporationId),
            value: k.zkb.totalValue ?? 0, attackers: attackers.count, gate: gate,
            bubbles: attackers.contains { $0.shipTypeId.flatMap { typeGroup[$0] }.map { Self.bubbleGroups.contains($0) } ?? false },
            smartbombs: attackers.contains { $0.weaponTypeId.flatMap { typeGroup[$0] } == Self.smartbombGroup },
            camp: false,
            killers: killers,
            attackerTypes: tally(attackers.map(\.shipTypeId)).prefix(6).map { ($0.id, $0.n) },
            weapons: tally(attackers.map { a in a.weaponTypeId != a.shipTypeId ? a.weaponTypeId : nil }).prefix(4).map { ($0.id, $0.n) })
        kill.camp = gate != nil && (recentAtGate >= 1 || attackers.count >= 5)
        // A camp found now marks the earlier kills at the same gate too.
        if kill.camp, let g = gate {
            for i in kills.indices where kills[i].systemId == sys && kills[i].gate?.to == g.to { kills[i].camp = true }
        }
        kills = Array(([kill] + kills.filter { $0.id != kill.id }).sorted { $0.time > $1.time }.prefix(200))
    }

    // MARK: Lookups

    private func loadTypes(_ ids: Set<Int>) async {
        let missing = ids.subtracting(typeNames.keys)
        guard !missing.isEmpty, let repo = env?.repository, let types = try? await repo.types(ids: missing) else { return }
        for (id, t) in types { typeNames[id] = t.name; typeGroup[id] = t.groupId }
        let groups = Set(types.values.map(\.groupId)).subtracting(groupNames.keys)
        if !groups.isEmpty, let g = try? await repo.groups(ids: groups) {
            for (id, grp) in g { groupNames[id] = grp.name }
        }
    }

    private func nameOrgs(_ ids: [Int]) async {
        let missing = Set(ids.filter { $0 > 0 && orgNames[$0] == nil })
        guard !missing.isEmpty, let names = try? await MarketService().names(ids: Array(missing)) else { return }
        orgNames.merge(names) { _, new in new }
    }

    private func org(_ alliance: Int?, _ corp: Int?) -> RadarOrg? {
        if let alliance { return RadarOrg(id: alliance, isAlliance: true, name: orgNames[alliance] ?? "") }
        if let corp { return RadarOrg(id: corp, isAlliance: false, name: orgNames[corp] ?? "") }
        return nil
    }

    private func gates(of system: Int) async -> Set<Int> {
        if let g = systemGates[system] { return g }
        struct Sys: Decodable { let stargates: [Int]? }
        let data = try? await fetch("https://esi.evetech.net/latest/universe/systems/\(system)/").0
        let g = Set(data.flatMap { try? JSONDecoder.esi.decode(Sys.self, from: $0) }?.stargates ?? [])
        systemGates[system] = g
        return g
    }

    private func leadsTo(_ gate: Int) async -> Int? {
        if let t = gateTarget[gate] { return t }
        struct Gate: Decodable { struct Dest: Decodable { let systemId: Int }; let destination: Dest }
        let data = try? await fetch("https://esi.evetech.net/latest/universe/stargates/\(gate)/").0
        let t = data.flatMap { try? JSONDecoder.esi.decode(Gate.self, from: $0) }?.destination.systemId
        gateTarget[gate] = t
        return t
    }

    /// Counts of values, most common first.
    private func tally(_ values: [Int?]) -> [(id: Int, n: Int)] {
        values.compactMap { $0 }.reduce(into: [Int: Int]()) { $0[$1, default: 0] += 1 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (id: $0.key, n: $0.value) }
    }
}

private enum RadarError: LocalizedError {
    case status(Int)
    var errorDescription: String? {
        switch self {
        case .status(let s): s == 403 || s == 429 ? String(localized: "zKillboard asks to wait (\(s))") : "zKillboard \(s)"
        }
    }
}

/// One entry of zKillboard's live feed.
private struct R2Kill: Decodable {
    struct Esi: Decodable {
        let killmailTime: Date
        let solarSystemId: Int
        let victim: ESIKillVictim
        let attackers: [ESIKillAttacker]
    }
    struct Zkb: Decodable {
        let locationID: Int?
        let totalValue: Double?
        let npc: Bool?
    }
    let killmailId: Int
    let esi: Esi
    let zkb: Zkb
}
