// The intel page (the desktop's IntelPage.tsx): Local check, D-scan, fleet composition and the live kill
// radar. On the phone there is no game client to read: lists are pasted (on a Mac with Universal
// Clipboard, Ctrl+A / Ctrl+C in the game puts them on the phone's clipboard). The desktop's intel
// channels read the game's chat logs and stay on the desktop.

import SwiftUI
import UIKit
import Domain
import EVEAuth
import EVEStaticData

struct IntelPage: View {
    private enum Tab: String { case local, dscan, fleet, radar }
    @State private var tab: Tab = {
        #if DEBUG
        // Debug builds: `-intelTab radar` (screenshots).
        if let t = UserDefaults.standard.string(forKey: "intelTab").flatMap(Tab.init(rawValue:)) { return t }
        #endif
        return .local
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                CanopusTabs(tabs: [(Tab.local, "Local"), (.dscan, "D-scan"), (.fleet, "Fleet"), (.radar, "Kill radar")], selection: $tab)
                switch tab {
                case .local: LocalTab()
                case .dscan: DscanTab()
                case .fleet: FleetTab()
                case .radar: RadarTab()
                }
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .background(C.bg)
    }
}

// MARK: - Shared pieces

/// Threat as a five-segment meter plus its word: readable without relying on colour alone.
struct ThreatBadge: View {
    let threat: Threat

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1).fill(i < threat.bars ? threat.color : C.panel2).frame(width: 4, height: 10)
                }
            }
            Text(threat.label).font(.ui(11, .medium)).foregroundStyle(threat.color)
        }
    }
}

/// A text field for a pasted list, with Paste and the action button.
private struct PasteBox: View {
    let hint: LocalizedStringKey
    let action: LocalizedStringKey
    @Binding var text: String
    let run: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hint).font(.ui(12)).foregroundStyle(C.muted).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text)
                .font(.mono(12))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 90, maxHeight: 160)
                .padding(6)
                .background(C.card, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(C.border, lineWidth: 1))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            HStack(spacing: 8) {
                Button("Paste") {
                    if let s = UIPasteboard.general.string { text = s; run() }
                }
                .buttonStyle(.canopusGhost)
                Button(action) { run() }
                    .buttonStyle(.canopus)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !text.isEmpty {
                    Button("Clear") { text = "" }.buttonStyle(.canopusSmall)
                }
            }
        }
        .canopusSurface(padding: 12)
    }
}

// MARK: - Local

