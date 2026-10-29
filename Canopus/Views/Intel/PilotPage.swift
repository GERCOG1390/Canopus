// The PvP page (the desktop's PvpPage.tsx): any pilot's zKillboard record — kills, losses, ISK efficiency,
// solo and danger — and their recent fights; a fight opens to the victim's fit and the attackers.

import SwiftUI
import Domain
import EVEAuth
import EVEStaticData

struct PilotPage: View {
    @Environment(AppEnvironment.self) private var env
    @State private var pilot: (id: Int, name: String)?
    @State private var search = ""
    @State private var searching = false
    @State private var notFound = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Glyph(name: .search, size: 14).foregroundStyle(C.muted)
                        TextField("Pilot name…", text: $search)
                            .font(.ui(14)).autocorrectionDisabled().textInputAutocapitalization(.never)
                            .onSubmit { Task { await find() } }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(C.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(C.border, lineWidth: 1))
                    Button("Find") { Task { await find() } }.buttonStyle(.canopusGhost).disabled(search.count < 3 || searching)
                    if let me = myself, pilot?.id != me.id {
                        Button("My character") { pilot = me }.buttonStyle(.canopusGhost)
                    }
                }
                if notFound { Text("No pilot with that exact name.").font(.ui(12)).foregroundStyle(C.muted) }
                if let pilot {
                    PilotBoardContent(pilotId: pilot.id, name: pilot.name).id(pilot.id)
                } else {
                    EmptyState("Find a pilot", icon: "win_killreport") { Text("Their statistics and recent fights from zKillboard.") }
                }
            }
            .padding(16)
        }
        .background(C.bg)
        .onAppear { if pilot == nil { pilot = myself } }
    }

    private var myself: (id: Int, name: String)? {
        env.characterStore.selectedService.map { ($0.tokens.characterId, $0.tokens.characterName) }
    }

    private func find() async {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3 else { return }
        searching = true
        defer { searching = false }
        let hits = (try? await PublicESI.shared.characterIds(names: [q])) ?? []
        notFound = hits.isEmpty
        if let h = hits.first { pilot = (h.id, h.name) }
    }
}

/// A pilot's record pushed from elsewhere (a Local check).
struct PilotBoard: View {
    let pilotId: Int
    let name: String

    var body: some View {
        ScrollView {
            PilotBoardContent(pilotId: pilotId, name: name).padding(16)
        }
        .background(C.bg)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PilotBoardContent: View {
    let pilotId: Int
    let name: String
    @Environment(AppEnvironment.self) private var env
    @State private var stats: ZKBCharacterStats??
    @State private var fights: [ZKBEntry] = []
    @State private var names: [Int: String] = [:]
    @State private var types: [Int: String] = [:]
    @State private var systems: [Int: (name: String, security: Double)] = [:]
    @State private var open: Int?
    @State private var error: Error?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error {
                Text(error.localizedDescription).font(.ui(13)).foregroundStyle(C.bad)
            } else if let loaded = stats {
                header(loaded)
                if let s = loaded { tiles(s) }
                fightsCard
            } else {
                HStack(spacing: 8) { ProgressView().tint(C.accent); Text("Asking zKillboard…").font(.ui(13)).foregroundStyle(C.muted) }
                    .padding(.top, 20)
            }
        }
        .task { await load() }
    }

