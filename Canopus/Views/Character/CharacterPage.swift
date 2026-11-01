// The character page as the desktop's character/index.tsx: one page with tabs — every character at a
// glance, the overview, skills, clones and implants, ship and fits, assets, wallet and contracts.

import SwiftUI
import Domain
import EVEAuth
import EVEStaticData

enum CharacterTab: String, CaseIterable {
    case all, overview, skills, plan, clones, fits, assets, blueprints, wallet, contracts, reputation

    var label: String {
        switch self {
        case .all: "All characters"
        case .overview: "Overview"
        case .skills: "Skills"
        case .plan: "Skill plan"
        case .clones: "Implants & clones"
        case .fits: "Ship & fits"
        case .assets: "Assets"
        case .blueprints: "Blueprints"
        case .wallet: "Wallet"
        case .contracts: "Contracts"
        case .reputation: "Reputation"
        }
    }
}

struct CharacterPage: View {
    @Environment(AppEnvironment.self) private var env
    @State var tab: CharacterTab

    init(tab: CharacterTab = {
        #if DEBUG
        if let t = UserDefaults.standard.string(forKey: "charTab").flatMap(CharacterTab.init(rawValue:)) { return t }
        #endif
        return .overview
    }()) {
        _tab = State(initialValue: tab)
    }

    /// Tabs worth showing: "all characters" only with more than one.
    private var tabs: [CharacterTab] {
        CharacterTab.allCases.filter { $0 != .all || env.characterStore.characters.count > 1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CanopusTabs(tabs: tabs.map { (id: $0, label: $0.label) }, selection: $tab)
                .padding(.horizontal, 12).padding(.vertical, 8)
            if let s = env.characterStore.selectedService {
                Group {
                    switch tab {
                    case .all: AllCharacters { tab = .overview }
                    case .overview: CharacterRootView(openTab: { tab = $0 })
                    case .skills: SkillsView()
                    case .plan: SkillPlannerTab(characterService: s)
                    case .clones: CloneView(characterService: s)
                    case .fits: FittingsView(characterService: s)
                    case .assets: AssetsTab(characterService: s)
                    case .wallet: WalletTab(characterService: s)
                    case .contracts: ContractsTab(characterService: s)
                    case .blueprints: BlueprintsTab(characterService: s)
                    case .reputation: ReputationTab(characterService: s)
                    }
                }
                .id(s.tokens.characterId)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .background(C.bg)
        .navigationTitle("Character")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - All characters (the desktop's AllCharacters.tsx)

/// Every logged-in character on one screen: where they are and in what, the skill queue, ISK, industry,
/// jump fatigue and the clone jump timer. Each part may fail on its own (a missing scope).
private struct CharacterRow: Identifiable {
    let id: Int
    let name: String
    var online: Bool?
    var system: (name: String, sec: Double)?
    var docked: Bool?
    var ship: (type: Int, name: String)?
    /// End of the last skill; nil inside = the queue is empty
    var queueEnd: Date??
    var wallet: Double?
    var jobs: (active: Int, ready: Int)?
    var fatigueEnd: Date??
    var cloneReady: Date??
}

private let infomorphSynchronizing = 33399

struct AllCharacters: View {
    let onOpen: () -> Void
    @Environment(AppEnvironment.self) private var env
    @State private var rows: [CharacterRow] = []
    @State private var loading = false
    @State private var shipNames: [Int: String] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let total = rows.reduce(0) { $0 + ($1.wallet ?? 0) }
                Card(title: String(localized: "All characters: \(env.characterStore.characters.count)"), actions: {
                    Button(loading ? "Refreshing…" : "Refresh") { Task { await load() } }
                        .buttonStyle(.canopusSmall).disabled(loading)
                }) {
                    if rows.isEmpty, loading { ProgressView().tint(C.accent).frame(maxWidth: .infinity) }
                    ForEach(rows) { r in
                        Button {
                            env.characterStore.selectedId = r.id
                            onOpen()
                        } label: { row(r) }
                        .buttonStyle(.plain)
                        if r.id != rows.last?.id { Rectangle().fill(C.border).frame(height: 1) }
                    }
                    if total > 0 {
                        Text("Total ISK: \(Fmt.isk(total))").font(.ui(12)).foregroundStyle(C.muted)
                    }
                }
            }
            .padding(16)
        }
        .task(id: env.characterStore.characters.map(\.characterId)) { await load() }
    }

    private func row(_ r: CharacterRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                EVECharacterPortrait(characterId: r.id, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(verbatim: r.name).font(.ui(14, .semibold)).foregroundStyle(r.id == env.characterStore.selectedId ? C.accentText : C.text)
                        if r.online == true { Circle().fill(C.good).frame(width: 7, height: 7) }
                    }
                    HStack(spacing: 4) {
                        if let s = r.system {
                            Text(verbatim: String(format: "%.1f", s.sec)).foregroundStyle(C.sec(s.sec))
                            Text(verbatim: s.name).foregroundStyle(C.text)
                            Text(r.docked == true ? "docked" : "in space").foregroundStyle(C.muted)
                        } else {
                            Text(verbatim: "—").foregroundStyle(C.muted)
                        }
                    }
                    .font(.ui(12))
                }
                Spacer(minLength: 6)
                if let ship = r.ship {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(verbatim: shipNames[ship.type] ?? "").font(.ui(12)).foregroundStyle(C.text).lineLimit(1)
                        Text(verbatim: ship.name).font(.ui(11)).foregroundStyle(C.muted).lineLimit(1)
                    }
                    EVETypeIcon(typeId: ship.type, size: 30)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 6) {
                fact("Skill queue", queueText(r), r.queueEnd.map { $0 == nil } == true ? C.warn : C.text)
                fact("Wallet", r.wallet.map { Fmt.isk($0) } ?? "—", C.text)
                fact("Industry", r.jobs.map { $0.ready > 0 ? String(localized: "\($0.active) active, \($0.ready) ready") : String(localized: "\($0.active) active") } ?? "—",
                     (r.jobs?.ready ?? 0) > 0 ? C.good : C.text)
                fact("Jump fatigue", timer(r.fatigueEnd), C.text)
                fact("Clone jump", r.cloneReady.map { $0.map { $0 > Date() ? Fmt.duration(until: $0) : String(localized: "ready") } ?? String(localized: "ready") } ?? "—", C.text)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func fact(_ label: LocalizedStringKey, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.ui(10, .medium)).textCase(.uppercase).tracking(1).foregroundStyle(C.muted)
            Text(verbatim: value).font(.mono(12)).foregroundStyle(color).lineLimit(1)
        }
    }