private struct LocalTab: View {
    @Environment(AppEnvironment.self) private var env
    @State private var text = ""
    @State private var pilots: [PilotIntel] = []
    @State private var unknown: [String] = []
    @State private var running = false
    @State private var scannedAt: Date?
    @State private var arrived: Set<Int> = []
    @State private var left: [String] = []
    @State private var filter: Int?
    @State private var error: Error?
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PasteBox(hint: "In the game: the Local window → Ctrl+A, Ctrl+C. On a Mac with Universal Clipboard it lands here: tap Paste. Or type names, one per line.",
                     action: "Check", text: $text, run: scan)
            if let error { Text(error.localizedDescription).font(.ui(12)).foregroundStyle(C.bad) }
            if scannedAt != nil { results }
        }
        #if DEBUG
        // Debug builds: `-intelLocal "Name;Name"` checks a list at once (screenshots).
        .task {
            if text.isEmpty, let list = UserDefaults.standard.string(forKey: "intelLocal") {
                text = list.replacingOccurrences(of: ";", with: "\n")
                scan()
            }
        }
        #endif
    }

    private func scan() {
        let names = IntelLogic.parseLocal(text)
        guard !names.isEmpty else { return }
        task?.cancel()
        let before = Dictionary(uniqueKeysWithValues: pilots.map { ($0.id, $0.name) })
        task = Task {
            running = true
            error = nil
            defer { running = false }
            let me = await myself()
            do {
                let r = try await IntelLogic.scan(names: names, me: me) { pilots = $0 }
                pilots = r.pilots
                unknown = r.unknown
                let now = Set(r.pilots.map(\.id))
                arrived = before.isEmpty ? [] : now.subtracting(before.keys)
                left = before.filter { !now.contains($0.key) }.map(\.value).sorted()
                scannedAt = Date()
            } catch {
                if !error.isCancellation { self.error = error }
            }
        }
        scannedAt = scannedAt ?? Date()
    }

    private func myself() async -> Me? {
        guard let svc = env.characterStore.selectedService else { return nil }
        let id = svc.tokens.characterId
        let info = await PublicESI.shared.character(id)
        return Me(id: id, corpId: info?.corporationId, allianceId: info?.allianceId)
    }

    private struct Group: Identifiable {
        let id: Int
        let isAlliance: Bool
        let ticker: String
        var count: Int
        var danger: Int
    }

    private var groups: [Group] {
        var m: [Int: Group] = [:]
        for p in pilots {
            guard let id = p.allianceId ?? p.corpId else { continue }
            var g = m[id] ?? Group(id: id, isAlliance: p.allianceId != nil, ticker: p.allianceTicker ?? p.corpTicker ?? "?", count: 0, danger: 0)
            g.count += 1
            if p.threat == .high || p.threat == .hostile { g.danger += 1 }
            m[id] = g
        }
        return m.values.sorted { $0.count > $1.count }
    }

    @ViewBuilder private var results: some View {
        let sorted = IntelLogic.sorted(pilots)
        let count = { (t: Threat) in pilots.filter { $0.threat == t }.count }
        let dangerous = count(.hostile) + count(.high)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            StatTile(label: "Pilots", value: "\(pilots.count)", sub: running ? String(localized: "checking…") : nil)
            StatTile(label: "Dangerous", value: "\(dangerous)", sub: String(localized: "hostile \(count(.hostile)) · dangerous \(count(.high)) · watch \(count(.medium))"),
                     valueColor: dangerous > 0 ? C.bad : C.good)
            StatTile(label: "Friendly", value: "\(count(.friendly))")
            StatTile(label: "Changes", value: "+\(arrived.count) / −\(left.count)",
                     sub: left.isEmpty ? String(localized: "since the last check") : String(localized: "left: \(left.prefix(4).joined(separator: ", "))"))
        }
        let gs = groups
        if gs.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(gs.prefix(16)) { g in
                        Button { filter = filter == g.id ? nil : g.id } label: {
                            HStack(spacing: 5) {
                                if g.isAlliance { EVEAllianceLogo(allianceId: g.id, size: 18) } else { EVECorpLogo(corpId: g.id, size: 18) }
                                Text(verbatim: g.ticker).font(.ui(12))
                                Text(verbatim: "\(g.count)").font(.mono(12, medium: true))
                                if g.danger > 0 { Text(verbatim: "⚠\(g.danger)").font(.ui(11)).foregroundStyle(C.bad) }
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(filter == g.id ? C.accentSoft : C.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(filter == g.id ? C.accentLine : C.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(C.text)
                    }
                }
            }
        }
        VStack(spacing: 0) {
            let shown = filter.map { f in sorted.filter { ($0.allianceId ?? $0.corpId) == f } } ?? sorted
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, p in
                if i > 0 { Rectangle().fill(C.border).frame(height: 1) }
                NavigationLink { PilotBoard(pilotId: p.id, name: p.name) } label: { PilotRow(p: p, isNew: arrived.contains(p.id)) }
                    .buttonStyle(.plain)
            }
        }
        .canopusSurface(padding: 10)
        if !unknown.isEmpty {
            Text("Not found: \(unknown.joined(separator: ", "))").font(.ui(12)).foregroundStyle(C.muted)
        }
        Text("Threat is an estimate from your corporation and alliance and zKillboard statistics. \"Dangerous\": an active PvP pilot (kills this week, or many over the last months with a high danger ratio). Tap a pilot for the full record.")
            .font(.ui(11)).foregroundStyle(C.faint)
    }
}

