// The map page (the desktop's GalaxyMap panels): search, where am I, views, layers, the selected
// system's card, the route with its danger (kills in the last hour), avoided systems and notes.

import SwiftUI
import simd
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
    @State private var bridgeHops = 0
    // Sovereignty
    @State private var showSov = false
    @State private var sov: SovData?
    @State private var sovError: Error?
    // Jump bridges
    @State private var bridges = BridgeStore.load()
    @State private var showBridges = true
    @State private var viaBridges = true
    @State private var bridgesOpen = false
    // Capital jump range
    @State private var jumpFrom: Int?
    @State private var jumpShips: [JumpDriveShip] = []
    @State private var jumpShip: JumpDriveShip?
    @State private var jumpAll5 = true
    @State private var jdcLevel: Int?

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
        .task(id: "\(origin ?? 0)-\(routeTo ?? 0)-\(flag.rawValue)-\(marks.avoid.sorted())-\(viaBridges)-\(bridges.list.count)") { await loadRoute() }
        .task(id: showSov) { await loadSov() }
        .task(id: jumpAll5) { await loadJdc() }
        .onChange(of: selected) { syncOverlay() }
        .onChange(of: bridges) { bridges.save(); syncOverlay() }
        .onChange(of: showBridges) { syncOverlay() }
        .onChange(of: jumpKey) { syncOverlay(); if let j = overlay.jump { controller.fit([j.from] + j.systems) } }
        .sheet(isPresented: $bridgesOpen) {
            if let galaxy {
                NavigationStack { BridgesSheet(galaxy: galaxy, store: $bridges, onSystem: { bridgesOpen = false; controller.fly(to: $0) }) }
            }
        }
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
            }
            // `-mapSov YES`, `-mapJump 1DQ1-A:Thanatos`, `-mapBridges "A » B;C » D"`.
            if UserDefaults.standard.bool(forKey: "mapSov") { showSov = true }
            if let text = UserDefaults.standard.string(forKey: "mapBridges") {
                bridges.text = text.replacingOccurrences(of: ";", with: "\n")
                bridges.list = MapLogic.parseBridges(bridges.text, galaxy: g).bridges
            }
            if let parts = UserDefaults.standard.string(forKey: "mapJump")?.split(separator: ":"), parts.count == 2, let id = byName(String(parts[0])) {
                await loadJdc()
                jumpShip = jumpShips.first { $0.name == parts[1] }
                jumpFrom = id
                selected = id
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
        bridgeHops = 0
        defer { routing = false }
        // ESI refuses the start or the end in the avoid list.
        let avoid = marks.avoid.filter { $0 != from && $0 != to }.sorted()
        // ESI routes over stargates only. With jump bridges the route is worked out here, and used only
        // when it actually takes a bridge: otherwise ESI's route is exactly the game's.
        if viaBridges, !bridges.list.isEmpty, let g = galaxy,
           let local = MapLogic.route(g, from: from, to: to, flag: flag.rawValue, bridges: bridges.list, avoid: avoid), local.bridgeHops > 0 {
            route = local.ids
            bridgeHops = local.bridgeHops
            controller.fit(route)
            return
        }
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
        o.sovColors = showSov ? sov?.systemColors : nil
        o.skyhooks = showSov ? Array(sov?.skyhooks.keys ?? [:].keys) : []
        o.timers = showSov ? Array(sov?.timers.keys ?? [:].keys) : []
        o.bridges = showBridges ? bridges.list : []
        o.jump = jumpReach
        overlay = o
    }

    // MARK: Sovereignty

    /// Who holds each system, raidable Skyhooks and sovereignty timers (public ESI), every 10 minutes.
    private func loadSov() async {
        guard showSov else { syncOverlay(); return }
        while !Task.isCancelled {
            do {
                let market = MarketService()
                async let systems = market.sovereignty()
                async let hooks = market.raidableSkyhooks()
                async let campaigns = market.sovereigntyCampaigns()
                sov = try await SovData(systems: systems, skyhooks: (try? await hooks) ?? [], campaigns: (try? await campaigns) ?? [], market: market)
                sovError = nil
            } catch {
                if error.isCancellation { return }
                sovError = error
            }
            syncOverlay()
            try? await Task.sleep(for: .seconds(600))
        }
    }

    // MARK: Capital jump range

    /// Jump Drive Calibration: V, or the character's level.
    private func loadJdc() async {
        if jumpShips.isEmpty, let repo = env.repository { jumpShips = (try? await repo.jumpDriveShips()) ?? [] }
        guard !jumpAll5, let svc = env.characterStore.selectedService else { jdcLevel = 5; return }
        let skills = try? await svc.skills()
        jdcLevel = skills?.skills.first { $0.skillId == 21611 }?.activeSkillLevel ?? 0
    }

    /// Base range × (1 + 20% per Jump Drive Calibration level), light years.
    private var jumpRange: Float {
        guard let ship = jumpShip else { return 0 }
        return Float(ship.baseRange * (1 + 0.2 * Double(jdcLevel ?? 5)))
    }

    private var jumpReach: GalaxyJump? {
        guard let from = jumpFrom, let g = galaxy, let i = g.index[from], jumpRange > 0 else { return nil }
        let p = g.positions[i]
        let systems = (0..<g.count).filter { j in j != i && g.jumpable[j] && simd_length(g.positions[j] - p) <= jumpRange }.map { g.ids[$0] }
        return GalaxyJump(from: from, range: jumpRange, systems: systems)
    }

    private var jumpKey: String { "\(jumpFrom ?? 0)-\(jumpShip?.id ?? 0)-\(jdcLevel ?? -1)" }

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
                    toggle("Sovereignty", $showSov)
                    Button(bridges.list.isEmpty ? String(localized: "Bridges") : String(localized: "Bridges: \(bridges.list.count)")) { bridgesOpen = true }
                        .buttonStyle(.canopusSmall)
                    if !bridges.list.isEmpty { toggle("Show bridges", $showBridges) }
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
            if showSov, let sov {
                ForEach(sov.top, id: \.id) { a in
                    HStack(spacing: 6) {
                        Circle().fill(Color(rgba: sov.allianceColors[a.id] ?? .one)).frame(width: 9, height: 9)
                        Text(verbatim: sov.names[a.id] ?? "#\(a.id)").font(.ui(11)).foregroundStyle(C.text2).lineLimit(1)
                        Text(verbatim: "\(a.count)").font(.mono(10)).foregroundStyle(C.faint)
                    }
                }
                legendRow(Circle().fill(Color(red: 0xC7 / 255, green: 0x7D / 255, blue: 1)), "Skyhooks open to theft: \(sov.skyhooks.count)")
                legendRow(Circle().fill(Color(red: 1, green: 0x9F / 255, blue: 0x1C / 255)), "Sovereignty timers: \(sov.timers.count)")
            } else if showSov, let sovError {
                Text(sovError.localizedDescription).font(.ui(11)).foregroundStyle(C.bad)
            } else {
                legendRow(Circle().fill(C.sec(1)), "highsec")
                legendRow(Circle().fill(C.sec(0.3)), "lowsec")
                legendRow(Circle().fill(C.sec(-0.5)), "nullsec")
            }
            if overlay.showKills {
                legendRow(Circle().fill(Color(red: 1, green: 0x4A / 255, blue: 0x2E / 255).opacity(0.6)), "kills in the last hour")
            }
            if overlay.current != nil { legendRow(Circle().strokeBorder(C.accent, lineWidth: 2), "you are here") }
            if !marks.avoid.isEmpty { legendRow(Circle().strokeBorder(C.muted, lineWidth: 2), "avoided") }
            if !marks.notes.isEmpty { legendRow(Text(verbatim: "✎").font(.ui(10)).foregroundStyle(C.warn), "note") }
            if showBridges && !bridges.list.isEmpty { legendRow(Rectangle().fill(C.star).frame(height: 2), "bridges") }
            if jumpReach != nil { legendRow(Circle().fill(Color(red: 0x8E / 255, green: 0xCB / 255, blue: 1)), "in jump range") }
        }
        .padding(8)
        .background(C.panel.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
    }

    private func legendRow<Mark: View>(_ mark: Mark, _ label: String.LocalizationValue) -> some View {
        legendRow(mark, Text(String(localized: label)))
    }

    private func legendRow<Mark: View>(_ mark: Mark, _ label: Text) -> some View {
        HStack(spacing: 6) {
            mark.frame(width: 9, height: 9)
            label.font(.ui(11)).foregroundStyle(C.text2)
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
            if jumpFrom != nil {
                jumpPanel(g)
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
            if showSov, let sov, let info = sov.systems[id] {
                VStack(alignment: .leading, spacing: 2) {
                    if let a = info.alliance {
                        Text(verbatim: sov.names[a] ?? "#\(a)").foregroundStyle(Color(rgba: sov.allianceColors[a] ?? .one))
                    }
                    if let end = sov.skyhooks[id] {
                        Text("Skyhook open to theft until \(Self.eveTime(end)) EVE").foregroundStyle(Color(red: 0xC7 / 255, green: 0x7D / 255, blue: 1))
                    }
                    if let t = sov.timers[id] {
                        Text("Sovereignty timer: \(t.event) · \(Self.eveDateTime(t.start)) EVE").foregroundStyle(Color(red: 1, green: 0x9F / 255, blue: 0x1C / 255))
                    }
                }
                .font(.ui(12))
            }
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
            Button("Capital jump from here") { jumpFrom = id }.buttonStyle(.canopusSmall)
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
            if !bridges.list.isEmpty {
                toggle("Through the alliance's bridges", $viaBridges)
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
                if bridgeHops > 0 {
                    (Text("Over bridges: \(bridgeHops)").foregroundColor(C.star) + Text(" · subcapitals only").foregroundColor(C.muted))
                        .font(.ui(12))
                    if flag != .shortest {
                        Text("Canopus works out routes with bridges: the safe one can differ from the game's by a couple of jumps.")
                            .font(.ui(11)).foregroundStyle(C.faint)
                    }
                }
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

extension MapPage {
    fileprivate func jumpPanel(_ g: GalaxyData) -> some View {
        let name = jumpFrom.flatMap { g.index[$0] }.map { g.names[$0] } ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Jump from \(name)").font(.ui(15, .semibold)).foregroundStyle(C.text)
                Spacer()
                Button("✕") { jumpFrom = nil }.buttonStyle(.canopusSmall)
            }
            Menu {
                ForEach(jumpShips) { ship in
                    Button(ship.name) { jumpShip = ship }
                }
            } label: {
                Text(jumpShip?.name ?? String(localized: "Pick a ship with a jump drive")).font(.ui(13))
            }
            .buttonStyle(.canopusGhost)
            HStack(spacing: 6) {
                Button("Jump Drive Calibration V") { jumpAll5 = true }
                    .buttonStyle(CanopusButtonStyle(kind: jumpAll5 ? .primary : .ghost, small: true))
                if env.characterStore.selectedService != nil {
                    Button("Character's skills") { jumpAll5 = false }
                        .buttonStyle(CanopusButtonStyle(kind: jumpAll5 ? .ghost : .primary, small: true))
                }
            }
            if jumpShip != nil, jumpRange > 0 {
                HStack(spacing: 6) {
                    Text(verbatim: String(format: "%.2f ly", jumpRange)).font(.mono(14, medium: true)).foregroundStyle(C.text)
                    Text(verbatim: "· JDC \(jdcLevel ?? 5)").font(.ui(12)).foregroundStyle(C.muted)
                }
                Text("Systems in range: \(jumpReach?.systems.count ?? 0)").font(.ui(13)).foregroundStyle(C.text2)
                Text("Highsec and Pochven can't be jumped to. Bridges are closed to capitals.").font(.ui(11)).foregroundStyle(C.faint)
            }
        }
        .canopusSurface(padding: 12)
    }

    fileprivate static func eveTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    fileprivate static func eveDateTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }
}

/// Sovereignty as the map shows it: holder colours (the ten biggest alliances distinct), names, Skyhooks, timers.
struct SovData {
    struct Holder { let alliance: Int?; let faction: Int? }
    let systems: [Int: Holder]
    let skyhooks: [Int: Date]
    let timers: [Int: (event: String, start: Date)]
    let top: [(id: Int, count: Int)]
    let allianceColors: [Int: SIMD4<Float>]
    let names: [Int: String]

    @MainActor
    init(systems list: [ESISovereigntySystem], skyhooks hooks: [ESIRaidableSkyhook], campaigns: [ESISovereigntyCampaign], market: MarketService) async throws {
        var systems: [Int: Holder] = [:]
        var counts: [Int: Int] = [:]
        for s in list {
            let a = s.claim?.alliance?.allianceId
            systems[s.solarSystemId] = Holder(alliance: a, faction: a == nil ? s.claim?.faction?.factionId : nil)
            if let a { counts[a, default: 0] += 1 }
        }
        var skyhooks: [Int: Date] = [:]
        for h in hooks { skyhooks[h.solarSystemId] = max(skyhooks[h.solarSystemId] ?? .distantPast, h.theftVulnerability?.end ?? .distantPast) }
        var timers: [Int: (event: String, start: Date)] = [:]
        for c in campaigns { timers[c.solarSystemId] = (c.eventType, c.startTime) }
        let top = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(10).map { (id: $0.key, count: $0.value) }
        var colors = Dictionary(uniqueKeysWithValues: counts.keys.map { ($0, MapLogic.hashedColor($0)) })
        for (k, a) in top.enumerated() { colors[a.id] = MapLogic.color(hex: MapLogic.topColors[k]) }
        self.systems = systems
        self.skyhooks = skyhooks
        self.timers = timers
        self.top = top
        allianceColors = colors
        names = (try? await market.names(ids: Array(counts.keys))) ?? [:]
    }

    /// Star colour per system id (alliance holders only; the map dims the rest).
    var systemColors: [Int: SIMD4<Float>] {
        systems.reduce(into: [:]) { out, e in if let a = e.value.alliance { out[e.key] = allianceColors[a] } }
    }
}

extension Color {
    init(rgba v: SIMD4<Float>) {
        self.init(red: Double(v.x), green: Double(v.y), blue: Double(v.z), opacity: Double(v.w))
    }
}

/// Paste the alliance's jump bridges, pick the capital: distances show how far each bridge reaches.
private struct BridgesSheet: View {
    let galaxy: GalaxyData
    @Binding var store: BridgeStore
    let onSystem: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var unknown: [String] = []
    @State private var capitalSearch = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste the bridge list, one per line: \"1DQ1-A » 8WA-Z6\", Dotlan's format (\"1DQ1-A @ 3-4 » 8WA-Z6 @ 1-1\") or structure names. Since Cradle of War bridges take subcapitals only, and a jump costs more the farther it is from the alliance capital.")
                    .font(.ui(12)).foregroundStyle(C.muted)
                TextEditor(text: $text)
                    .font(.mono(13))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .padding(6)
                    .background(C.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(C.border, lineWidth: 1))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                HStack {
                    Button("Save") {
                        let r = MapLogic.parseBridges(text, galaxy: galaxy)
                        unknown = r.unknown
                        store.text = text
                        store.list = r.bridges
                    }
                    .buttonStyle(.canopus)
                    Text("Bridges found: \(store.list.count)").font(.ui(12)).foregroundStyle(C.muted)
                }
                if !unknown.isEmpty {
                    Text("Lines not recognised: \(unknown.count)").font(.ui(12)).foregroundStyle(C.bad)
                    ForEach(unknown.prefix(5), id: \.self) { Text(verbatim: $0).font(.mono(11)).foregroundStyle(C.muted) }
                }
                capital
                rows
            }
            .padding(16)
        }
        .background(C.bg)
        .navigationTitle("Alliance bridges (Ansiblex)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        .onAppear { text = store.text }
    }

    private func name(_ id: Int) -> String { galaxy.index[id].map { galaxy.names[$0] } ?? "#\(id)" }

    @ViewBuilder private var capital: some View {
        HStack(spacing: 8) {
            Text("Alliance capital:").font(.ui(13)).foregroundStyle(C.text2)
            if let c = store.capital {
                Button(name(c)) { onSystem(c) }.font(.ui(13)).foregroundStyle(C.accentText)
                Button("✕") { store.capital = nil }.buttonStyle(.canopusSmall)
            } else {
                TextField("Find a system…", text: $capitalSearch)
                    .font(.ui(13)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(6).background(C.card, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        if store.capital == nil, !capitalSearch.isEmpty {
            let q = capitalSearch.lowercased()
            ForEach((0..<galaxy.count).filter { galaxy.names[$0].lowercased().hasPrefix(q) }.prefix(6), id: \.self) { i in
                Button(galaxy.names[i]) { store.capital = galaxy.ids[i]; capitalSearch = "" }.font(.ui(13)).foregroundStyle(C.accentText)
            }
        }
    }

    @ViewBuilder private var rows: some View {
        // Cost grows with the distance from the capital to the bridge's far end.
        let list = store.list.map { b -> (b: GalaxyPair, len: Float?, far: Float?) in
            let far = store.capital.map { c in max(MapLogic.lightYears(galaxy, c, b.a) ?? 0, MapLogic.lightYears(galaxy, c, b.b) ?? 0) }
            return (b, MapLogic.lightYears(galaxy, b.a, b.b), far)
        }.sorted { ($0.far ?? 0) < ($1.far ?? 0) }
        if !list.isEmpty {
            VStack(spacing: 0) {
                HStack {
                    Text("Bridge").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Length, ly").frame(width: 80, alignment: .trailing)
                    if store.capital != nil { Text("From capital, ly").frame(width: 110, alignment: .trailing) }
                }
                .font(.ui(11, .medium)).foregroundStyle(C.muted).padding(.bottom, 6)
                ForEach(Array(list.enumerated()), id: \.offset) { _, r in
                    HStack {
                        HStack(spacing: 4) {
                            Button(name(r.b.a)) { onSystem(r.b.a) }
                            Text(verbatim: "⇄").foregroundStyle(C.muted)
                            Button(name(r.b.b)) { onSystem(r.b.b) }
                        }
                        .font(.ui(13)).foregroundStyle(C.accentText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: r.len.map { String(format: "%.1f", $0) } ?? "—").frame(width: 80, alignment: .trailing)
                        if store.capital != nil { Text(verbatim: r.far.map { String(format: "%.1f", $0) } ?? "—").frame(width: 110, alignment: .trailing) }
                    }
                    .font(.mono(12))
                    .padding(.vertical, 4)
                }
            }
            .canopusSurface(padding: 10)
        }
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
