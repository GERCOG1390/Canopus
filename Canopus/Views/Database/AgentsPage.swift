// Mission agents (importer 7): filter by level, division and kind, find a corporation's agents, and see
// how many jumps each is from you; tapping one opens its info in the game client.

import SwiftUI
import EVEAuth
import EVEStaticData

struct AgentsPage: View {
    @Environment(AppEnvironment.self) private var env
    @State private var all: [AgentEntry]?
    @State private var galaxy: GalaxyData?
    @State private var origin: (id: Int, name: String)?
    @State private var jumps: [Int: Int] = [:]
    @State private var level = 4
    @State private var division = "Security"
    @State private var query = ""
    @State private var highsecOnly = true
    @State private var status: String?

    /// The SDE's division names (and "Locator": agents that find players, any division).
    private let divisions = ["Security", "Distribution", "Mining", "R&D", "Locator"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let all {
                    if all.isEmpty {
                        Card { Text("The SDE database has no agents yet. Update the database in Settings.").font(.ui(13)).foregroundStyle(C.muted) }
                    } else {
                        filters
                        list(all)
                    }
                } else {
                    ProgressView().tint(C.accent).frame(maxWidth: .infinity).padding(.top, 30)
                }
            }
            .padding(16)
        }
        .background(C.bg)
        .navigationTitle("Agents")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: env.repositoryVersion) {
            all = (try? await env.repository?.agents()) ?? []
            if galaxy == nil { galaxy = try? await env.repository?.galaxy() }
        }
        .task(id: env.dataKey) {
            guard origin == nil, let svc = env.characterStore.selectedService, let loc = try? await svc.location(),
                  let s = try? await env.repository?.systems(ids: [loc.solarSystemId])[loc.solarSystemId] else { return }
            origin = (loc.solarSystemId, s.name)
        }
        .task(id: "\(origin?.id ?? 0)/\(galaxy?.count ?? 0)") { countJumps() }
    }

    private var filters: some View {
        Card {
            HStack(spacing: 6) {
                Text("Level").font(.ui(11)).foregroundStyle(C.muted)
                ForEach(1...5, id: \.self) { l in
                    Button("\(l)") { level = l }.buttonStyle(CanopusButtonStyle(kind: level == l ? .primary : .ghost, small: true))
                }
                Spacer(minLength: 4)
                Button(highsecOnly ? String(localized: "✓ Highsec only") : String(localized: "Highsec only")) { highsecOnly.toggle() }
                    .buttonStyle(CanopusButtonStyle(kind: highsecOnly ? .primary : .ghost, small: true))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(divisions, id: \.self) { d in
                        Button(divisionLabel(d)) { division = d }.buttonStyle(CanopusButtonStyle(kind: division == d ? .primary : .ghost, small: true))
                    }
                    Button("Any") { division = "" }.buttonStyle(CanopusButtonStyle(kind: division.isEmpty ? .primary : .ghost, small: true))
                }
            }
            TextField("Corporation or agent…", text: $query)
                .font(.ui(14)).autocorrectionDisabled().textInputAutocapitalization(.never)
                .padding(.horizontal, 10).frame(minHeight: 36)
                .background(C.panel2, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(C.border))
            SystemPicker(label: "Count jumps from", picked: $origin)
            if let status { Text(verbatim: status).font(.ui(11)).foregroundStyle(C.muted) }
        }
    }

    @ViewBuilder private func list(_ all: [AgentEntry]) -> some View {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let g = galaxy
        let sec = { (id: Int?) -> Double in id.flatMap { g?.index[$0] }.map { g!.security[$0] } ?? 0 }
        let shown = all.filter { a in
            a.level == level && (division == "Locator" ? a.isLocator : division.isEmpty || a.division == division)
                && (!highsecOnly || C.roundSec(sec(a.systemId)) >= 0.5)
                && (q.isEmpty || a.corporation.lowercased().contains(q) || a.name.lowercased().contains(q))
        }
        .sorted { (jumps[$0.systemId ?? 0] ?? 999, $0.corporation) < (jumps[$1.systemId ?? 0] ?? 999, $1.corporation) }
        Card(String(localized: "Agents: \(shown.count)")) {
            if shown.isEmpty { Text("No agents match.").font(.ui(13)).foregroundStyle(C.muted) }
            ForEach(shown.prefix(150)) { a in row(a, sec: sec(a.systemId)) }
            if shown.count > 150 { Text("The nearest 150 are shown.").font(.ui(11)).foregroundStyle(C.faint) }
        }
    }

    private func row(_ a: AgentEntry, sec: Double) -> some View {
        Button {
            guard let svc = env.characterStore.selectedService else { return }
            Task {
                do { try await svc.openInfoInGame(targetId: a.id); status = String(localized: "\(a.name): opened in the game") }
                catch { status = String(localized: "The game didn't answer: is the character logged in?") }
            }
        } label: {
            HStack(spacing: 8) {
                EVECorpLogo(corpId: a.corporationId, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(verbatim: a.name).font(.ui(13, .semibold)).foregroundStyle(C.text).lineLimit(1)
                        Text(verbatim: "L\(a.level)").font(.mono(10)).foregroundStyle(C.muted)
                        if !a.inStation { Pill(text: "In space", color: C.warn) }
                    }
                    Text(verbatim: "\(a.corporation) · \(divisionLabel(a.division))").font(.ui(11)).foregroundStyle(C.muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 4) {
                        SecText(value: sec)
                        Text(verbatim: a.systemId.flatMap { galaxy?.index[$0] }.map { galaxy!.names[$0] } ?? "—").font(.ui(12)).foregroundStyle(C.text)
                    }
                    if let j = a.systemId.flatMap({ jumps[$0] }) { Text("\(j) j.").font(.mono(11)).foregroundStyle(C.accentText) }
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Division names in the app's language (their own keys: "Security" alone means something else).
    private func divisionLabel(_ d: String) -> String {
        switch d {
        case "Security": String(localized: "Security division")
        case "Distribution": String(localized: "Distribution division")
        case "Mining": String(localized: "Mining division")
        case "R&D": String(localized: "R&D division")
        case "Locator": String(localized: "Locators")
        default: d
        }
    }

    /// Gate jumps from the origin to every system (breadth-first over the map).
    private func countJumps() {
        guard let g = galaxy, let origin, let start = g.index[origin.id] else { jumps = [:]; return }
        var dist = [start: 0]
        var frontier = [start]
        var d = 0
        while !frontier.isEmpty, d < 60 {
            d += 1
            var next: [Int] = []
            for i in frontier { for n in g.neighbors[i] where dist[n] == nil { dist[n] = d; next.append(n) } }
            frontier = next
        }
        jumps = Dictionary(uniqueKeysWithValues: dist.map { (g.ids[$0.key], $0.value) })
    }
}
