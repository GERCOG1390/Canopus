// The fitting screen's tools tab: the price optimizer and the abyss planner laid out as on the desktop
// (FitOptimize.tsx, FitAbyss.tsx), and damage against mission NPCs (the desktop engine's npc.ts, which the
// desktop's assistant uses). All numbers come from the bundled desktop engine.

import SwiftUI
import Domain
import EVEAuth
import EVEStaticData

enum FitToolKind: String, CaseIterable {
    case learn, optimize, abyss, npc, compare, popular

    var label: String {
        switch self {
        case .learn: "What to learn"
        case .optimize: "Price optimizer"
        case .abyss: "Abyss"
        case .npc: "Mission NPCs"
        case .compare: "Compare fits"
        case .popular: "Popular fits"
        }
    }
}

/// What a tool needs from the fit screen.
struct FitToolContext {
    let spec: JSFitSpec
    let skills: JSSkills
    /// The pilot's levels; nil when the stats use all skills at V.
    let levels: [Int: Int]?
    let typeName: (Int) -> String
    /// Replaces every fitted module (or drone stack) of each `from` type with `to`.
    let apply: ([(from: Int, to: Int, isDrone: Bool)]) -> Void
    let service: CharacterService
    /// Opens another fit (a popular one from zKillboard) in the fitting screen.
    let openFit: (ESIFitting) -> Void

    /// Changes when the fit or the skills do (sorted keys: JSONEncoder's key order is not stable).
    var key: String {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return String(decoding: (try? e.encode(spec)) ?? Data(), as: UTF8.self) + skills.json
    }
}

struct FitToolsView: View {
    let context: FitToolContext
    @State private var tool: FitToolKind = {
        #if DEBUG
        // Debug builds: `-fitTool abyss` opens a tool (screenshots, UI checks).
        if let t = UserDefaults.standard.string(forKey: "fitTool").flatMap(FitToolKind.init(rawValue:)) { return t }
        #endif
        return .learn
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CanopusTabs(tabs: FitToolKind.allCases.map { (id: $0, label: $0.label) }, selection: $tool)
            switch tool {
            case .optimize: FitOptimizeView(context: context)
            case .abyss: FitAbyssView(context: context)
            case .npc: FitNpcView(context: context)
            case .learn: FitLearnView(context: context)
            case .compare: FitCompareView(context: context)
            case .popular: FitPopularView(context: context)
            }
        }
    }
}

// MARK: - Shared pieces

private func n0(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0))) }
private func n1(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1))) }

/// "1:23", "45 s", "∞" for a fight that never ends.
private func seconds(_ s: Double?) -> String {
    guard let s, s.isFinite else { return "∞" }
    if s >= 60 { return "\(Int(s) / 60):" + String(format: "%02d", Int(s.rounded()) % 60) }
    return String(localized: "\(n0(s)) s")
}