    private func load() async {
        let esi = PublicESI.shared
        async let s = esi.zkbStats(pilotId)
        async let f = esi.zkbFights(pilotId)
        let loaded = await s
        do {
            fights = Array(try await f.prefix(40))
        } catch {
            if !error.isCancellation { fights = [] }
        }
        var ids = Set<Int>()
        for k in fights {
            ids.formUnion([k.victim?.characterId, k.victim?.corporationId].compactMap { $0 })
            ids.formUnion((k.attackers ?? []).prefix(30).compactMap(\.characterId))
        }
        ids.formUnion([loaded?.corporationId, loaded?.allianceId].compactMap { $0 })
        names = (try? await MarketService().names(ids: Array(ids))) ?? [:]
        if let repo = env.repository {
            var typeIds = Set<Int>()
            for k in fights {
                if let v = k.victim { typeIds.insert(v.shipTypeId); typeIds.formUnion((v.items ?? []).map(\.itemTypeId)) }
                typeIds.formUnion((k.attackers ?? []).flatMap { [$0.shipTypeId, $0.weaponTypeId].compactMap { $0 } })
            }
            types = ((try? await repo.types(ids: typeIds)) ?? [:]).mapValues(\.name)
            systems = (try? await repo.systems(ids: Set(fights.compactMap(\.solarSystemId)))) ?? [:]
        }
        stats = .some(loaded)
    }

