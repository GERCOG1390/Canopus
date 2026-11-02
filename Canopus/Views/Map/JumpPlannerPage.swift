// Capital jump planner (the desktop's JumpPlanner.tsx): jump range from skills, the fewest-jumps route
// over lowsec / nullsec, fuel per jump and the jump fatigue / activation timers along the way.

import SwiftUI
import Domain
import EVEAuth
import EVEStaticData

private enum JumpAttr {
    static let fuelType = 866, range = 867, fuelPerLy = 868
}
private enum JumpSkill {
    static let calibration = 21611, conservation = 21610, jumpFreighters = 29029
}
private let jumpFreighterGroup = 902
/// Industrial hulls: jump fatigue counts 10 % of the distance.
private let industrialGroups: Set<Int> = [902, 883, 941, 513, 28, 1202, 380, 31, 29]
private let blackOpsGroup = 898
private let maxFatigueMinutes = 300.0
private let maxCooldownMinutes = 30.0

private func ly(_ v: Double) -> String { String(localized: "\(v.formatted(.number.precision(.fractionLength(0...2)))) ly") }
private func minutes(_ m: Double) -> String {
    m >= 60 ? String(localized: "\(Int(m / 60)) h \(Int(m.truncatingRemainder(dividingBy: 60).rounded())) min") : String(localized: "\(Int(m.rounded())) min")
}