/// A row of choice chips (the desktop's `.chip-btn`).
private struct Chips<ID: Hashable>: View {
    let options: [(id: ID, label: String)]
    @Binding var selection: ID

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(options, id: \.id) { o in
                    let on = o.id == selection
                    Button { selection = o.id } label: {
                        Text(LocalizedStringKey(o.label))
                            .font(.ui(13))
                            .foregroundStyle(on ? C.accentText : C.text2)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(on ? C.accentSoft : C.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(on ? C.accentLine : C.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct Note: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        Text(text).font(.ui(12)).foregroundStyle(C.faint).fixedSize(horizontal: false, vertical: true)
    }
}

private struct Loading: View {
    let label: LocalizedStringKey
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().tint(C.accent)
            Text(label).font(.ui(13)).foregroundStyle(C.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}

private struct ErrorLine: View {
    let error: Error
    var body: some View {
        Text("⚠ " + error.localizedDescription).font(.ui(13)).foregroundStyle(C.bad)
    }
}

/// One type with its icon, "3× " in front when several.
private struct TypeLine: View {
    let typeId: Int
    let name: String
    var count = 1

    var body: some View {
        HStack(spacing: 6) {
            EVETypeIcon(typeId: typeId, size: 20)
            Text(verbatim: (count > 1 ? "\(count)× " : "") + name)
                .font(.ui(13)).foregroundStyle(C.text).lineLimit(2)
        }
    }
}

// MARK: - Price optimizer

private struct FitOptimizeView: View {
    let context: FitToolContext
    @Environment(AppEnvironment.self) private var env

    private enum Mode: Hashable { case cheaper, better }
    @State private var mode: Mode = {
        #if DEBUG
        // Debug builds: `-optimizerMode better` (screenshots).
        if UserDefaults.standard.string(forKey: "optimizerMode") == "better" { return .better }
        #endif
        return .cheaper
    }()
    @State private var tol = 0.0
    @State private var metric: OptimizerMetric = .dps
    @State private var budget = 200e6
    @State private var data: OptimizerData?
    @State private var error: Error?
    @State private var cheaper: (picks: [(v: FitVariant, saving: Double)], combined: FitMetrics?)?
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chips(options: [(Mode.cheaper, "Cheaper for the same numbers"), (Mode.better, "Better for extra ISK")], selection: $mode)
            if let error {
                ErrorLine(error: error)
            } else if let d = data {
                if mode == .cheaper { cheaperView(d) } else { betterView(d) }
                let skipped = d.options.filter(\.missingSkills).count
                if skipped > 0, context.levels != nil {
                    Note("\(skipped) versions not offered: the pilot lacks the skills.")
                }
            } else {
                Loading(label: "Trying module versions and Jita prices…")
            }
        }
        .task(id: specKey) { await load() }
        .task(id: "\(specKey)-\(tol)-\(data == nil)") { await checkCheaper() }
    }

    private var specKey: String { context.key }

    private func load() async {
        data = nil
        error = nil
        cheaper = nil
        guard let dogma = env.dogma, let repo = env.repository else { return }
        do {
            data = try await FitOptimizer.load(spec: context.spec, skills: context.skills, levels: context.levels, dogma: dogma, repo: repo)
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }

    private func checkCheaper() async {
        guard let d = data, let dogma = env.dogma else { return }
        checking = true
        defer { checking = false }
        cheaper = try? await FitOptimizer.findCheaper(d, spec: context.spec, skills: context.skills, tol: tol, dogma: dogma)
    }

    @ViewBuilder private func cheaperView(_ d: OptimizerData) -> some View {
        HStack(spacing: 6) {
            Text("Allowed loss:").font(.ui(12)).foregroundStyle(C.muted)
            Chips(options: [(0.0, String(localized: "none")), (0.02, "≤ 2%"), (0.05, "≤ 5%"), (0.1, "≤ 10%")], selection: $tol)
        }
        if checking || cheaper == nil {
            Loading(label: "Checking the swaps together…")
        } else if let c = cheaper, !c.picks.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(c.picks.enumerated()), id: \.offset) { i, p in
                    if i > 0 { Rectangle().fill(C.border).frame(height: 1) }
                    swapRow(p.v, d: d) {
                        Text(Fmt.isk(p.saving)).font(.mono(13, medium: true)).foregroundStyle(C.good)
                    } note: {
                        FitOptimizer.sideEffects(p.v.metrics, d.base)
                    }
                }
            }
            .canopusSurface(nested: true, padding: 10)
            VStack(alignment: .leading, spacing: 8) {
                Text("Saving in all: \(Fmt.isk(c.picks.reduce(0) { $0 + $1.saving }))")
                    .font(.ui(15, .semibold)).foregroundStyle(C.good)
                if let m = c.combined {
                    let effects = FitOptimizer.sideEffects(m, d.base)
                    Text(effects.isEmpty ? String(localized: "The numbers stay the same") : effects)
                        .font(.ui(12)).foregroundStyle(C.muted)
                }
                Button("Apply all swaps") {
                    context.apply(c.picks.map { ($0.v.from, $0.v.to, $0.v.isDrone) })
                }
                .buttonStyle(.canopus)
            }
        } else {
            Note("Nothing cheaper without losses: every module is already the cheapest version with these numbers.")
        }
        Note("Compared: weapon damage, range and application, EHP, active tank, speed, align, signature, targeting range and resolution, capacitor; the fit must still fit CPU, powergrid and calibration. Prices are the lowest Jita sell orders.")
    }