    private func queueText(_ r: CharacterRow) -> String {
        guard let end = r.queueEnd else { return "—" }
        guard let end else { return String(localized: "empty") }
        return Fmt.duration(until: end)
    }

    private func timer(_ t: Date??) -> String {
        guard let t else { return "—" }
        guard let t, t > Date() else { return String(localized: "none") }
        return Fmt.duration(until: t)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let services = env.characterStore.services
        var out: [CharacterRow] = []
        await withTaskGroup(of: CharacterRow.self) { group in
            for s in services { group.addTask { await Self.loadRow(s) } }
            for await r in group { out.append(r) }
        }
        rows = services.compactMap { s in out.first { $0.id == s.tokens.characterId } }
        let types = Set(rows.compactMap { $0.ship?.type })
        shipNames = ((try? await env.repository?.types(ids: types)) ?? [:]).mapValues(\.name)
    }

    private static func loadRow(_ s: CharacterService) async -> CharacterRow {
        async let online = try? s.online()
        async let location = try? s.location()
        async let ship = try? s.currentShip()
        async let queue = try? s.skillQueue()
        async let wallet = try? s.wallet()
        async let jobs = try? s.industryJobs()
        async let fatigue = try? s.fatigue()
        async let clones = try? s.clones()
        async let skills = try? s.skills()
        var r = CharacterRow(id: s.tokens.characterId, name: s.tokens.characterName)
        r.online = await online?.online
        if let loc = await location {
            r.docked = loc.stationId != nil || loc.structureId != nil
            if let sys = try? await s.systemInfo(id: loc.solarSystemId) { r.system = (sys.name, sys.securityStatus ?? 0) }
        }
        if let sh = await ship { r.ship = (sh.shipTypeId, sh.shipName) }
        if let q = await queue {
            r.queueEnd = .some(q.compactMap(\.finishDate).filter { $0 > Date() }.max())
        }
        r.wallet = await wallet
        if let j = await jobs {
            let active = j.filter { $0.status == "active" }
            r.jobs = (active.count, active.filter { $0.endDate <= Date() }.count)
        }
        if let f = await fatigue { r.fatigueEnd = .some(f.jumpFatigueExpireDate) }
        if let c = await clones {
            let sync = await skills?.skills.first { $0.skillId == infomorphSynchronizing }?.activeSkillLevel ?? 0
            r.cloneReady = .some(c.lastCloneJumpDate.map { $0.addingTimeInterval(Double(24 - sync) * 3600) })
        }
        return r
    }
}