struct JumpPlannerPage: View {
    @Environment(AppEnvironment.self) private var env
    @State private var ships: [JumpDriveShip] = []
    @State private var ship: JumpDriveShip?
    @State private var shipQuery = ""
    @State private var shipGroup = 0
    @State private var attrs: [Int: Double] = [:]
    @State private var fuelName = ""
    @State private var fuelPrice: Double?
    @State private var from: (id: Int, name: String)?
    @State private var to: (id: Int, name: String)?
    @State private var allV = true
    @State private var charLevels: [Int: Int]?
    @State private var fatigueStart = 0.0
    @State private var galaxy: GalaxyData?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                form
                result
            }
            .padding(16)
        }
        .background(C.bg)
        .navigationTitle("Capital jumps")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: env.repositoryVersion) {
            guard let repo = env.repository else { return }
            if ships.isEmpty { ships = (try? await repo.jumpDriveShips()) ?? [] }
            if galaxy == nil { galaxy = try? await repo.galaxy() }
            #if DEBUG
            // Debug builds: `-jumpShip 23757 -jumpFrom 30002187 -jumpTo 30004759` fill the planner (screenshots).
            let d = UserDefaults.standard
            if ship == nil, d.integer(forKey: "jumpShip") > 0 { ship = ships.first { $0.id == d.integer(forKey: "jumpShip") } }
            for (key, apply) in [("jumpFrom", { (v: (id: Int, name: String)) in from = v }), ("jumpTo", { to = $0 })] {
                let id = d.integer(forKey: key)
                if id > 0, let s = try? await repo.systems(ids: [id])[id] { apply((id, s.name)) }
            }
            #endif
        }
        .task(id: env.dataKey) { await loadPilot() }
        .task(id: "\(ship?.id ?? 0)/\(env.repositoryVersion)") { await loadShip() }
    }

    // MARK: Form

    private var form: some View {
        Card(String(localized: "Capital jumps")) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ship with a jump drive").font(.ui(11)).foregroundStyle(C.muted)
                field(ship?.name ?? String(localized: "Archon, Revelation, Rhea, Rorqual…"), text: $shipQuery)
                let q = shipQuery.trimmingCharacters(in: .whitespaces).lowercased()
                if !q.isEmpty {
                    ForEach(ships.filter { $0.name.lowercased().contains(q) }.prefix(8)) { s in
                        Button { ship = s; shipQuery = "" } label: {
                            HStack(spacing: 8) {
                                EVETypeIcon(typeId: s.id, size: 22)
                                Text(verbatim: s.name).font(.ui(13)).foregroundStyle(C.text)
                                Spacer()
                            }
                            .frame(minHeight: 30).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            SystemPicker(label: "From", picked: $from)
            SystemPicker(label: "To (lowsec or null)", picked: $to)
            HStack(spacing: 6) {
                Text("Skills").font(.ui(11)).foregroundStyle(C.muted)
                Button("All V") { allV = true }.buttonStyle(CanopusButtonStyle(kind: allV ? .primary : .ghost, small: true))
                if charLevels != nil {
                    Button(String(localized: "Skills of \(env.characterStore.selectedService?.tokens.characterName ?? "")")) { allV = false }
                        .buttonStyle(CanopusButtonStyle(kind: allV ? .ghost : .primary, small: true))
                }
            }
            NumberField(label: "Current fatigue, min", value: $fatigueStart)
            if ship != nil, (attrs[JumpAttr.range] ?? 0) > 0 {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    StatTile(label: "Jump range", value: ly(range),
                             sub: String(localized: "base \(ly(attrs[JumpAttr.range] ?? 0)), Jump Drive Calibration \(level(JumpSkill.calibration))"))
                    StatTile(label: "Fuel", value: fuelName.isEmpty ? "—" : fuelName,
                             sub: String(localized: "\(Int(fuelPerLy.rounded())) per light year"))
                    StatTile(label: "Fatigue counts", value: String(localized: "\(Int(fatigueFactor * 100))% of the distance"),
                             sub: fatigueFactor == 0.1 ? String(localized: "industrial ship") : fatigueFactor < 1 ? "Black Ops" : String(localized: "combat capital"))
                }
            }
        }
    }

    private func field(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .font(.ui(14)).autocorrectionDisabled().textInputAutocapitalization(.never)
            .padding(.horizontal, 10).frame(minHeight: 38)
            .background(C.panel2, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(C.border))
    }

    // MARK: Numbers

    private func level(_ skill: Int) -> Int { allV ? 5 : charLevels?[skill] ?? 0 }
    private var range: Double { (attrs[JumpAttr.range] ?? 0) * (1 + 0.2 * Double(level(JumpSkill.calibration))) }
    private var fuelPerLy: Double {
        (attrs[JumpAttr.fuelPerLy] ?? 0) * (1 - 0.1 * Double(level(JumpSkill.conservation)))
            * (shipGroup == jumpFreighterGroup ? 1 - 0.1 * Double(level(JumpSkill.jumpFreighters)) : 1)
    }
    private var fatigueFactor: Double { industrialGroups.contains(shipGroup) ? 0.1 : shipGroup == blackOpsGroup ? 0.25 : 1 }

    private struct PlanRow { let hop: MapLogic.JumpHop; let fuel: Int; let cooldown: Double; let fatigue: Double; let at: Double }

    /// Fatigue along the route, jumping as soon as each activation timer runs out.
    private func plan(_ hops: [MapLogic.JumpHop]) -> (rows: [PlanRow], fuel: Int, time: Double) {
        var fatigue = fatigueStart, time = 0.0
        var rows: [PlanRow] = []
        for (i, h) in hops.enumerated() {
            let eff = h.ly * fatigueFactor
            let cooldown = min(maxCooldownMinutes, max(1 + eff, fatigue / 10))
            fatigue = min(maxFatigueMinutes, max(10 * (1 + eff), fatigue * (1 + eff)))
            rows.append(PlanRow(hop: h, fuel: Int((h.ly * fuelPerLy).rounded(.up)), cooldown: cooldown, fatigue: fatigue, at: time))
            if i < hops.count - 1 {
                time += cooldown
                fatigue = max(0, fatigue - cooldown)
            }
        }
        return (rows, rows.reduce(0) { $0 + $1.fuel }, time)
    }

    // MARK: Result

    @ViewBuilder private var result: some View {
        if ship == nil || from == nil || to == nil {
            Text("Pick the ship, where from and where to.").font(.ui(13)).foregroundStyle(C.muted)
        } else if (attrs[JumpAttr.range] ?? 0) <= 0 {
            EmptyView()
        } else if let g = galaxy, let from, let to {
            if let hops = MapLogic.jumpRoute(g, from: from.id, to: to.id, rangeLy: range) {
                let p = plan(hops)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    StatTile(label: "Jumps", value: "\(hops.count)", sub: String(localized: "\(ly(hops.reduce(0) { $0 + $1.ly })) in all"))
                    StatTile(label: "Fuel", value: p.fuel.formatted(), sub: fuelPrice.map { String(localized: "≈ \(Fmt.isk(Double(p.fuel) * $0)) at Jita") })
                    StatTile(label: "Travel time", value: minutes(p.time), sub: String(localized: "waiting out activation timers"))
                    StatTile(label: "Fatigue on arrival", value: minutes(p.rows.last?.fatigue ?? 0),
                             sub: String(localized: "next jump timer \(minutes(p.rows.last?.cooldown ?? 0))"),
                             valueColor: (p.rows.last?.fatigue ?? 0) > 120 ? C.bad : C.text)
                }
                Card {
                    ForEach(Array(p.rows.enumerated()), id: \.offset) { i, r in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(verbatim: "\(i + 1)").font(.mono(11)).foregroundStyle(C.faint).frame(width: 20, alignment: .leading)
                                systemLabel(g, r.hop.from)
                                Text(verbatim: "→").foregroundStyle(C.muted)
                                systemLabel(g, r.hop.to, bold: true)
                                Spacer(minLength: 4)
                                Text(verbatim: ly(r.hop.ly)).font(.mono(12)).foregroundStyle(C.text)
                            }
                            HStack(spacing: 10) {
                                Text("fuel \(r.fuel.formatted())")
                                Text("start in \(minutes(r.at))")
                                Text("timer \(minutes(r.cooldown))")
                                Text("fatigue \(minutes(r.fatigue))").foregroundStyle(r.fatigue > 120 ? C.bad : C.muted)
                            }
                            .font(.mono(10)).foregroundStyle(C.muted).padding(.leading, 26)
                        }
                        .padding(.vertical, 4)
                    }
                    Text("Route: fewest jumps, then the shortest distance (less fatigue), lowsec and null only. Fatigue after a jump is max(10·(1+ly), fatigue·(1+ly)), up to 5 h; the activation timer is max(1+ly, fatigue/10), up to 30 min; fatigue wears off in real time. Each stop needs a cyno.")
                        .font(.ui(11)).foregroundStyle(C.faint)
                }
            } else {
                let direct = MapLogic.lightYears(g, from.id, to.id).map { ly(Double($0)) } ?? "?"
                Text("No route: the target is in highsec, a wormhole or out of reach (\(direct) direct, range \(ly(range))).")
                    .font(.ui(13)).foregroundStyle(C.warn)
            }
        } else {
            ProgressView().tint(C.accent).frame(maxWidth: .infinity)
        }
    }

    private func systemLabel(_ g: GalaxyData, _ id: Int, bold: Bool = false) -> some View {
        let i = g.index[id]
        let sec = i.map { g.security[$0] } ?? 0
        return HStack(spacing: 3) {
            Text(verbatim: String(format: "%.1f", (sec * 10).rounded() / 10)).font(.mono(11)).foregroundStyle(C.sec(sec))
            Text(verbatim: i.map { g.names[$0] } ?? "#\(id)").font(.ui(13, bold ? .semibold : .regular)).foregroundStyle(C.text).lineLimit(1)
        }
    }

    // MARK: Loading

    private func loadPilot() async {
        guard let svc = env.characterStore.selectedService else { charLevels = nil; return }
        if let skills = try? await svc.skills() {
            charLevels = Dictionary(skills.skills.map { ($0.skillId, $0.activeSkillLevel) }, uniquingKeysWith: { a, _ in a })
            allV = false
        }
        if let f = try? await svc.fatigue(), let end = f.jumpFatigueExpireDate {
            fatigueStart = max(0, end.timeIntervalSinceNow / 60).rounded()
        }
    }

    private func loadShip() async {
        guard let ship, let repo = env.repository else { attrs = [:]; return }
        attrs = (try? await repo.typeAttributeMaps(typeIds: [ship.id]))?[ship.id] ?? [:]
        shipGroup = (try? await repo.types(ids: [ship.id]))?[ship.id]?.groupId ?? 0
        let fuel = Int(attrs[JumpAttr.fuelType] ?? 0)
        if fuel > 0 {
            fuelName = (try? await repo.types(ids: [fuel]))?[fuel]?.name ?? ""
            fuelPrice = (try? await HubPrices.jitaSell(typeIds: [fuel]))?[fuel]
        } else {
            fuelName = ""
            fuelPrice = nil
        }
    }
}