    @ViewBuilder private func betterView(_ d: OptimizerData) -> some View {
        Chips(options: OptimizerMetric.allCases.map { ($0, $0.label) }, selection: $metric)
        HStack(spacing: 6) {
            Text("Extra per swap:").font(.ui(12)).foregroundStyle(C.muted)
            Chips(options: [(50e6, "≤ 50M"), (200e6, "≤ 200M"), (1e9, "≤ 1B"), (Double.infinity, String(localized: "any"))], selection: $budget)
        }
        let rows = FitOptimizer.findUpgrades(d, metric: metric, budget: budget)
        if rows.isEmpty {
            Note("Within these limits no other version improves this without noticeable losses elsewhere.")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    if i > 0 { Rectangle().fill(C.border).frame(height: 1) }
                    swapRow(r.v, d: d) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(FitOptimizer.pct(r.gain)).font(.mono(13, medium: true)).foregroundStyle(C.good)
                            Text(r.cost <= 0 ? String(localized: "\(Fmt.isk(-r.cost)) cheaper") : Fmt.isk(r.cost))
                                .font(.mono(11)).foregroundStyle(r.cost <= 0 ? C.good : C.muted)
                        }
                    } note: {
                        FitOptimizer.sideEffects(r.v.metrics, d.base, skip: metric)
                    } action: {
                        Button("Swap") { context.apply([(r.v.from, r.v.to, r.v.isDrone)]) }
                            .buttonStyle(.canopusSmall)
                    }
                }
            }
            .canopusSurface(nested: true, padding: 10)
        }
        Note("Each line swaps all modules of that type; the most gain per million ISK first. Swaps that break the fit's resources or cost more than 3% elsewhere are left out. Prices are the lowest Jita sell orders.")
    }

    private func swapRow<Value: View, Action: View>(_ v: FitVariant, d: OptimizerData, @ViewBuilder value: () -> Value, note: () -> String, @ViewBuilder action: () -> Action = { EmptyView() }) -> some View {
        let effects = note()
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    TypeLine(typeId: v.from, name: d.names[v.from] ?? context.typeName(v.from), count: v.count).opacity(0.6)
                    HStack(spacing: 4) {
                        Text(verbatim: "→").foregroundStyle(C.muted)
                        TypeLine(typeId: v.to, name: d.names[v.to] ?? context.typeName(v.to))
                    }
                }
                Spacer(minLength: 8)
                value()
            }
            HStack {
                Text(effects.isEmpty ? String(localized: "no changes") : effects)
                    .font(.ui(11)).foregroundStyle(C.muted).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                action()
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Abyss planner

private let tierNames = ["Tranquil", "Calm", "Agitated", "Fierce", "Raging", "Chaotic", "Cataclysmic"]
private let damageShort = ["EM", "Th", "Kin", "Exp"]

private extension AbyssWeather {
    var label: String {
        switch self {
        case .electrical: "Electrical: EM hole"
        case .dark: "Dark: turret range"
        case .exotic: "Exotic: kinetic hole"
        case .firestorm: "Firestorm: thermal hole"
        case .gamma: "Gamma: explosive hole"
        }
    }

    var bonus: LocalizedStringKey {
        switch self {
        case .electrical: "Bonus: capacitor recharges twice as fast (NPCs too)."
        case .dark: "Bonus: +50% max velocity (NPCs too, when they chase)."
        case .exotic: "Bonus: +50% scan resolution (NPCs too)."
        case .firestorm: "Bonus: +50% armor HP (NPCs too)."
        case .gamma: "Bonus: +50% shield HP (NPCs too)."
        }
    }

    /// The damage type whose resistance the weather cuts.
    var hole: Int? {
        switch self {
        case .electrical: 0
        case .firestorm: 1
        case .exotic: 2
        case .gamma: 3
        case .dark: nil
        }
    }
}

private let abyssFactionLabel: [String: String] = [
    "triglavian": "Triglavians", "drifter": "Drifters", "sleeper": "Sleepers", "rogue_drone": "Rogue drones",
    "sansha": "Sansha", "angel": "Angels", "edencom": "EDENCOM",
]
private let ewarLabel: [String: String] = [
    "web": "web", "paint": "painter", "scram": "scram", "damp": "damp", "track": "tracking disruption",
    "guide": "guidance disruption", "remote": "repairs others", "chain": "chain lightning",
]
private let layerLabel: [String: String] = ["shield": "shield", "armor": "armor", "hull": "hull"]

private struct FitAbyssView: View {
    let context: FitToolContext
    @Environment(AppEnvironment.self) private var env
    @State private var weather: AbyssWeather = .electrical
    @State private var tier = 4
    @State private var strengthPick: Int?
    @State private var faction = "triglavian"
    @State private var report: AbyssReport?
    @State private var error: Error?

    /// The worse roll of the tier unless one is chosen.
    private var strength: Int {
        let s = AbyssWeather.strengths(tier: tier)
        if let p = strengthPick, p == s.0 || p == s.1 { return p }
        return s.1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chips(options: AbyssWeather.allCases.map { ($0, $0.label) }, selection: $weather)
            Chips(options: tierNames.indices.map { ($0, "T\($0) \(tierNames[$0])") }, selection: $tier)
            HStack(spacing: 6) {
                Text("Penalty:").font(.ui(12)).foregroundStyle(C.muted)
                let s = AbyssWeather.strengths(tier: tier)
                Chips(options: [(s.0, "−\(s.0)%"), (s.1, "−\(s.1)%")], selection: Binding(get: { strength }, set: { strengthPick = $0 }))
            }
            Note(weather.bonus)
            Note("The penalty strength is random: 30% or 50% through T3, 50% or 70% from T4. The worse one is the default.")
            if let error {
                ErrorLine(error: error)
            } else if let r = report {
                comparison(r)
                factionView(r)
                Note("Per NPC, not per room: the game data has no room spawns. NPC damage is on paper (every shot hits, disintegrators spooled up); \"hits you for\" is after your resists in the weather. The weather applies to NPCs too: their resist hole and HP bonus are counted. Kill time: no travel or reload, NPC self-repair counted.")
            } else {
                Loading(label: "Calculating the fit in the weather…")
            }
        }
        .task(id: "\(weather.rawValue)-\(strength)-\(context.key)") { await load() }
    }

    private func load() async {
        report = nil
        error = nil
        guard let dogma = env.dogma else { return }
        do {
            report = try await dogma.abyssPlan(context.spec, skills: context.skills, weather: weather, strength: strength)
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }

    private func cap(_ s: AbyssReport.Side) -> String {
        s.capStable ? "\(n0((s.capLevel ?? 0) * 100))%" : seconds(s.capLasts)
    }

    private func comparison(_ r: AbyssReport) -> some View {
        let rows: [(LocalizedStringKey, String, Text, Bool)] = [
            ("EHP", n0(r.normal.ehp), Text(n0(r.inWeather.ehp)), false),
            ("Repair, HP/s", n1(r.normal.repair), Text(n1(r.inWeather.repair)), false),
            ("Capacitor", cap(r.normal), Text(cap(r.inWeather)), false),
            ("Damage (DPS)", n0(r.normal.dps), Text(n0(r.inWeather.dps)), false),
            ("Weapon range, km", n1(r.normal.reach / 1000), Text(n1(r.inWeather.reach / 1000)), r.inWeather.reach < r.normal.reach - 1),
            ("Speed, m/s", n0(r.normal.speed), Text(n0(r.inWeather.speed)), false),
        ]
        return VStack(spacing: 7) {
            HStack {
                Spacer()
                Text("Normal space").frame(width: 110, alignment: .trailing)
                Text("In the weather").frame(width: 110, alignment: .trailing)
            }
            .font(.ui(11, .medium)).foregroundStyle(C.muted)
            HStack(alignment: .firstTextBaseline) {
                Text("Resists (\(String(localized: String.LocalizationValue(layerLabel[r.layer] ?? r.layer))))").font(.ui(13)).foregroundStyle(C.text2)
                Spacer(minLength: 4)
                Text(verbatim: r.normal.resist.map { n0($0 * 100) }.joined(separator: "/")).frame(width: 110, alignment: .trailing)
                r.inWeather.resist.enumerated().reduce(Text(verbatim: "")) { acc, e in
                    acc + Text(verbatim: (e.offset > 0 ? "/" : "") + n0(e.element * 100)).foregroundColor(e.offset == weather.hole ? C.bad : C.text)
                }
                .frame(width: 110, alignment: .trailing)
            }
            .font(.mono(12))
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.0).font(.ui(13)).foregroundStyle(C.text2)
                    Spacer(minLength: 4)
                    Text(verbatim: row.1).frame(width: 110, alignment: .trailing).foregroundStyle(C.text)
                    row.2.frame(width: 110, alignment: .trailing).foregroundStyle(row.3 ? C.bad : C.text)
                }
                .font(.mono(12))
            }
        }
        .canopusSurface(nested: true, padding: 10)
    }

    @ViewBuilder private func factionView(_ r: AbyssReport) -> some View {
        let f = r.factions.first { $0.faction == faction } ?? r.factions.first
        CanopusTabs(tabs: r.factions.map { (id: $0.faction, label: abyssFactionLabel[$0.faction] ?? $0.faction) },
                    selection: Binding(get: { f?.faction ?? faction }, set: { faction = $0 }))
        if let f {
            VStack(alignment: .leading, spacing: 4) {
                Text("Median kill time: **\(seconds(f.ttkMedian))**").font(.ui(13)).foregroundStyle(C.text2)
                (Text("The most dangerous hits for ") + Text(n0(f.worstTaken)).bold().foregroundColor(f.worstTaken > r.inWeather.repair ? C.bad : C.good)
                    + Text(" DPS through your resists; you repair \(n0(r.inWeather.repair)) HP/s"))
                    .font(.ui(13)).foregroundStyle(C.text2)
            }
            VStack(spacing: 0) {
                ForEach(Array(f.npcs.enumerated()), id: \.offset) { i, n in
                    if i > 0 { Rectangle().fill(C.border).frame(height: 1) }
                    npcRow(n, repair: r.inWeather.repair)
                }
            }
            .canopusSurface(nested: true, padding: 10)
        }
    }

    private func npcRow(_ n: AbyssReport.Npc, repair: Double) -> some View {
        let total = n.types.reduce(0, +)
        let types = total > 0
            ? n.types.enumerated().filter { $0.element / total >= 0.15 }.map { "\(String(localized: String.LocalizationValue(damageShort[$0.offset]))) \(n0($0.element / total * 100))%" }.joined(separator: " · ")
            : "—"
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: n.name).font(.ui(13, .medium)).foregroundStyle(C.text).lineLimit(2)
                Spacer(minLength: 8)
                Text(verbatim: "\(n0(n.hp)) HP").font(.mono(11)).foregroundStyle(C.muted)
            }
            HStack(spacing: 12) {
                stat("Kill time", seconds(n.ttk), bad: !(n.ttk?.isFinite ?? false))
                stat("Hits", "\(n0(min(1, n.application) * 100))%", bad: n.application < 0.5)
                stat("Hits you", n0(n.taken), bad: n.taken > repair)
                if n.neut > 0 { stat("Neut, GJ/s", n1(n.neut), bad: n.neut >= 10) }
            }
            Text(verbatim: ([types] + n.ewar.map { String(localized: String.LocalizationValue(ewarLabel[$0] ?? $0)) }).joined(separator: " · "))
                .font(.ui(11)).foregroundStyle(C.muted)
        }
        .padding(.vertical, 7)
    }

    private func stat(_ label: LocalizedStringKey, _ value: String, bad: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.ui(10, .medium)).textCase(.uppercase).foregroundStyle(C.faint)
            Text(verbatim: value).font(.mono(12, medium: true)).foregroundStyle(bad ? C.bad : C.text)
        }
    }
}

