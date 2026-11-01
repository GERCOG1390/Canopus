// Wormholes (the desktop's Wormholes.tsx): look up a hole by its code or a J-space system by name, roll a
// hole with the mass calculator, and every wormhole type with where it leads and its limits.

import SwiftUI
import Domain
import EVEStaticData

private let classLabels: [Int: String] = [
    1: "C1", 2: "C2", 3: "C3", 4: "C4", 5: "C5", 6: "C6", 7: "Highsec", 8: "Lowsec", 9: "Nullsec", 12: "Thera",
    13: "C13 (Shattered)", 14: "Sentinel", 15: "Barbican", 16: "Vidette", 17: "Conflux", 18: "Redoubt", 25: "Pochven",
]

private func classLabel(_ c: Int) -> String {
    if let l = classLabels[c] { return [7, 8, 9].contains(c) ? String(localized: String.LocalizationValue(l)) : l }
    return c > 0 ? String(localized: "class \(c)") : String(localized: "unknown")
}

private func millionKg(_ kg: Double) -> String {
    String(localized: "\((kg / 1e6).formatted(.number.precision(.fractionLength(0...1)))) M kg")
}

private func tons(_ kg: Double) -> String {
    String(localized: "\((kg / 1000).formatted(.number.precision(.fractionLength(0)))) t")
}

/// Which ships fit through, by the hole's per-jump mass limit.
private func passes(_ jumpMass: Double) -> String {
    switch jumpMass {
    case ...5_000_000: String(localized: "frigates and destroyers")
    case ...62_000_000: String(localized: "up to battlecruisers")
    case ...375_000_000: String(localized: "up to battleships")
    case ...1_000_000_000: String(localized: "up to freighters")
    default: String(localized: "capital ships")
    }
}

struct WormholesPage: View {
    @Environment(AppEnvironment.self) private var env
    @State private var types: [WormholeType] = []
    @State private var selected: WormholeType?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                WormholeLookup(types: types) { selected = $0 }
                MassCalculator(hole: selected)
                typeTable
            }
            .padding(16)
        }
        .background(C.bg)
        .navigationTitle("Wormholes")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: env.repositoryVersion) { types = (try? await env.repository?.wormholeTypes()) ?? [] }
    }

    @State private var target = 0

    private var typeTable: some View {
        let targets = Set(types.map(\.target)).filter { classLabels[$0] != nil }.sorted()
        let shown = types.filter { target == 0 || $0.target == target }
        return Card(title: String(localized: "Wormhole types (\(shown.count))"), actions: {
            Menu {
                Button("Lead anywhere") { target = 0 }
                ForEach(targets, id: \.self) { c in
                    Button { target = c } label: { Text("Lead into \(classLabel(c))") }
                }
            } label: {
                Text(verbatim: target == 0 ? String(localized: "Lead anywhere") : String(localized: "Lead into \(classLabel(target))"))
                    .font(.ui(12, .medium)).foregroundStyle(C.accentText)
            }
        }) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(shown) { w in
                    Button { selected = w } label: {
                        HStack(spacing: 8) {
                            Text(verbatim: w.code).font(.mono(13, medium: true)).foregroundStyle(selected?.id == w.id ? C.accentText : C.text).frame(width: 52, alignment: .leading)
                            Text(verbatim: classLabel(w.target)).font(.ui(12)).foregroundStyle(C.text).frame(width: 78, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: "\(millionKg(w.mass)) · \(millionKg(w.jumpMass))/" + String(localized: "jump"))
                                    .font(.mono(11)).foregroundStyle(C.text)
                                Text(verbatim: String(localized: "\((w.lifetime / 60).formatted()) h · \(passes(w.jumpMass))"))
                                    .font(.ui(10)).foregroundStyle(C.muted)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(C.border).frame(height: 1)
                }
            }
            Text("Data from CCP's SDE. A hole's real mass is random within ±10 % of the listed one. Tap a type to put it into the calculator.")
                .font(.ui(11)).foregroundStyle(C.faint)
        }
    }
}

// MARK: - Lookup

private struct WormholeLookup: View {
    let types: [WormholeType]
    let onPick: (WormholeType) -> Void
    @Environment(AppEnvironment.self) private var env
    @State private var query: String = {
        #if DEBUG
        // Debug builds: `-whQuery J100001` (screenshots).
        if let q = UserDefaults.standard.string(forKey: "whQuery") { return q }
        #endif
        return ""
    }()
    @State private var system: WormholeSystem?
    @State private var effectName: String?