/// A solar system picked by typing its name (suggestions from the SDE).
struct SystemPicker: View {
    let label: LocalizedStringKey
    @Binding var picked: (id: Int, name: String)?
    @Environment(AppEnvironment.self) private var env
    @State private var query = ""
    @State private var hits: [(id: Int, name: String, security: Double)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.ui(11)).foregroundStyle(C.muted)
            TextField(picked?.name ?? String(localized: "System…"), text: $query)
                .font(.ui(14)).autocorrectionDisabled().textInputAutocapitalization(.never)
                .padding(.horizontal, 10).frame(minHeight: 38)
                .background(C.panel2, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(C.border))
            ForEach(hits, id: \.id) { s in
                Button {
                    picked = (s.id, s.name)
                    query = ""
                    hits = []
                } label: {
                    HStack(spacing: 6) {
                        Text(verbatim: String(format: "%.1f", (s.security * 10).rounded() / 10)).font(.mono(12)).foregroundStyle(C.sec(s.security))
                        Text(verbatim: s.name).font(.ui(13)).foregroundStyle(C.text)
                        Spacer()
                    }
                    .frame(minHeight: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2, let repo = env.repository else { hits = []; return }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            hits = (try? await repo.systems(matching: q, limit: 6)) ?? []
        }
    }
}