// MARK: - Mission NPCs

private let npcFactionLabel: [NpcFaction: String] = [
    .guristas: "Guristas", .serpentis: "Serpentis", .blood_raiders: "Blood Raiders", .sansha: "Sansha's Nation",
    .angel: "Angel Cartel", .rogue_drones: "Rogue drones", .amarr: "Amarr Empire", .caldari: "Caldari State",
    .gallente: "Gallente Federation", .minmatar: "Minmatar Republic", .khanid: "Khanid", .thukker: "Thukker",
    .mordu: "Mordu's Legion", .concord: "CONCORD",
]
private let npcClassLabel: [String: String] = [
    "frigate": "Frigates", "destroyer": "Destroyers", "cruiser": "Cruisers", "battlecruiser": "Battlecruisers", "battleship": "Battleships",
]
/// The engine names what holds damage back in Russian (combat.ts application).
private let limitLabel: [String: String] = [
    "наводка": "tracking", "фоллоф": "falloff", "вне дальности": "out of range", "радиус взрыва": "explosion radius",
    "скорость взрыва": "explosion velocity", "вне дальности полёта": "beyond missile flight range",
    "цель уходит от ракет": "target outruns the missiles", "цель быстрее дронов": "target faster than the drones",
    "вне радиуса смартбомбы": "outside smartbomb radius",
]