private struct PilotRow: View {
    let p: PilotIntel
    let isNew: Bool

    var body: some View {
        let z = p.zkb ?? nil
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                EVECharacterPortrait(characterId: p.id, size: 32).clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(verbatim: p.name).font(.ui(14, .medium)).foregroundStyle(C.text).lineLimit(1)
                        if isNew { Pill(text: "new", color: C.warn) }
                    }
                    HStack(spacing: 4) {
                        if let t = p.corpTicker { Text(verbatim: "[\(t)]").foregroundStyle(C.text2) }
                        if let t = p.allianceTicker { Text(verbatim: "<\(t)>").foregroundStyle(C.text2) }
                        Text(verbatim: p.allianceName ?? p.corpName ?? "").foregroundStyle(C.muted).lineLimit(1)
                    }
                    .font(.ui(11))
                }
                Spacer(minLength: 6)
                ThreatBadge(threat: p.threat)
            }
            HStack(spacing: 12) {
                if let b = p.birthday {
                    let years = Date().timeIntervalSince(b) / (365.25 * 86400)
                    stat("Age", years < 1 ? String(localized: "\(Int((years * 12).rounded())) mo") : String(format: "%.1f", years) + String(localized: " y"))
                }
                if p.zkb == nil {
                    stat("K / L", "…")
                } else if let z {
                    stat("K / L", "\(z.kills) / \(z.losses)")
                    stat("Activity", "\(z.activeWeek) / \(z.recentKills)")
                    stat("Danger", "\(z.danger)%" + (z.soloKills > 0 ? String(localized: " · solo \(z.soloKills)") : ""))
                } else {
                    stat("K / L", "—")
                }
                Spacer(minLength: 0)
                if let z {
                    HStack(spacing: 3) { ForEach(z.recentShips.prefix(3), id: \.typeId) { EVETypeIcon(typeId: $0.typeId, size: 22) } }
                }
            }
        }
        .padding(.vertical, 8)
        .background(isNew ? C.warn.opacity(0.06) : .clear)
        .contentShape(Rectangle())
    }

    private func stat(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.ui(9, .medium)).textCase(.uppercase).foregroundStyle(C.faint)
            Text(verbatim: value).font(.mono(11, medium: true)).foregroundStyle(C.text2)
        }
    }
}

// MARK: - D-scan

private let notableGroups: [Int: LocalizedStringKey] = [
    541: "Interdictors", 894: "Heavy interdictors", 833: "Force recons", 906: "Combat recons", 834: "Stealth bombers",
    832: "Logistics", 1527: "Logistics frigates", 898: "Black Ops", 547: "Carriers", 485: "Dreadnoughts",
    1538: "Force Auxiliaries", 659: "Supercarriers", 30: "Titans", 361: "Mobile warp disruptors",
]