    private func header(_ s: ZKBCharacterStats?) -> some View {
        HStack(spacing: 12) {
            EVECharacterPortrait(characterId: pilotId, size: 72).clipShape(EVECut())
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: name).font(.display(22)).foregroundStyle(C.text)
                if let c = s?.corporationId, c > 0 {
                    HStack(spacing: 5) {
                        EVECorpLogo(corpId: c, size: 18)
                        Text(verbatim: names[c] ?? "").font(.ui(13)).foregroundStyle(C.text2)
                        if let a = s?.allianceId, a > 0 {
                            Text(verbatim: "·").foregroundStyle(C.muted)
                            EVEAllianceLogo(allianceId: a, size: 18)
                            Text(verbatim: names[a] ?? "").font(.ui(13)).foregroundStyle(C.text2)
                        }
                    }
                }
                Link("Open on zKillboard", destination: URL(string: "https://zkillboard.com/character/\(pilotId)/")!)
                    .font(.ui(12)).foregroundStyle(C.accentText)
            }
            Spacer(minLength: 0)
        }
        .canopusSurface(padding: 12)
    }

    private func tiles(_ s: ZKBCharacterStats) -> some View {
        let total = s.iskDestroyed + s.iskLost
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            StatTile(label: "Destroyed", value: "\(s.kills)", sub: Fmt.isk(s.iskDestroyed))
            StatTile(label: "Lost", value: "\(s.losses)", sub: Fmt.isk(s.iskLost))
            StatTile(label: "ISK efficiency", value: total > 0 ? String(format: "%.1f%%", s.iskDestroyed / total * 100) : "—")
            StatTile(label: "Solo kills", value: "\(s.soloKills)", sub: String(localized: "Danger \(s.danger)% · in gangs \(s.gang)%"))
        }
    }

    private var fightsCard: some View {
        Card("Recent fights") {
            if fights.isEmpty {
                Text("No data on zKillboard.").font(.ui(13)).foregroundStyle(C.muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(fights.enumerated()), id: \.element.id) { i, k in
                        if i > 0 { Rectangle().fill(C.border).frame(height: 1) }
                        fightRow(k)
                        if open == k.killmailId { KillDetails(k: k, names: names, types: types) }
                    }
                }
            }
            Text("Data: zKillboard. Tap a fight for the victim's fit and the attackers.").font(.ui(11)).foregroundStyle(C.faint)
        }
    }

    private func fightRow(_ k: ZKBEntry) -> some View {
        let loss = k.victim?.characterId == pilotId
        let sys = k.solarSystemId.flatMap { systems[$0] }
        return Button { open = open == k.killmailId ? nil : k.killmailId } label: {
            HStack(spacing: 10) {
                Pill(text: loss ? "Loss" : "Kill", color: loss ? C.bad : C.good, filled: true)
                if let v = k.victim { EVETypeIcon(typeId: v.shipTypeId, size: 32) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: k.victim.flatMap { types[$0.shipTypeId] } ?? "—").font(.ui(13, .medium)).foregroundStyle(C.text).lineLimit(1)
                    Text(verbatim: k.victim?.characterId.flatMap { names[$0] } ?? "—").font(.ui(12)).foregroundStyle(C.text2).lineLimit(1)
                    if let sys {
                        HStack(spacing: 4) {
                            SecText(value: sys.security)
                            Text(verbatim: sys.name).font(.ui(12)).foregroundStyle(C.muted)
                        }
                    }
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.isk(k.zkb.totalValue ?? 0)).font(.mono(12, medium: true)).foregroundStyle(C.text)
                    Text("\(k.attackers?.count ?? 0) attackers\(k.zkb.solo == true ? String(localized: " · solo") : "")").font(.ui(11)).foregroundStyle(C.muted)
                    if let t = k.killmailTime { Text(t, format: .relative(presentation: .named)).font(.ui(11)).foregroundStyle(C.faint) }
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A fight opened: the victim's fit by slot and the attackers by damage.
private struct KillDetails: View {
    let k: ZKBEntry
    let names: [Int: String]
    let types: [Int: String]

    private static let slots: [(prefix: String, title: LocalizedStringKey)] = [
        ("HiSlot", "High slots"), ("MedSlot", "Mid slots"), ("LoSlot", "Low slots"), ("RigSlot", "Rig slots"),
        ("SubSystemSlot", "Subsystems"), ("DroneBay", "Drones"), ("Cargo", "Cargo"),
    ]

    var body: some View {
        let items = (k.victim?.items ?? []).compactMap { i -> (flag: String, id: Int, qty: Int)? in
            FitSpecBuilder.flagName(i.flag).map { ($0, i.itemTypeId, max(1, (i.quantityDestroyed ?? 0) + (i.quantityDropped ?? 0))) }
        }
        let attackers = (k.attackers ?? []).sorted { $0.damageDone > $1.damageDone }
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Self.slots, id: \.prefix) { slot in
                let list = items.filter { $0.flag.hasPrefix(slot.prefix) }
                if !list.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(slot.title).font(.ui(11, .medium)).textCase(.uppercase).foregroundStyle(C.muted)
                        ForEach(Array(list.enumerated()), id: \.offset) { _, i in
                            HStack(spacing: 6) {
                                EVETypeIcon(typeId: i.id, size: 18)
                                Text(verbatim: (i.qty > 1 ? "\(i.qty)× " : "") + (types[i.id] ?? "#\(i.id)")).font(.ui(12)).foregroundStyle(C.text2).lineLimit(1)
                            }
                        }
                    }
                }
            }
            Text("Attackers (\(attackers.count)) · damage \(k.victim?.damageTaken ?? 0)").font(.ui(11, .medium)).textCase(.uppercase).foregroundStyle(C.muted)
            ForEach(Array(attackers.prefix(30).enumerated()), id: \.offset) { _, a in
                HStack(spacing: 6) {
                    if a.finalBlow { Pill(text: "FB", color: C.good) }
                    Text(verbatim: a.characterId.flatMap { names[$0] } ?? "NPC").font(.ui(12)).foregroundStyle(a.characterId == nil ? C.muted : C.text).lineLimit(1)
                    Spacer(minLength: 4)
                    if let s = a.shipTypeId { EVETypeIcon(typeId: s, size: 18) }
                    if let w = a.weaponTypeId, w != a.shipTypeId { EVETypeIcon(typeId: w, size: 18) }
                    Text(verbatim: "\(a.damageDone)").font(.mono(11)).foregroundStyle(C.text2).frame(width: 56, alignment: .trailing)
                }
            }
            Link("Open on zKillboard", destination: URL(string: "https://zkillboard.com/kill/\(k.killmailId)/")!)
                .font(.ui(12)).foregroundStyle(C.accentText)
        }
        .padding(10)
        .background(C.card, in: RoundedRectangle(cornerRadius: 8))
        .padding(.bottom, 8)
    }
}