private struct FitNpcView: View {
    let context: FitToolContext
    @Environment(AppEnvironment.self) private var env
    @State private var faction: NpcFaction = .guristas
    @State private var report: NpcReport?
    @State private var error: Error?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chips(options: NpcFaction.allCases.map { ($0, npcFactionLabel[$0] ?? $0.rawValue) }, selection: $faction)
            if let error {
                ErrorLine(error: error)
            } else if let r = report {
                if let room = r.room.seconds {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("A typical level 4 room: \(seconds(room))").font(.ui(15, .semibold)).foregroundStyle(C.text)
                        Text("4 frigates, 2 destroyers, 4 cruisers, 2 battlecruisers, 4 battleships at the medians · paper DPS \(n1(r.paperDps)) · weapon reach \(n1(r.weaponReach / 1000)) km")
                            .font(.ui(12)).foregroundStyle(C.muted)
                    }
                }
                VStack(spacing: 0) {
                    ForEach(Array(r.classes.enumerated()), id: \.offset) { i, c in
                        if i > 0 { Rectangle().fill(C.border).frame(height: 1) }
                        classRow(c)
                    }
                }
                .canopusSurface(nested: true, padding: 10)
                Note("Sustained DPS without reloads, travel between targets or missile flight time. Each NPC orbits at its cruise speed at its orbit distance, or closer when your weapons reach less far (you fly in: \"approach\" marks classes that orbit beyond your weapons). NPC self-repairs are counted. For comparing fits, not a stopwatch.")
            } else {
                Loading(label: "Applying the fit's weapons to the NPCs…")
            }
        }
        .task(id: "\(faction.rawValue)-\(context.key)") { await load() }
    }

    private func load() async {
        report = nil
        error = nil
        guard let dogma = env.dogma else { return }
        do {
            report = try await dogma.npcDamage(context.spec, skills: context.skills, faction: faction)
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }

    private func classRow(_ c: NpcReport.ClassResult) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(npcClassLabel[c.cls] ?? c.cls)).font(.ui(14, .medium)).foregroundStyle(C.text)
                Text(verbatim: "\(c.count)").font(.mono(11)).foregroundStyle(C.faint)
                if c.approach { Pill(text: "approach", color: C.warn) }
                Spacer(minLength: 8)
                Text(verbatim: seconds(c.ttkMedian)).font(.display(18)).foregroundStyle(c.ttkMedian?.isFinite ?? false ? C.text : C.bad)
            }
            HStack(spacing: 12) {
                stat("Lands", "\(n0(c.application * 100))%", bad: c.application < 0.5)
                stat("Applied DPS", n0(c.appliedDps), bad: false)
                stat("Typical HP", n0(c.typical.hp), bad: false)
                if c.unkillable > 0 { stat("Out-repair you", "\(c.unkillable)", bad: true) }
            }
            Text("Fastest \(c.fastest.name) \(seconds(c.fastest.ttk)) · slowest \(c.slowest.name) \(seconds(c.slowest.ttk))")
                .font(.ui(11)).foregroundStyle(C.muted).fixedSize(horizontal: false, vertical: true)
            if !c.limits.isEmpty {
                Text("Held back by: \(c.limits.map { String(localized: String.LocalizationValue(limitLabel[$0] ?? $0)) }.joined(separator: ", "))")
                    .font(.ui(11)).foregroundStyle(C.warn)
            }
        }
        .padding(.vertical, 8)
    }

    private func stat(_ label: LocalizedStringKey, _ value: String, bad: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.ui(10, .medium)).textCase(.uppercase).foregroundStyle(C.faint)
            Text(verbatim: value).font(.mono(12, medium: true)).foregroundStyle(bad ? C.bad : C.text)
        }
    }
}

// MARK: - What to learn

private struct FitLearnView: View {
    let context: FitToolContext
    @Environment(AppEnvironment.self) private var env

    private enum Metric: String, CaseIterable { case dps, ehp, activeTank, speed, align, lockRange }
    private static let labels: [Metric: String] = [
        .dps: "Damage (DPS)", .ehp: "EHP", .activeTank: "Active tank", .speed: "Speed", .align: "Align time", .lockRange: "Targeting range",
    ]
    private struct Row: Identifiable {
        var id: Int { gain.skill }
        let gain: SkillGain
        let name: String
        let hours: Double
    }