private struct DscanTab: View {
    @Environment(AppEnvironment.self) private var env
    @State private var text = ""
    @State private var rows: [IntelLogic.ScanRow]?
    @State private var types: [Int: ItemType] = [:]
    @State private var groups: [Int: ItemGroup] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PasteBox(hint: "In the game: the directional scanner → Ctrl+A, Ctrl+C, then Paste here.", action: "Read", text: $text) {
                Task { await read() }
            }
            if let rows { summary(rows) }
        }
    }

    private func read() async {
        let r = IntelLogic.parseDscan(text)
        guard let repo = env.repository else { return }
        let t = (try? await repo.types(ids: Set(r.map(\.typeId)))) ?? [:]
        let g = (try? await repo.groups(ids: Set(t.values.map(\.groupId)))) ?? [:]
        types = t
        groups = g
        rows = r
    }

    @ViewBuilder private func summary(_ rows: [IntelLogic.ScanRow]) -> some View {
        let byType = rows.reduce(into: [Int: (total: Int, grid: Int)]()) { m, r in
            var e = m[r.typeId] ?? (0, 0)
            e.total += 1
            if let d = r.distanceKm, d <= IntelLogic.onGridKm { e.grid += 1 }
            m[r.typeId] = e
        }
        let isShip = { (id: Int) in types[id].flatMap { groups[$0.groupId] }?.categoryId == 6 }
        let ships = byType.keys.filter(isShip).sorted { byType[$0]!.total > byType[$1]!.total }
        let byGroup = ships.reduce(into: [Int: Int]()) { $0[types[$1]!.groupId, default: 0] += byType[$1]!.total }
        let shipCount = ships.reduce(0) { $0 + byType[$1]!.total }
        let notable = byGroup.filter { notableGroups[$0.key] != nil }.sorted { $0.value > $1.value }
        let others = byType.keys.filter { !isShip($0) }.sorted { byType[$0]!.total > byType[$1]!.total }

        if rows.isEmpty {
            Text("Nothing recognised: copy the scanner's results with Ctrl+A, Ctrl+C.").font(.ui(13)).foregroundStyle(C.muted)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                StatTile(label: "Objects", value: "\(rows.count)")
                StatTile(label: "Ships", value: "\(shipCount)", sub: String(localized: "on grid: \(ships.reduce(0) { $0 + byType[$1]!.grid })"))
                StatTile(label: "Ship types", value: "\(ships.count)")
            }
            if !notable.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(notable, id: \.key) { g, n in
                        HStack { Text(verbatim: "⚠"); Text(notableGroups[g]!); Text(verbatim: "\(n)").bold() }
                    }
                }
                .font(.ui(13)).foregroundStyle(C.bad)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(C.badFill.opacity(0.12), in: EVECut())
            }
            Card("Ships by class") {
                ForEach(byGroup.sorted { $0.value > $1.value }, id: \.key) { g, n in
                    HStack {
                        Text(verbatim: groups[g]?.name ?? "#\(g)").font(.ui(13)).foregroundStyle(C.text2)
                        Spacer()
                        Text(verbatim: "\(n)").font(.mono(13, medium: true)).foregroundStyle(C.text)
                    }
                }
            }
            Card("Ships by type") {
                ForEach(ships, id: \.self) { id in
                    HStack(spacing: 6) {
                        EVETypeIcon(typeId: id, size: 20)
                        Text(verbatim: types[id]?.name ?? "#\(id)").font(.ui(13)).foregroundStyle(C.text)
                        Spacer()
                        Text(verbatim: "\(byType[id]!.total)").font(.mono(13, medium: true))
                        Text(verbatim: byType[id]!.grid > 0 ? String(localized: "grid \(byType[id]!.grid)") : "").font(.ui(11)).foregroundStyle(C.muted).frame(width: 60, alignment: .trailing)
                    }
                }
            }
            if !others.isEmpty {
                Card("Other (structures, drones, objects)") {
                    ForEach(others, id: \.self) { id in
                        HStack(spacing: 6) {
                            EVETypeIcon(typeId: id, size: 18)
                            Text(verbatim: types[id]?.name ?? "#\(id)").font(.ui(12)).foregroundStyle(C.text2)
                            Spacer()
                            Text(verbatim: "×\(byType[id]!.total)").font(.mono(12)).foregroundStyle(C.muted)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Fleet

private struct FleetTab: View {
    @Environment(AppEnvironment.self) private var env
    @State private var text = ""
    @State private var rows: [(pilot: String, typeId: Int?)]?
    @State private var names: [Int: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PasteBox(hint: "In the game: the fleet window → select the members → Ctrl+C, then Paste here.", action: "Read", text: $text) {
                Task { await read() }
            }
            if let rows { composition(rows) }
        }
    }

    private func read() async {
        let lines = IntelLogic.parseFleet(text)
        let cells = Set(lines.flatMap { $0 }.filter { !$0.isEmpty && $0.count < 60 })
        let found = (try? await env.repository?.typesNamed(cells)) ?? [:]
        rows = lines.map { cols in
            let ship = cols.compactMap { found[$0.lowercased()] }.first { $0.category == 6 }
            return (cols[0], ship?.id)
        }
        names = Dictionary(found.compactMap { k, v in v.category == 6 ? (v.id, cells.first { $0.lowercased() == k } ?? k) : nil }, uniquingKeysWith: { a, _ in a })
    }

    @ViewBuilder private func composition(_ rows: [(pilot: String, typeId: Int?)]) -> some View {
        let counts = rows.compactMap(\.typeId).reduce(into: [Int: Int]()) { $0[$1, default: 0] += 1 }
        Card(String(localized: "Composition: \(rows.count) pilots")) {
            ForEach(counts.sorted { $0.value > $1.value }, id: \.key) { id, n in
                HStack(spacing: 6) {
                    EVETypeIcon(typeId: id, size: 20)
                    Text(verbatim: names[id] ?? "#\(id)").font(.ui(13)).foregroundStyle(C.text)
                    Spacer()
                    Text(verbatim: "\(n)").font(.mono(13, medium: true))
                }
            }
        }
        Card("Pilots") {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack {
                    Text(verbatim: r.pilot).font(.ui(13)).foregroundStyle(C.text)
                    Spacer()
                    Text(verbatim: r.typeId.flatMap { names[$0] } ?? "—").font(.ui(12)).foregroundStyle(C.muted)
                }
            }
        }
    }
}

// MARK: - Kill radar

private struct RadarTab: View {
    @Environment(AppEnvironment.self) private var env
    @State private var radar = RadarStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(radar.enabled ? "Radar on" : "Radar off") { radar.enabled.toggle() }
                        .buttonStyle(CanopusButtonStyle(kind: radar.enabled ? .primary : .ghost))
                    Spacer()
                    Text(status).font(.ui(12)).foregroundStyle(radar.error == nil ? C.muted : C.bad).multilineTextAlignment(.trailing)
                }
                HStack(spacing: 6) {
                    Text("Jumps around me:").font(.ui(12)).foregroundStyle(C.muted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach([0, 1, 2, 3, 5, 7, 10], id: \.self) { r in
                                Button(r == 0 ? String(localized: "here") : "\(r)") { radar.radius = r }
                                    .buttonStyle(CanopusButtonStyle(kind: radar.radius == r ? .primary : .ghost, small: true))
                            }
                        }
                    }
                }
                Button { radar.watchRoute.toggle() } label: {
                    HStack(spacing: 6) {
                        Text(verbatim: radar.watchRoute ? "✓" : " ").frame(width: 14)
                        Text("Also the route planned on the map")
                    }
                }
                .buttonStyle(.canopusSmall)
                Text("Player kills of the last hour from zKillboard's live feed, near your character (from ESI) and on the map's route. Gate camps, bubbles and smartbombs are marked. The radar runs while Canopus is open.")
                    .font(.ui(11)).foregroundStyle(C.faint)
            }
            .canopusSurface(padding: 12)
            if radar.kills.isEmpty {
                Text(radar.enabled ? "No kills around you in the last hour." : "Turn the radar on to follow kills around you.")
                    .font(.ui(13)).foregroundStyle(C.muted)
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    VStack(spacing: 8) {
                        ForEach(radar.kills) { RadarCard(k: $0, now: ctx.date) }
                    }
                }
            }
        }
        .onAppear { radar.attach(env) }
    }

    private var status: String {
        if let e = radar.error { return e }
        guard radar.enabled else { return "" }
        let place = radar.here.map { String(localized: "in \($0.name)") } ?? String(localized: "location unknown")
        return String(localized: "\(place) · watching \(radar.watchedCount) systems · \(radar.seen) kills checked")
    }
}