    var body: some View {
        let code = query.trimmingCharacters(in: .whitespaces).uppercased()
        let hole = types.first { $0.code == code }
        Card(String(localized: "Lookup: hole code or J-system")) {
            TextField("e.g. C247 or J100001", text: $query)
                .font(.mono(14)).autocorrectionDisabled().textInputAutocapitalization(.characters)
                .padding(.horizontal, 10).frame(minHeight: 38)
                .background(C.panel2, in: RoundedRectangle(cornerRadius: 8))
            if let hole {
                VStack(alignment: .leading, spacing: 4) {
                    kv(String(localized: "Hole"), hole.code)
                    kv(String(localized: "Leads into"), classLabel(hole.target))
                    kv(String(localized: "Lives"), String(localized: "\((hole.lifetime / 60).formatted()) h"))
                    kv(String(localized: "Total mass"), millionKg(hole.mass))
                    kv(String(localized: "Mass per jump"), "\(millionKg(hole.jumpMass)) — \(passes(hole.jumpMass))")
                    if hole.regen > 0 { kv(String(localized: "Mass regeneration"), String(localized: "\(millionKg(hole.regen)) a day")) }
                }
                Button("To the mass calculator") { onPick(hole) }.buttonStyle(.canopusSmall)
            }
            if let s = system {
                VStack(alignment: .leading, spacing: 4) {
                    kv(String(localized: "System"), String(format: "%.1f ", s.security) + s.name)
                    kv(String(localized: "Region"), s.region)
                    kv(String(localized: "Class"), s.wormholeClass.map(classLabel) ?? "—")
                    HStack {
                        Text("Effect").font(.ui(12)).foregroundStyle(C.muted)
                        Spacer()
                        if let fx = s.effectTypeId {
                            NavigationLink { TypeDetailView(typeId: fx, typeName: effectName ?? "") } label: {
                                Text(verbatim: effectName ?? "#\(fx)").font(.ui(13)).foregroundStyle(C.accentText)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("none").font(.ui(13)).foregroundStyle(C.text)
                        }
                    }
                }
            }
            if code.count >= 4, hole == nil, system == nil {
                Text("Not found: type a hole's 4-character signature code or a J-system's name.").font(.ui(12)).foregroundStyle(C.muted)
            }
        }
        .task(id: "\(code)/\(env.repositoryVersion)") {
            system = nil
            effectName = nil
            guard code.count >= 4, code.hasPrefix("J") || ["THERA", "TURNUR"].contains(code), let repo = env.repository else { return }
            system = try? await repo.wormholeSystem(named: code)
            if let fx = system?.effectTypeId { effectName = try? await repo.types(ids: [fx])[fx]?.name }
        }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: k).font(.ui(12)).foregroundStyle(C.muted)
            Spacer(minLength: 8)
            Text(verbatim: v).font(.ui(13, .medium)).foregroundStyle(C.text).multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Mass calculator

private enum HoleState: String, CaseIterable, Hashable {
    case fresh, reduced, critical

    /// Remaining mass as fractions of the nominal mass, for the state the game shows (actual mass is ±10 %).
    var range: (Double, Double) {
        switch self {
        case .fresh: (0.5 * 0.9, 1.1)
        case .reduced: (0.1 * 0.9, 0.5 * 1.1)
        case .critical: (0, 0.1 * 1.1)
        }
    }

    var label: String {
        switch self {
        case .fresh: String(localized: "Not disrupted (>50 %)")
        case .reduced: String(localized: "Reduced (10–50 %)")
        case .critical: String(localized: "Critical (<10 %)")
        }
    }
}

/// Prop modules used for rolling: "hot" jumps add their mass (attribute 796, massAddition).
private let propModules = ["1MN Afterburner II", "5MN Microwarpdrive II", "10MN Afterburner II", "50MN Microwarpdrive II", "100MN Afterburner II", "500MN Microwarpdrive II"]

private struct MassCalculator: View {
    let hole: WormholeType?
    @Environment(AppEnvironment.self) private var env

    private struct Ship: Hashable { let typeId: Int; let name: String; let mass: Double; var prop: Double }
    private struct Jump: Hashable { let ship: Int; let hot: Bool; let out: Bool }

    @State private var mass = 2_000_000_000.0
    @State private var jumpMass = 300_000_000.0
    @State private var state: HoleState = .fresh
    @State private var ships: [Ship] = []
    @State private var jumps: [Jump] = []
    @State private var props: [(name: String, add: Double)] = []
    @State private var query = ""
    @State private var hits: [ItemType] = []

    private struct Row { let jump: Jump; let m: Double; let lo: Double; let hi: Double; let risk: String? }

    /// Each jump with the mass it uses and what may be left after it (a range: the real mass is ±10 %).
    private func plan() -> (rows: [Row], lo: Double, hi: Double) {
        let lo0 = state.range.0 * mass, hi0 = state.range.1 * mass
        var used = 0.0
        var rows: [Row] = []
        for j in jumps {
            let s = ships.indices.contains(j.ship) ? ships[j.ship] : nil
            let m = (s?.mass ?? 0) + (j.hot ? s?.prop ?? 0 : 0)
            used += m
            let lo = lo0 - used, hi = hi0 - used
            let risk: String? = m > jumpMass ? "heavy" : hi <= 0 ? "closed" : lo <= 0 ? (j.out ? "cutoff" : "may") : nil
            rows.append(Row(jump: j, m: m, lo: lo, hi: hi, risk: risk))
        }
        return (rows, rows.last?.lo ?? lo0, rows.last?.hi ?? hi0)
    }

    var body: some View {
        let p = plan()
        let rows = p.rows, remLo = p.lo, remHi = p.hi
        let outside = ships.indices.map { i in jumps.filter { $0.ship == i }.reduce(0) { $0 + ($1.out ? 1 : -1) } > 0 }

        Card(String(localized: "Mass calculator (rolling)")) {
            FlowRow(spacing: 10) {
                NumberField(label: "Total mass, M kg", value: Binding(get: { mass / 1e6 }, set: { mass = $0 * 1e6 }))
                NumberField(label: "Mass per jump, M kg", value: Binding(get: { jumpMass / 1e6 }, set: { jumpMass = $0 * 1e6 }))
            }
            FlowRow(spacing: 6) {
                ForEach(HoleState.allCases, id: \.self) { s in
                    Button(s.label) { state = s }.buttonStyle(CanopusButtonStyle(kind: state == s ? .primary : .ghost, small: true))
                }
            }
            if let hole { Text(verbatim: "\(hole.code) → \(classLabel(hole.target))").font(.ui(12)).foregroundStyle(C.muted) }

            Text("Ships for rolling").font(.ui(12, .semibold)).foregroundStyle(C.text).padding(.top, 4)
            TextField("Add a ship…", text: $query).font(.ui(14)).autocorrectionDisabled().textInputAutocapitalization(.never)
                .padding(.horizontal, 10).frame(minHeight: 36)
                .background(C.panel2, in: RoundedRectangle(cornerRadius: 8))
            ForEach(hits) { t in
                Button { addShip(t) } label: { MarketTypeRow(type: t) }.buttonStyle(.plain)
            }
            if ships.isEmpty {
                Text("Add the ships you'll jump with: mass comes from the SDE, a hot jump has the AB / MWD on.").font(.ui(12)).foregroundStyle(C.muted)
            }
            ForEach(Array(ships.enumerated()), id: \.offset) { i, s in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        EVETypeIcon(typeId: s.typeId, size: 22)
                        Text(verbatim: s.name).font(.ui(13)).foregroundStyle(C.text)
                        if outside[i] { Pill(text: String(localized: "outside"), color: C.bad) }
                        Spacer()
                        Text(verbatim: "❄ \(tons(s.mass)) · 🔥 \(tons(s.mass + s.prop))").font(.mono(10)).foregroundStyle(C.muted)
                    }
                    Menu {
                        Button("No AB / MWD") { ships[i].prop = 0 }
                        ForEach(props, id: \.name) { p in
                            Button { ships[i].prop = p.add } label: { Text(verbatim: "\(p.name) (+\(tons(p.add)))") }
                        }
                    } label: {
                        Text(verbatim: props.first { $0.add == s.prop }?.name ?? String(localized: "No AB / MWD")).font(.ui(11)).foregroundStyle(C.accentText)
                    }
                    FlowRow(spacing: 6) {
                        Button("Out ❄") { jumps.append(Jump(ship: i, hot: false, out: true)) }.buttonStyle(.canopusSmall)
                        Button("Out 🔥") { jumps.append(Jump(ship: i, hot: true, out: true)) }.buttonStyle(.canopusSmall)
                        Button("Back ❄") { jumps.append(Jump(ship: i, hot: false, out: false)) }.buttonStyle(.canopusSmall)
                        Button("Back 🔥") { jumps.append(Jump(ship: i, hot: true, out: false)) }.buttonStyle(.canopusSmall)
                    }
                }
                .padding(.vertical, 4)
            }

            StatTile(label: "Mass left",
                     value: String(localized: "\((max(0, remLo) / 1e6).formatted(.number.precision(.fractionLength(0))))–\((max(0, remHi) / 1e6).formatted(.number.precision(.fractionLength(0)))) M kg"),
                     sub: String(localized: "with ±10 % and the hole's state; jumps: \(jumps.count)"))
            GeometryReader { geo in
                // Against the most the hole can hold (+10 %): what is left for sure, then what may be.
                let full = mass * 1.1
                let sure = min(1, max(0, remLo / full))
                let maybe = min(1 - sure, max(0, (remHi - max(0, remLo)) / full))
                HStack(spacing: 0) {
                    Rectangle().fill(C.accent).frame(width: geo.size.width * sure)
                    Rectangle().fill(C.accent.opacity(0.35)).frame(width: geo.size.width * maybe)
                    Spacer(minLength: 0)
                }
                .background(C.panel2)
                .clipShape(Capsule())
            }
            .frame(height: 8)

            ForEach(Array(rows.enumerated()), id: \.offset) { n, r in
                HStack(spacing: 6) {
                    Text(verbatim: "\(n + 1)").font(.mono(11)).foregroundStyle(C.faint).frame(width: 22, alignment: .leading)
                    Text(verbatim: ships.indices.contains(r.jump.ship) ? ships[r.jump.ship].name : "?").font(.ui(12)).foregroundStyle(C.text).lineLimit(1)
                    Text(verbatim: (r.jump.out ? String(localized: "out") : String(localized: "back")) + (r.jump.hot ? " 🔥" : " ❄")).font(.ui(11)).foregroundStyle(C.muted)
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(verbatim: "\((max(0, r.lo) / 1e6).formatted(.number.precision(.fractionLength(0))))–\((max(0, r.hi) / 1e6).formatted(.number.precision(.fractionLength(0))))")
                            .font(.mono(11)).foregroundStyle(C.text)
                        if let risk = r.risk { riskText(risk) }
                    }
                }
                .padding(.vertical, 2)
                .background(r.risk == "cutoff" || r.risk == "heavy" ? C.bad.opacity(0.08) : .clear)
            }
            if !jumps.isEmpty {
                HStack(spacing: 6) {
                    Button("Undo jump") { jumps.removeLast() }.buttonStyle(.canopusSmall)
                    Button("Reset jumps") { jumps = [] }.buttonStyle(.canopusSmall)
                }
            }
            Text("The hole's state shows in the game's Show Info. Its real mass is random within ±10 %, so what's left is a range. Jump out only when the ship can still get back in the worst case: risky jumps are marked red.")
                .font(.ui(11)).foregroundStyle(C.faint)
        }
        .onChange(of: hole) { _, h in
            guard let h else { return }
            mass = h.mass
            jumpMass = h.jumpMass
            jumps = []
        }
        .task(id: env.repositoryVersion) { await loadProps() }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2, let repo = env.repository else { hits = []; return }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let found = (try? await repo.search(q)) ?? []
            let groups = (try? await repo.groups(ids: Set(found.map(\.groupId)))) ?? [:]
            hits = Array(found.filter { groups[$0.groupId]?.categoryId == 6 }.prefix(6))
        }
    }

    @ViewBuilder private func riskText(_ risk: String) -> some View {
        switch risk {
        case "heavy": Text("won't pass: heavier than the jump limit").font(.ui(10)).foregroundStyle(C.bad)
        case "closed": Text("the hole closes for sure").font(.ui(10)).foregroundStyle(C.good)
        case "may": Text("may close on this jump").font(.ui(10)).foregroundStyle(C.warn)
        default: Text("may close — the ship is left outside!").font(.ui(10)).foregroundStyle(C.bad)
        }
    }

    private func addShip(_ t: ItemType) {
        let m = t.mass ?? 0
        // Default prop module by hull size: big hulls roll with 100MN AB / 500MN MWD.
        let prefix = m > 50_000_000 ? "100MN" : m > 5_000_000 ? "10MN" : "1MN"
        ships.append(Ship(typeId: t.id, name: t.name, mass: m, prop: props.first { $0.name.hasPrefix(prefix) }?.add ?? 0))
        query = ""
    }

    private func loadProps() async {
        guard let repo = env.repository else { return }
        var out: [(String, Double)] = []
        for name in propModules {
            guard let t = try? await repo.type(named: name),
                  let add = try? await repo.typeAttributeMaps(typeIds: [t.id])[t.id]?[796] else { continue }
            out.append((name, add))
        }
        props = out
    }
}