    @State private var metric: Metric = .dps
    @State private var rows: [Row]?
    @State private var error: Error?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if context.levels == nil {
                Note("Needs a character: sign in with EVE SSO to see what each next level of your skills would give.")
            } else {
                Chips(options: Metric.allCases.map { ($0, Self.labels[$0] ?? $0.rawValue) }, selection: $metric)
                if let error {
                    ErrorLine(error: error)
                } else if let rows {
                    let top = rows.filter { value($0.gain) > 1e-6 }
                        .sorted { value($0.gain) / max($0.hours, 0.05) > value($1.gain) / max($1.hours, 0.05) }
                        .prefix(30)
                    if top.isEmpty {
                        Note("No next skill level improves this on this fit.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(top.enumerated()), id: \.offset) { i, r in
                                if i > 0 { Rectangle().fill(C.border).frame(height: 1) }
                                row(r)
                            }
                        }
                        .canopusSurface(nested: true, padding: 10)
                    }
                    Note("The fit recalculated with each skill one level higher (your current skills and implants). Sorted by gain per hour of training.")
                } else {
                    Loading(label: "Recalculating the fit for every skill…")
                }
            }
        }
        .task(id: context.key) { await load() }
    }

    /// "Better" is less time to align; everything else is more.
    private func value(_ g: SkillGain) -> Double {
        switch metric {
        case .dps: g.dps
        case .ehp: g.ehp
        case .activeTank: g.activeTank
        case .speed: g.speed
        case .align: -g.align
        case .lockRange: g.lockRange
        }
    }

    private func amount(_ g: SkillGain, _ m: Metric) -> String {
        switch m {
        case .align: "−" + (-g.align).formatted(.number.precision(.fractionLength(0...2))) + String(localized: " s")
        case .dps: "+" + n1(g.dps)
        case .ehp: "+" + n0(g.ehp)
        case .activeTank: "+" + n1(g.activeTank)
        case .speed: "+" + n1(g.speed)
        case .lockRange: "+" + n1(g.lockRange / 1000) + String(localized: " km")
        }
    }

    private func row(_ r: Row) -> some View {
        let roman = ["0", "I", "II", "III", "IV", "V"]
        let others = Metric.allCases.filter { m in
            m != metric && (m == .align ? r.gain.align < -0.005 : {
                switch m {
                case .dps: r.gain.dps > 0.05
                case .ehp: r.gain.ehp > 0.05
                case .activeTank: r.gain.activeTank > 0.05
                case .speed: r.gain.speed > 0.05
                case .lockRange: r.gain.lockRange > 0.05
                case .align: false
                }
            }())
        }
        .map { "\(String(localized: String.LocalizationValue(Self.labels[$0] ?? ""))) \(amount(r.gain, $0))" }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    EVETypeIcon(typeId: r.gain.skill, size: 20)
                    Text(verbatim: r.name).font(.ui(13, .medium)).foregroundStyle(C.text).lineLimit(1)
                    Text(verbatim: "\(roman[min(5, r.gain.from)]) → \(roman[min(5, r.gain.from + 1)])").font(.mono(11)).foregroundStyle(C.muted)
                }
                Spacer(minLength: 8)
                Text(verbatim: amount(r.gain, metric)).font(.mono(13, medium: true)).foregroundStyle(C.good)
            }
            HStack {
                Text(r.hours.isFinite ? Fmt.duration(seconds: r.hours * 3600) : "—").font(.ui(11)).foregroundStyle(C.text2)
                if !others.isEmpty {
                    Text(verbatim: others.joined(separator: " · ")).font(.ui(11)).foregroundStyle(C.muted).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 7)
    }

    private func load() async {
        rows = nil
        error = nil
        guard let levels = context.levels, let dogma = env.dogma, let repo = env.repository else { return }
        do {
            let gains = try await dogma.skillGains(context.spec, levels: levels)
            let ids = Set(gains.map(\.skill))
            async let skillsReq = context.service.skills()
            async let attrsReq = context.service.characterAttributes()
            async let queueReq = context.service.skillQueue()
            async let implantsReq = context.service.implants()
            let sp = Dictionary(uniqueKeysWithValues: ((try? await skillsReq)?.skills ?? []).map { ($0.skillId, $0.skillpointsInSkill) })
            let attributes = await TrainingAttributes.resolve(
                esi: try? await attrsReq, queue: (try? await queueReq) ?? [], implants: (try? await implantsReq) ?? [], repo: repo)
            let skillAttrs = try await repo.typeAttributeMaps(typeIds: ids)
            let names = try await repo.types(ids: ids).mapValues(\.name)
            rows = gains.map { g in
                let a = skillAttrs[g.skill] ?? [:]
                let rank = a[275] ?? 1
                let rate = attributes.map { ($0[Int(a[180] ?? 0)] ?? 0) + ($0[Int(a[181] ?? 0)] ?? 0) / 2 } ?? 0
                let have = Double(sp[g.skill] ?? 0)
                let need = max(0, TrainingAttributes.spForLevel(rank: rank, level: g.from + 1) - max(have, TrainingAttributes.spForLevel(rank: rank, level: g.from)))
                return Row(gain: g, name: names[g.skill] ?? "#\(g.skill)", hours: rate > 0 ? need / rate / 60 : .infinity)
            }
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }
}

/// Training speed inputs as the desktop's CharacterContext works them out.
enum TrainingAttributes {
    /// Implant attributes that add to charisma, intelligence, memory, perception, willpower.
    private static let implantBonus: [Int: Int] = [164: 175, 165: 176, 166: 177, 167: 178, 168: 179]

    static func spForLevel(rank: Double, level: Int) -> Double {
        level <= 0 ? 0 : (250 * rank * pow(2, 2.5 * Double(level - 1))).rounded(.up)
    }