/// One kill as a card that reads at a glance (the desktop's RadarCard): the lost ship, where, how and by whom.
struct RadarCard: View {
    let k: RadarKill
    var now = Date()

    var body: some View {
        let danger = k.camp || k.bubbles || k.smartbombs
        let minutes = max(0, Int(now.timeIntervalSince(k.time) / 60))
        HStack(alignment: .top, spacing: 10) {
            Link(destination: URL(string: "https://zkillboard.com/kill/\(k.id)/")!) {
                EVETypeIcon(typeId: k.victimShip, size: 44)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(verbatim: k.victimShipName).font(.ui(14, .semibold)).foregroundStyle(C.text).lineLimit(1)
                    if let g = k.victimGroup { Text(verbatim: g).font(.ui(11)).foregroundStyle(C.muted).lineLimit(1) }
                    Spacer(minLength: 4)
                    Text(Fmt.isk(k.value)).font(.mono(11)).foregroundStyle(C.text2)
                    Text(minutes < 1 ? String(localized: "now") : String(localized: "\(minutes) min"))
                        .font(.ui(11, .medium)).foregroundStyle(minutes < 5 ? C.warn : C.muted)
                }
                HStack(spacing: 6) {
                    Text(String(format: "%.1f", C.roundSec(k.security))).font(.ui(12, .bold)).foregroundStyle(C.sec(k.security))
                    Text(verbatim: k.system).font(.ui(13, .medium)).foregroundStyle(C.text)
                    if let j = k.jumps {
                        Text(j == 0 ? String(localized: "HERE") : String(localized: "\(j) j."))
                            .font(.ui(11, .bold)).foregroundStyle(j == 0 ? C.bad : j == 1 ? C.warn : C.text2)
                    } else {
                        Text("on the route").font(.ui(11)).foregroundStyle(C.accentText)
                    }
                    if let g = k.gate { Text(verbatim: "⇢ \(g.toName)").font(.ui(11)).foregroundStyle(C.text2) }
                    if let o = k.victimOrg, !o.name.isEmpty {
                        Text(verbatim: o.name).font(.ui(11)).foregroundStyle(C.muted).lineLimit(1)
                    }
                }
                if danger {
                    HStack(spacing: 6) {
                        if k.camp { Pill(text: "GATE CAMP", color: C.bad, filled: true) }
                        if k.bubbles { Pill(text: "BUBBLES", color: C.warn, filled: true) }
                        if k.smartbombs { Pill(text: "SMARTBOMBS", color: Color(hex: 0xC77DFF), filled: true) }
                    }
                }
                HStack(spacing: 6) {
                    Text(verbatim: "⚔").foregroundStyle(C.muted)
                    ForEach(k.killers, id: \.org.id) { o, n in
                        HStack(spacing: 3) {
                            if o.isAlliance { EVEAllianceLogo(allianceId: o.id, size: 16) } else { EVECorpLogo(corpId: o.id, size: 16) }
                            Text(verbatim: o.name.isEmpty ? "—" : o.name).lineLimit(1)
                            if n > 1 { Text(verbatim: "×\(n)").foregroundStyle(C.muted) }
                        }
                    }
                    Text("\(k.attackers) pilots").foregroundStyle(C.muted)
                }
                .font(.ui(11)).foregroundStyle(C.text2)
                if !k.attackerTypes.isEmpty || !k.weapons.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(k.attackerTypes, id: \.id) { icon($0.id, $0.n) }
                        if !k.weapons.isEmpty { Rectangle().fill(C.border).frame(width: 1, height: 18).padding(.horizontal, 2) }
                        ForEach(k.weapons, id: \.id) { icon($0.id, $0.n) }
                    }
                }
            }
        }
        .padding(10)
        .background(danger ? C.badFill.opacity(0.08) : C.panel, in: EVECut())
        .overlay(EVECut().strokeBorder(danger ? C.bad.opacity(0.5) : C.border, lineWidth: 1))
    }

    private func icon(_ id: Int, _ n: Int) -> some View {
        EVETypeIcon(typeId: id, size: 22)
            .overlay(alignment: .bottomTrailing) {
                if n > 1 {
                    Text(verbatim: "\(n)").font(.ui(9, .bold)).foregroundStyle(C.text)
                        .padding(.horizontal, 2).background(C.bg.opacity(0.85), in: RoundedRectangle(cornerRadius: 2))
                }
            }
    }
}
