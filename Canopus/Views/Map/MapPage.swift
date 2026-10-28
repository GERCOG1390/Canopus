// The map page (the desktop's GalaxyMap panels): search, where am I, views, layers, the selected
// system's card, the route with its danger (kills in the last hour), avoided systems and notes.

import SwiftUI
import EVEAuth
import EVEStaticData

struct MapPage: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var galaxy: GalaxyData?
    @State private var error: Error?
    @State private var controller = GalaxyController()
    @State private var overlay = GalaxyOverlay()
    @State private var kills: [Int: ESISystemKills] = [:]
    @State private var jumps: [Int: Int] = [:]
    @State private var selected: Int?
    @State private var routeFrom: Int?
    @State private var routeTo: Int?
    @State private var flag: ESIRouteFlag = .secure
    @State private var route: [Int] = []
    @State private var routeError: Error?
    @State private var routing = false
    @State private var search = ""
    @State private var marks = SystemMarks.load()

    var body: some View {
        ZStack(alignment: .top) {
            C.bg.ignoresSafeArea()
            if let galaxy {
                GalaxyMapView(data: galaxy, overlay: overlay, controller: controller)
                    .ignoresSafeArea(edges: .bottom)
                VStack(spacing: 8) {
                    toolbar(galaxy)
                    Spacer()
                    // A phone keeps the map visible: no legend, panels in the lower part, scrolling.
                    if sizeClass != .compact {
                        HStack(alignment: .bottom, spacing: 10) {
                            legend
                            Spacer(minLength: 0)
                        }
                    }
                    GeometryReader { geo in
                        VStack {
                            Spacer(minLength: 0)
                            ScrollView { panels(galaxy) }
                                .scrollBounceBehavior(.basedOnSize)
                                .frame(maxHeight: sizeClass == .compact ? geo.size.height : .infinity)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxHeight: sizeClass == .compact ? 300 : 520)
                }
                .padding(12)
            } else if let error {
                EmptyState("Map unavailable", icon: "win_map") { Text(error.localizedDescription) }
            } else {
                ProgressView().tint(C.accent).padding(.top, 80)
            }
        }
        .task(id: env.repositoryVersion) { await load() }
        .task { await loadTraffic() }
        .task(id: "\(origin ?? 0)-\(routeTo ?? 0)-\(flag.rawValue)-\(marks.avoid.sorted())") { await loadRoute() }
        .onChange(of: selected) { syncOverlay() }
        .onChange(of: route) { syncOverlay() }
        .onChange(of: marks) { marks.save(); syncOverlay() }
    }

    // MARK: Data

    private var origin: Int? { routeFrom ?? overlay.current }

    private func load() async {
        guard let repo = env.repository else { return }
        do {
            let g = try await repo.galaxy()
            guard g.count > 0 else { throw MapError.noSystems }
            galaxy = g
            controller.onSelect = { selected = $0 }
            if let svc = env.characterStore.selectedService, let loc = try? await svc.location() {
                overlay.current = loc.solarSystemId
            }
            syncOverlay()
            #if DEBUG
            // Debug builds: `-mapFly Jita`, `-mapRoute Jita:Amarr` (screenshots, UI checks).
            let byName = { (n: String) in g.names.firstIndex(of: n).map { g.ids[$0] } }
            if let parts = UserDefaults.standard.string(forKey: "mapRoute")?.split(separator: ":"), parts.count == 2,
               let a = byName(String(parts[0])), let b = byName(String(parts[1])) {
                routeFrom = a
                routeTo = b
                selected = b
            } else if let n = UserDefaults.standard.string(forKey: "mapFly"), let id = byName(n) {
                try? await Task.sleep(for: .milliseconds(500))
                controller.fly(to: id)
            }
            #endif
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }

    /// Kills and jumps in the last hour; ESI refreshes them hourly, checked every 10 minutes.
    private func loadTraffic() async {
        while !Task.isCancelled {
            let market = MarketService()
            if let k = try? await market.systemKills() {
                kills = Dictionary(uniqueKeysWithValues: k.map { ($0.systemId, $0) })
                syncOverlay()
            }
            if let j = try? await market.systemJumps() {
                jumps = Dictionary(uniqueKeysWithValues: j.map { ($0.systemId, $0.shipJumps) })
            }
            try? await Task.sleep(for: .seconds(600))
        }
    }

    private func loadRoute() async {
        route = []
        routeError = nil
        guard let from = origin, let to = routeTo, from != to else { return }
        routing = true
        defer { routing = false }
        // ESI refuses the start or the end in the avoid list.
        let avoid = marks.avoid.filter { $0 != from && $0 != to }.sorted()
        do {
            route = try await MarketService().route(from: from, to: to, flag: flag, avoid: avoid)
            controller.fit(route)
        } catch {
            if !error.isCancellation { routeError = error }
        }
    }

    private func syncOverlay() {
        var o = overlay
        o.kills = kills.mapValues { $0.shipKills + $0.podKills }
        o.route = route
        o.selected = selected
        o.avoid = Set(marks.avoid)
        o.noted = Set(marks.notes.keys)
        overlay = o
    }

    private func pvp(_ id: Int) -> Int { kills[id].map { $0.shipKills + $0.podKills } ?? 0 }

    // MARK: Toolbar

    private func toolbar(_ g: GalaxyData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Glyph(name: .search, size: 14).foregroundStyle(C.muted)
                    TextField("Find a system…", text: $search)
                        .font(.ui(14))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(C.card, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(C.border, lineWidth: 1))
                .frame(maxWidth: 320)
                if let current = overlay.current {
                    Button("Where am I") { controller.fly(to: current) }.buttonStyle(.canopusGhost)
                }
            }
            if !search.isEmpty {
                let hits = matches(g)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(hits, id: \.self) { i in
                        Button {
                            search = ""
                            controller.fly(to: g.ids[i])
                        } label: {
                            HStack {
                                Text(verbatim: g.names[i]).font(.ui(14)).foregroundStyle(C.text)
                                SecText(value: g.security[i])
                                Text(verbatim: g.regionNames[g.region[i]]).font(.ui(12)).foregroundStyle(C.muted)
                                Spacer()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if hits.isEmpty {
                        Text("No such system").font(.ui(13)).foregroundStyle(C.muted).padding(10)
                    }
                }
                .frame(maxWidth: 320, alignment: .leading)
                .canopusSurface(padding: 0)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button("Top") { controller.show(.top) }.buttonStyle(.canopusSmall)
                    Button("Side") { controller.show(.side) }.buttonStyle(.canopusSmall)
                    Button("Whole map") { controller.show(.all) }.buttonStyle(.canopusSmall)
                    toggle("Stargates", $overlay.showGates)
                    toggle("Kills in the last hour", $overlay.showKills)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggle(_ label: LocalizedStringKey, _ value: Binding<Bool>) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(value.wrappedValue ? C.accent : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(value.wrappedValue ? .clear : C.lineStrong, lineWidth: 1))
                    .overlay(value.wrappedValue ? Text(verbatim: "✓").font(.ui(10, .bold)).foregroundStyle(C.onAccent) : nil)
                    .frame(width: 14, height: 14)
                Text(label)
            }
        }
        .buttonStyle(.canopusSmall)
    }

    /// Systems whose name starts with the search first, then those containing it.
    private func matches(_ g: GalaxyData) -> [Int] {
        let q = search.lowercased()
        var starts: [Int] = [], contains: [Int] = []
        for i in 0..<g.count {
            let n = g.names[i].lowercased()
            if n.hasPrefix(q) { starts.append(i) } else if n.contains(q) { contains.append(i) }
            if starts.count >= 8 { break }
        }
        return Array((starts + contains).prefix(8))
    }

    // MARK: Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: 3) {
            legendRow(Circle().fill(C.sec(1)), "highsec")
            legendRow(Circle().fill(C.sec(0.3)), "lowsec")
            legendRow(Circle().fill(C.sec(-0.5)), "nullsec")
            if overlay.showKills {
                legendRow(Circle().fill(Color(red: 1, green: 0x4A / 255, blue: 0x2E / 255).opacity(0.6)), "kills in the last hour")
            }
            if overlay.current != nil { legendRow(Circle().strokeBorder(C.accent, lineWidth: 2), "you are here") }
            if !marks.avoid.isEmpty { legendRow(Circle().strokeBorder(C.muted, lineWidth: 2), "avoided") }
            if !marks.notes.isEmpty { legendRow(Text(verbatim: "✎").font(.ui(10)).foregroundStyle(C.warn), "note") }
        }
        .padding(8)
        .background(C.panel.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
    }

    private func legendRow<Mark: View>(_ mark: Mark, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            mark.frame(width: 9, height: 9)
            Text(label).font(.ui(11)).foregroundStyle(C.text2)
        }
    }

    // MARK: Panels

    @ViewBuilder private func panels(_ g: GalaxyData) -> some View {
        VStack(spacing: 8) {
            // The route's own ends are in the route panel already.
            if let id = selected, let i = g.index[id], route.isEmpty || (id != routeTo && id != origin) {
                systemCard(g, id: id, i: i)
            }
            if routeTo != nil {
                routePanel(g)
            }
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func systemCard(_ g: GalaxyData, id: Int, i: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: g.names[i]).font(.display(18)).foregroundStyle(C.text)
                SecText(value: g.security[i])
                Spacer()
                Button("✕") { selected = nil }.buttonStyle(.canopusSmall)
            }
            Text(verbatim: g.regionNames[g.region[i]]).font(.ui(13)).foregroundStyle(C.muted)
            HStack(spacing: 14) {
                if pvp(id) > 0 { Text("Kills in the last hour: \(pvp(id))").foregroundStyle(C.bad) }
                if let k = kills[id], k.npcKills > 0 { Text("NPCs: \(k.npcKills)").foregroundStyle(C.muted) }
                if let j = jumps[id] { Text("Jumps: \(j)").foregroundStyle(C.muted) }
            }
            .font(.ui(12))
            HStack(spacing: 6) {
                Button("Route here") { routeTo = id }
                    .buttonStyle(.canopusSmall)
                    .disabled(origin == nil || origin == id)
                Button("From here") { routeFrom = id }.buttonStyle(.canopusSmall)
                Button(marks.avoid.contains(id) ? "Avoided" : "Avoid") {
                    if marks.avoid.contains(id) { marks.avoid.removeAll { $0 == id } } else { marks.avoid.append(id) }
                }
                .buttonStyle(CanopusButtonStyle(kind: marks.avoid.contains(id) ? .primary : .ghost, small: true))
            }
            if origin == nil {
                Text("Pick the route's start first: From here").font(.ui(11)).foregroundStyle(C.faint)
            }
            NoteField(text: Binding(get: { marks.notes[id] ?? "" }, set: { marks.notes[id] = $0.isEmpty ? nil : $0 }))
        }
        .canopusSurface(padding: 12)
    }

    private func routePanel(_ g: GalaxyData) -> some View {
        let name = { (id: Int?) in id.flatMap { g.index[$0] }.map { g.names[$0] } ?? "—" }
        let sec = { (id: Int) in g.index[id].map { g.security[$0] } ?? 0 }
        var count = (high: 0, low: 0, null: 0)
        for id in route.dropFirst() {
            let r = C.roundSec(sec(id))
            if r >= 0.5 { count.high += 1 } else if r > 0 { count.low += 1 } else { count.null += 1 }
        }
        let hot = route.map { ($0, pvp($0)) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: "\(name(origin)) → \(name(routeTo))").font(.ui(15, .semibold)).foregroundStyle(C.text)
                Spacer()
                Button("✕") { routeTo = nil; routeFrom = nil }.buttonStyle(.canopusSmall)
            }
            HStack(spacing: 6) {
                ForEach(ESIRouteFlag.allCases, id: \.self) { f in
                    Button(LocalizedStringKey(f.label)) { flag = f }
                        .buttonStyle(CanopusButtonStyle(kind: flag == f ? .primary : .ghost, small: true))
                }
            }
            let avoided = marks.avoid.filter { $0 != origin && $0 != routeTo }.count
            if avoided > 0 {
                HStack {
                    Text("Avoids \(avoided) systems").font(.ui(12)).foregroundStyle(C.muted)
                    Button("reset") { marks.avoid = [] }.font(.ui(12)).foregroundStyle(C.accentText)
                }
            }
            if routing && route.isEmpty {
                Text("Plotting…").font(.ui(13)).foregroundStyle(C.muted)
            } else if let routeError {
                Text(routeError.localizedDescription).font(.ui(12)).foregroundStyle(C.bad)
            } else if !route.isEmpty {
                HStack(spacing: 4) {
                    Text("\(route.count - 1) jumps").font(.ui(14, .semibold)).foregroundStyle(C.text)
                    Text(verbatim: "·").foregroundStyle(C.muted)
                    Text(verbatim: "\(count.high)").foregroundStyle(C.sec(1))
                    Text(verbatim: "/").foregroundStyle(C.muted)
                    Text(verbatim: "\(count.low)").foregroundStyle(C.sec(0.3))
                    Text(verbatim: "/").foregroundStyle(C.muted)
                    Text(verbatim: "\(count.null)").foregroundStyle(C.sec(-0.5))
                }
                .font(.mono(13))
                if hot.isEmpty {
                    Text("No kills on the route in the last hour").font(.ui(12)).foregroundStyle(C.muted)
                } else {
                    Text("Kills on the route in the last hour: \(hot.reduce(0) { $0 + $1.1 })").font(.ui(12, .medium)).foregroundStyle(C.bad)
                    ForEach(hot.prefix(sizeClass == .compact ? 3 : 5), id: \.0) { id, n in
                        Button { controller.fly(to: id) } label: {
                            HStack(spacing: 6) {
                                Text(verbatim: name(id)).foregroundStyle(C.accentText)
                                Text(verbatim: "\(n)").foregroundStyle(C.muted)
                            }
                            .font(.ui(12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .canopusSurface(padding: 12)
    }
}

private enum MapError: LocalizedError {
    case noSystems
    var errorDescription: String? {
        String(localized: "The game database has no map yet. It arrives with the next database update.")
    }
}

private extension ESIRouteFlag {
    var label: String {
        switch self {
        case .secure: "Safest"
        case .shortest: "Shortest"
        case .insecure: "Through low/null"
        }
    }
}

/// The pilot's own marks on systems: avoided by routes, and free-text notes (kept on this device).
struct SystemMarks: Codable, Equatable {
    var avoid: [Int] = []
    var notes: [Int: String] = [:]

    private static let key = "map.systemMarks"

    static func load() -> SystemMarks {
        (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode(SystemMarks.self, from: $0) } ?? SystemMarks()
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) }
    }
}

private struct NoteField: View {
    @Binding var text: String
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Note on this system…", text: $draft, axis: .vertical)
            .font(.ui(13))
            .lineLimit(1...4)
            .focused($focused)
            .padding(8)
            .background(C.card, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(C.border, lineWidth: 1))
            .onAppear { draft = text }
            .onChange(of: text) { if !focused { draft = text } }
            .onChange(of: focused) { if !focused { text = draft.trimmingCharacters(in: .whitespacesAndNewlines) } }
            .onSubmit { text = draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}