    /// The character attributes training runs on. Whether ESI's numbers include implants isn't documented:
    /// the skill in training tells (whichever set reproduces its real SP/min); without one, a character's
    /// own attributes add up to 99, so a larger sum means implants are in.
    static func resolve(esi: ESICharacterAttributes?, queue: [ESISkillQueueItem], implants: [Int], repo: SDERepository) async -> [Int: Double]? {
        guard let esi else { return nil }
        let base: [Int: Double] = [164: Double(esi.charisma), 165: Double(esi.intelligence), 166: Double(esi.memory), 167: Double(esi.perception), 168: Double(esi.willpower)]
        guard !implants.isEmpty, let maps = try? await repo.typeAttributeMaps(typeIds: Set(implants)) else { return base }
        var bonus: [Int: Double] = [:]
        for imp in implants {
            for (attr, b) in implantBonus { bonus[attr, default: 0] += maps[imp]?[b] ?? 0 }
        }
        let withImplants = base.reduce(into: [Int: Double]()) { $0[$1.key] = $1.value + (bonus[$1.key] ?? 0) }
        let now = Date()
        if let e = queue.first(where: { ($0.finishDate ?? .distantPast) > now && $0.startDate != nil }),
           let start = e.startDate, let finish = e.finishDate, let end = e.levelEndSp, let from = e.trainingStartSp,
           finish.timeIntervalSince(start) > 0,
           let a = try? await repo.typeAttributeMaps(typeIds: [e.skillId])[e.skillId] {
            let observed = Double(end - from) / (finish.timeIntervalSince(start) / 60)
            let rate = { (x: [Int: Double]) in (x[Int(a[180] ?? 0)] ?? 0) + (x[Int(a[181] ?? 0)] ?? 0) / 2 }
            return abs(rate(base) - observed) < abs(rate(withImplants) - observed) ? base : withImplants
        }
        let sum = base.values.reduce(0, +), bonusSum = bonus.values.reduce(0, +)
        return bonusSum > 0 && sum >= 99 + bonusSum ? base : withImplants
    }
}

// MARK: - Compare fits

private struct FitCompareView: View {
    let context: FitToolContext
    @Environment(AppEnvironment.self) private var env

    private struct Line {
        let label: LocalizedStringKey
        let get: (JSFitStats) -> Double
        let fmt: (Double) -> String
        var lowerBetter = false
    }
    private static let lines: [Line] = [
        Line(label: "DPS", get: { $0.offense.totalDps }, fmt: { n1($0) }),
        Line(label: "Volley", get: { $0.offense.totalVolley }, fmt: { n0($0) }),
        Line(label: "EHP", get: { $0.defense.ehp }, fmt: { n0($0) }),
        Line(label: "Active tank, EHP/s", get: { $0.defense.activeTankEhp }, fmt: { n1($0) }),
        Line(label: "Shield regeneration, HP/s", get: { $0.defense.passiveShieldRegen }, fmt: { n1($0) }),
        Line(label: "Capacitor, % stable", get: { $0.capacitor.stable ? ($0.capacitor.stableLevel ?? 0) * 100 : 0 },
             fmt: { $0 > 0 ? "\(n1($0))%" : String(localized: "unstable") }),
        Line(label: "Speed, m/s", get: { $0.navigation.maxVelocity }, fmt: { n1($0) }),
        Line(label: "Align time, s", get: { $0.navigation.alignSec }, fmt: { $0.formatted(.number.precision(.fractionLength(0...2))) }, lowerBetter: true),
        Line(label: "Signature, m", get: { $0.navigation.signatureRadius }, fmt: { n1($0) }, lowerBetter: true),
        Line(label: "Targeting range, km", get: { $0.targeting.maxRange / 1000 }, fmt: { n1($0) }),
        Line(label: "Scan resolution, mm", get: { $0.targeting.scanResolution }, fmt: { n1($0) }),
        Line(label: "CPU used, %", get: { $0.ship.cpu.total > 0 ? $0.ship.cpu.used / $0.ship.cpu.total * 100 : 0 }, fmt: { "\(n1($0))%" }, lowerBetter: true),
        Line(label: "Powergrid used, %", get: { $0.ship.power.total > 0 ? $0.ship.power.used / $0.ship.power.total * 100 : 0 }, fmt: { "\(n1($0))%" }, lowerBetter: true),
    ]

    @State private var saved: [ESIFitting]?
    @State private var others: [ESIFitting] = []
    @State private var stats: [JSFitStats]?
    @State private var names: [Int: String] = [:]
    @State private var error: Error?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Menu {
                ForEach(saved ?? [], id: \.fittingId) { f in
                    Button("\(names[f.shipTypeId] ?? "") — \(f.name)") { others = Array((others + [f]).suffix(3)) }
                }
            } label: {
                Text("+ Add a fit to compare").font(.ui(14))
            }
            .buttonStyle(.canopusGhost)
            .disabled(saved?.isEmpty ?? true)
            Note("All fits use the same skills: the ones the fitting screen uses.")
            if let error {
                ErrorLine(error: error)
            } else if let stats {
                table(stats)
            } else {
                Loading(label: "Calculating…")
            }
        }
        .task { await loadSaved() }
        .task(id: "\(context.key)-\(others.map(\.fittingId))") { await calculate() }
    }

    private func loadSaved() async {
        guard saved == nil, let repo = env.repository else { return }
        let list = (try? await context.service.fittings()) ?? []
        names = ((try? await repo.types(ids: Set(list.map(\.shipTypeId)))) ?? [:]).mapValues(\.name)
        saved = list.sorted { (names[$0.shipTypeId] ?? "", $0.name) < (names[$1.shipTypeId] ?? "", $1.name) }
    }

    private func calculate() async {
        stats = nil
        error = nil
        guard let dogma = env.dogma, let repo = env.repository else { return }
        do {
            var out = [try await dogma.calculate(context.spec, skills: context.skills)]
            for f in others {
                out.append(try await dogma.calculate(FitSpecBuilder.spec(for: f, repo: repo), skills: context.skills))
            }
            stats = out
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }

    private func table(_ stats: [JSFitStats]) -> some View {
        let titles = [String(localized: "\(context.spec.name) (current)")] + others.map(\.name)
        return ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 7) {
                GridRow {
                    Color.clear.frame(width: 1, height: 1)
                    ForEach(Array(titles.enumerated()), id: \.offset) { i, t in
                        VStack(alignment: .trailing, spacing: 3) {
                            EVETypeIcon(typeId: i == 0 ? context.spec.shipTypeId : others[i - 1].shipTypeId, size: 24)
                            Text(verbatim: t).font(.ui(11)).foregroundStyle(C.muted).lineLimit(2).frame(maxWidth: 130, alignment: .trailing)
                            if i > 0 {
                                Button("✕") { others.remove(at: i - 1) }.buttonStyle(.canopusSmall)
                            }
                        }
                    }
                }
                ForEach(Array(Self.lines.enumerated()), id: \.offset) { _, line in
                    let vals = stats.map(line.get)
                    let best = line.lowerBetter ? vals.min() : vals.max()
                    GridRow {
                        Text(line.label).font(.ui(12)).foregroundStyle(C.text2).gridColumnAlignment(.leading)
                        ForEach(Array(vals.enumerated()), id: \.offset) { _, v in
                            let highlight = vals.count > 1 && v == best && vals.contains { $0 != v }
                            Text(verbatim: line.fmt(v)).font(.mono(12, medium: highlight)).foregroundStyle(highlight ? C.good : C.text)
                        }
                    }
                }
            }
            .padding(10)
        }
        .canopusSurface(nested: true, padding: 0)
    }
}

// MARK: - Popular fits (zKillboard losses)

private struct FitPopularView: View {
    let context: FitToolContext
    @Environment(AppEnvironment.self) private var env

    private struct Group: Identifiable {
        let id: Int
        var count: Int
        var last: Date
        let victim: ESIKillVictim
        let modules: [Int]
    }

    @State private var groups: [Group]?
    @State private var total = 0
    @State private var names: [Int: String] = [:]
    @State private var error: Error?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error {
                ErrorLine(error: error)
            } else if let groups {
                if groups.isEmpty {
                    Note("No recent losses of this ship with modules on zKillboard.")
                } else {
                    Note("The fits this ship was lost with most often (the last \(total) losses on zKillboard): real fits players fly.")
                    VStack(spacing: 0) {
                        ForEach(Array(groups.enumerated()), id: \.offset) { i, g in
                            if i > 0 { Rectangle().fill(C.border).frame(height: 1) }
                            row(g)
                        }
                    }
                    .canopusSurface(nested: true, padding: 10)
                }
            } else {
                Loading(label: "Looking at recent losses on zKillboard…")
            }
        }
        .task(id: context.spec.shipTypeId) { await load() }
    }

    private func row(_ g: Group) -> some View {
        let counts = g.modules.reduce(into: [Int: Int]()) { $0[$1, default: 0] += 1 }
            .sorted { (names[$0.key] ?? "") < (names[$1.key] ?? "") }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(g.count)×").font(.display(18)).foregroundStyle(C.accentText)
                Text(g.last, format: .relative(presentation: .named)).font(.ui(12)).foregroundStyle(C.muted)
                Spacer()
                Button("Open") { context.openFit(FitSpecBuilder.fitting(from: g.victim, killmailId: g.id)) }
                    .buttonStyle(.canopusSmall)
            }
            Text(verbatim: counts.map { ($0.value > 1 ? "\($0.value)× " : "") + (names[$0.key] ?? "#\($0.key)") }.joined(separator: " · "))
                .font(.ui(12)).foregroundStyle(C.text2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }

    private func load() async {
        groups = nil
        error = nil
        guard let repo = env.repository else { return }
        do {
            let losses = try await KillBoardService().losses(shipTypeId: context.spec.shipTypeId).prefix(40)
            let ids = Set(losses.flatMap { $0.victim?.items?.map(\.itemTypeId) ?? [] })
            let profiles = try await repo.typeProfiles(typeIds: ids)
            let isModule = { (id: Int) in !(profiles[id]?.effectIds.isDisjoint(with: [11, 12, 13, 2663, 3772]) ?? true) }
            let fitted = { (flag: Int) in (11...34).contains(flag) || (92...99).contains(flag) || (125...132).contains(flag) }
            // Same set of fitted modules (charges ignored) = same fit.
            var byKey: [String: Group] = [:]
            var order: [String] = []
            for k in losses {
                guard let v = k.victim, let items = v.items else { continue }
                let modules = items.filter { fitted($0.flag) && isModule($0.itemTypeId) }.map(\.itemTypeId)
                guard modules.count >= 3 else { continue }
                let key = modules.sorted().map(String.init).joined(separator: ",")
                let time = k.killmailTime ?? .distantPast
                if var g = byKey[key] {
                    g.count += 1
                    g.last = max(g.last, time)
                    byKey[key] = g
                } else {
                    byKey[key] = Group(id: k.killmailId, count: 1, last: time, victim: v, modules: modules)
                    order.append(key)
                }
            }
            total = losses.filter { $0.victim != nil }.count
            names = try await repo.types(ids: Set(byKey.values.flatMap(\.modules))).mapValues(\.name)
            groups = order.compactMap { byKey[$0] }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.last > $1.last }.prefix(12).map { $0 }
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }
}
