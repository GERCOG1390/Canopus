// Planetary industry as the desktop's: the pilot's colonies (extractor timers, what each planet makes in
// an hour at Jita, storage) and the PI calculator (production chain for a P1–P4 product, raw resources
// and their planet types, profit after customs) with the colony finder. Schematics and planets per system
// come from the SDE (importer 6).

import SwiftUI
import Domain
import EVEAuth
import EVEStaticData
import UserNotifications

enum PlanetaryTab: String, CaseIterable {
    case colonies, calc

    var label: String {
        switch self {
        case .colonies: "My colonies"
        case .calc: "PI calculator"
        }
    }
}

struct PlanetaryPage: View {
    @State private var tab: PlanetaryTab = {
        #if DEBUG
        if let t = UserDefaults.standard.string(forKey: "piTab").flatMap(PlanetaryTab.init(rawValue:)) { return t }
        #endif
        return .colonies
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CanopusTabs(tabs: PlanetaryTab.allCases.map { (id: $0, label: $0.label) }, selection: $tab)
                .padding(.horizontal, 12).padding(.vertical, 8)
            ScrollView {
                Group {
                    switch tab {
                    case .colonies: ColoniesView()
                    case .calc: PICalculator()
                    }
                }
                .padding(16)
            }
            // Debug builds: `-piBottom YES` opens scrolled to the end (screenshots of the colony finder).
            .defaultScrollAnchor(UserDefaults.standard.bool(forKey: "piBottom") && _isDebugAssertConfiguration() ? .bottom : .top)
        }
        .background(C.bg)
        .navigationTitle("Planetary industry")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A planet type's name in the app's language.
func planetTypeName(_ id: Int) -> String {
    guard let n = PlanetTypes.names[id] else { return "" }
    return Bundle.main.preferredLocalizations.first == "ru" ? n.ru : n.en
}

private func rate(_ v: Double) -> String {
    v >= 100 ? v.formatted(.number.precision(.fractionLength(0))) : v.formatted(.number.precision(.fractionLength(0...1)))
}

// MARK: - My colonies

private struct Colony: Identifiable {
    let info: ESIPlanetColony
    let pins: [ESIPlanetLayout.Pin]
    let name: String
    let place: SystemPlace?
    /// Type → units an hour (running extractors and factories, less what the planet's factories use)
    let output: [(id: Int, perHour: Double)]
    let perHour: Double

    var id: Int { info.planetId }
    var extractors: [ESIPlanetLayout.Pin] { pins.filter { $0.extractorDetails != nil } }
    var factories: Int { pins.filter { $0.schematicId != nil }.count }
    var expiry: Date? { extractors.compactMap(\.expiryTime).min() }
    /// What sits in storage, launchpads and factories' buffers
    var stored: [(id: Int, amount: Int)] {
        var sum: [Int: Int] = [:]
        for p in pins where p.extractorDetails == nil && p.schematicId == nil { for c in p.contents ?? [] { sum[c.typeId, default: 0] += c.amount } }
        return sum.map { ($0.key, $0.value) }.sorted { $0.amount > $1.amount }
    }
}

private struct ColoniesView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var colonies: [Colony]?
    @State private var names: [Int: String] = [:]
    @State private var error: Error?
    @State private var noSchematics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if env.characterStore.selectedService == nil {
                Text("Sign in with a character to see the colonies.").font(.ui(13)).foregroundStyle(C.muted)
            } else if error != nil {
                ScopeHint(scope: "esi-planets.manage_planets.v1")
            } else if let colonies {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    content(colonies, now: ctx.date)
                }
            } else {
                ProgressView().tint(C.accent).frame(maxWidth: .infinity).padding(.top, 30)
            }
        }
        .task(id: env.dataKey) { await load() }
    }

    @ViewBuilder private func content(_ list: [Colony], now: Date) -> some View {
        let stopped = list.filter { ($0.expiry ?? .distantFuture) <= now }.count
        let income = list.reduce(0) { $0 + $1.perHour }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
            StatTile(label: "Colonies", value: "\(list.count)")
            StatTile(label: "Extractors stopped", value: "\(stopped)", valueColor: stopped > 0 ? C.bad : C.good)
            StatTile(label: "Output per hour (Jita sell)", value: Fmt.isk(income), sub: String(localized: "\(Fmt.isk(income * 24)) a day, before taxes"))
        }
        Card(title: nil, actions: {
            Button("Refresh") { Task { await load() } }.buttonStyle(.canopusSmall)
        }) {
            if list.isEmpty { Text("No colonies.").font(.ui(13)).foregroundStyle(C.muted) }
            ForEach(list.sorted { ($0.expiry ?? .distantFuture) < ($1.expiry ?? .distantFuture) }) { c in
                row(c, now: now)
                if c.id != list.last?.id { Divider().overlay(C.border) }
            }
            Text("ESI updates a colony only when you open it in the game. Output per hour: running extractors and factories (if they have input) minus what the planet's own factories use, at Jita sell before customs taxes.")
                .font(.ui(11)).foregroundStyle(C.faint)
            if noSchematics {
                Text("The SDE database has no PI schematics yet: factories are left out. Update the database in Settings.").font(.ui(11)).foregroundStyle(C.warn)
            }
        }
    }

    private func row(_ c: Colony, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let s = c.place { SecText(value: s.security) }
                Text(verbatim: c.name).font(.ui(14, .semibold)).foregroundStyle(C.text)
                Text(verbatim: planetTypeName(PlanetTypes.byESIName[c.info.planetType] ?? 0)).font(.ui(11)).foregroundStyle(C.muted)
                Spacer(minLength: 4)
                if let e = c.expiry {
                    let left = e.timeIntervalSince(now)
                    Text(left <= 0 ? String(localized: "Stopped") : Fmt.duration(seconds: left))
                        .font(.mono(12, medium: true)).foregroundStyle(left <= 0 ? C.bad : left < 6 * 3600 ? C.warn : C.text)
                }
            }
            Text("Command Center level \(c.info.upgradeLevel) · factories: \(c.factories) · updated \(c.info.lastUpdate.formatted(.relative(presentation: .named)))")
                .font(.ui(11)).foregroundStyle(C.muted)
            ForEach(c.extractors, id: \.pinId) { p in
                if let x = p.extractorDetails, let product = x.productTypeId {
                    HStack(spacing: 6) {
                        EVETypeIcon(typeId: product, size: 18)
                        Text(verbatim: names[product] ?? "#\(product)").font(.ui(12)).foregroundStyle(C.text).lineLimit(1)
                        Spacer(minLength: 4)
                        if let q = x.qtyPerCycle, let t = x.cycleTime, t > 0 {
                            Text(verbatim: "\(rate(Double(q) * 3600 / Double(t)))/h").font(.mono(11)).foregroundStyle(C.muted)
                        }
                        if let e = p.expiryTime {
                            Text(verbatim: e.formatted(date: .abbreviated, time: .shortened)).font(.mono(10)).foregroundStyle(e <= now ? C.bad : C.faint)
                        }
                    }
                }
            }
            if !c.output.isEmpty {
                FlowRow(spacing: 8) {
                    ForEach(c.output, id: \.id) { o in
                        HStack(spacing: 4) {
                            EVETypeIcon(typeId: o.id, size: 16)
                            Text(verbatim: "\(names[o.id] ?? "") \(rate(o.perHour))/h").font(.ui(11)).foregroundStyle(C.muted)
                        }
                    }
                }
                Text("≈ \(Fmt.isk(c.perHour)) an hour").font(.mono(11, medium: true)).foregroundStyle(C.accentText)
            }
            let stored = c.stored
            if !stored.isEmpty {
                Text(verbatim: stored.prefix(6).map { "\(names[$0.id] ?? "#\($0.id)") ×\($0.amount.formatted())" }.joined(separator: " · "))
                    .font(.ui(11)).foregroundStyle(C.faint)
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        guard let svc = env.characterStore.selectedService else { return }
        do {
            var list = try await svc.planets()
            var layouts = await withTaskGroup(of: (Int, [ESIPlanetLayout.Pin]).self) { group in
                for c in list { group.addTask { @MainActor in (c.planetId, (try? await svc.planet(c.planetId).pins) ?? []) } }
                var out: [Int: [ESIPlanetLayout.Pin]] = [:]
                for await (id, pins) in group { out[id] = pins }
                return out
            }
            #if DEBUG
            // Debug builds: `-piDemo YES` shows two sample colonies (screenshots without a PI character).
            if UserDefaults.standard.bool(forKey: "piDemo") { (list, layouts) = Self.demo() }
            #endif
            let repo = env.repository
            let schematics = (try? await repo?.planetSchematics()) ?? [:]
            let places = (try? await repo?.systemPlaces(ids: Set(list.map(\.solarSystemId)))) ?? [:]
            var planetNames: [Int: String] = [:]
            let market = MarketService()
            for c in list { planetNames[c.planetId] = try? await market.planetName(c.planetId) }
            // What each planet makes in an hour (as the desktop): running extractors plus factories assumed
            // fed, less what its own factories use up.
            let now = Date()
            var nets: [Int: [Int: Double]] = [:]
            for c in list {
                var net: [Int: Double] = [:]
                for p in layouts[c.planetId] ?? [] {
                    if let x = p.extractorDetails, let id = x.productTypeId, let q = x.qtyPerCycle, let t = x.cycleTime, t > 0,
                       let e = p.expiryTime, e > now {
                        net[id, default: 0] += Double(q) * 3600 / Double(t)
                    }
                    if let sid = p.schematicId, let s = schematics[sid], s.cycleTime > 0 {
                        let perHour = 3600 / Double(s.cycleTime)
                        net[s.output.typeId, default: 0] += Double(s.output.quantity) * perHour
                        for i in s.inputs { net[i.typeId, default: 0] -= Double(i.quantity) * perHour }
                    }
                }
                nets[c.planetId] = net
            }
            let outIds = Set(nets.values.flatMap { $0.filter { $0.value > 0.01 }.keys })
            let prices = (try? await HubPrices.jitaSell(typeIds: outIds)) ?? [:]
            var typeIds = outIds
            for pins in layouts.values { for p in pins { if let id = p.extractorDetails?.productTypeId { typeIds.insert(id) }; for c in p.contents ?? [] { typeIds.insert(c.typeId) } } }
            let typeNames = ((try? await repo?.types(ids: typeIds)) ?? [:]).mapValues(\.name)
            // A load started before the database reopened may finish after the new one: keep the newest.
            guard !Task.isCancelled else { return }
            noSchematics = schematics.isEmpty
            names = typeNames
            colonies = list.map { c in
                let output = (nets[c.planetId] ?? [:]).filter { $0.value > 0.01 }.map { (id: $0.key, perHour: $0.value) }.sorted { $0.perHour > $1.perHour }
                return Colony(info: c, pins: layouts[c.planetId] ?? [], name: planetNames[c.planetId] ?? "#\(c.planetId)", place: places[c.solarSystemId],
                              output: output, perHour: output.reduce(0) { $0 + $1.perHour * (prices[$1.id] ?? 0) })
            }
            error = nil
            await scheduleExtractorNotifications(colonies ?? [], character: env.characterStore.selectedService?.tokens.characterName ?? "")
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }

    #if DEBUG
    private static func demo() -> ([ESIPlanetColony], [Int: [ESIPlanetLayout.Pin]]) {
        let iso = { (h: Double) in ISO8601DateFormatter().string(from: Date().addingTimeInterval(h * 3600)) }
        let colonies = """
        [{"planet_id":40009235,"planet_type":"temperate","solar_system_id":30000144,"upgrade_level":5,"num_pins":12,"last_update":"\(iso(-20))"},
         {"planet_id":40009229,"planet_type":"barren","solar_system_id":30000144,"upgrade_level":4,"num_pins":9,"last_update":"\(iso(-50))"}]
        """
        let temperate = """
        {"pins":[{"pin_id":1,"type_id":3060,"expiry_time":"\(iso(31))","extractor_details":{"product_type_id":2305,"qty_per_cycle":6200,"cycle_time":1800}},
                 {"pin_id":2,"type_id":3060,"expiry_time":"\(iso(31))","extractor_details":{"product_type_id":2073,"qty_per_cycle":5100,"cycle_time":1800}},
                 {"pin_id":3,"type_id":2481,"schematic_id":135},{"pin_id":4,"type_id":2481,"schematic_id":135},
                 {"pin_id":5,"type_id":2481,"schematic_id":131},{"pin_id":6,"type_id":2481,"schematic_id":131},
                 {"pin_id":7,"type_id":2483,"schematic_id":69},
                 {"pin_id":8,"type_id":2257,"contents":[{"type_id":2393,"amount":12800},{"type_id":3683,"amount":9400},{"type_id":2329,"amount":420}]}]}
        """
        let barren = """
        {"pins":[{"pin_id":1,"type_id":3062,"expiry_time":"\(iso(-3))","extractor_details":{"product_type_id":2267,"qty_per_cycle":4300,"cycle_time":3600}},
                 {"pin_id":2,"type_id":3062,"expiry_time":"\(iso(-3))","extractor_details":{"product_type_id":2270,"qty_per_cycle":3900,"cycle_time":3600}}]}
        """
        let d = JSONDecoder.esi
        let list = (try? d.decode([ESIPlanetColony].self, from: Data(colonies.utf8))) ?? []
        return (list, [40009235: (try? d.decode(ESIPlanetLayout.self, from: Data(temperate.utf8)).pins) ?? [],
                       40009229: (try? d.decode(ESIPlanetLayout.self, from: Data(barren.utf8)).pins) ?? []])
    }
    #endif

    /// One notification per colony when its first extractor stops (Settings → Notifications).
    private func scheduleExtractorNotifications(_ list: [Colony], character: String) async {
        let center = UNUserNotificationCenter.current()
        let prefix = "canopus.pi.\(env.characterStore.selectedId ?? 0)."
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard NotificationSettings.shared.piExtractors, await center.notificationSettings().authorizationStatus == .authorized else { return }
        for c in list {
            guard let e = c.expiry, e > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Extractors stopped")
            content.body = String(localized: "\(character): \(c.name) — restart the extraction programs")
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: e)
            try? await center.add(UNNotificationRequest(identifier: prefix + "\(c.id)", content: content,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }
}

// MARK: - PI calculator

private struct PINode: Identifiable {
    enum Source { case build, buy, extract }
    let id = UUID()
    let type: Int
    let tier: Int
    /// Units an hour
    let rate: Double
    /// Factories running the schematic (fractional: how loaded)
    var factories: Double = 0
    let source: Source
    var children: [PINode] = []
}

private struct PICalculator: View {
    @Environment(AppEnvironment.self) private var env
    @State private var schematics: [Int: PlanetSchematic]?
    @State private var tiers: [Int: Int] = [:]
    @State private var bases: [Int: Double] = [:]
    @State private var names: [Int: String] = [:]
    @State private var tier = 2
    @State private var product: Int?
    @State private var startTier = 0
    @State private var rateInput: Double = 0
    @State private var tax: Double = 10
    @State private var sellToBuy = false
    @State private var taxImports = true
    @State private var prices: [Int: HubPrice] = [:]

    private var byOutput: [Int: PlanetSchematic] {
        Dictionary((schematics ?? [:]).values.map { ($0.output.typeId, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let schematics {
                if schematics.isEmpty {
                    Card { Text("The SDE database has no PI schematics yet. Update the database in Settings.").font(.ui(13)).foregroundStyle(C.muted) }
                } else {
                    form
                    if let product, let top = byOutput[product] { result(product, top) } else {
                        Text("Pick a product: the calculator shows the chain, the planets and the profit.").font(.ui(13)).foregroundStyle(C.muted)
                    }
                }
            } else {
                ProgressView().tint(C.accent).frame(maxWidth: .infinity).padding(.top, 30)
            }
        }
        .task(id: env.repositoryVersion) { await load() }
        .task(id: "\(product ?? 0)/\(startTier)") { await loadPrices() }
    }

    // MARK: Form

    private var form: some View {
        let products = byOutput.keys.filter { tiers[$0] == tier }.sorted { (names[$0] ?? "") < (names[$1] ?? "") }
        return Card(String(localized: "PI calculator")) {
            HStack(spacing: 6) {
                Text("Product tier").font(.ui(11)).foregroundStyle(C.muted)
                ForEach(1...4, id: \.self) { t in
                    Button("P\(t)") { tier = t; product = nil; startTier = min(startTier, t - 1) }
                        .buttonStyle(CanopusButtonStyle(kind: tier == t ? .primary : .ghost, small: true))
                }
            }
            Menu {
                ForEach(products, id: \.self) { id in
                    Button(names[id] ?? "#\(id)") { pick(id) }
                }
            } label: {
                HStack(spacing: 6) {
                    if let product { EVETypeIcon(typeId: product, size: 22) }
                    Text(verbatim: product.flatMap { names[$0] } ?? String(localized: "— choose a product —")).font(.ui(14)).foregroundStyle(C.text)
                    Spacer()
                    Text(verbatim: "▾").foregroundStyle(C.muted)
                }
                .padding(.horizontal, 10).frame(minHeight: 38)
                .background(C.panel2, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(C.border))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("Start from").font(.ui(11)).foregroundStyle(C.muted)
                    Button("extracting P0") { startTier = 0 }.buttonStyle(CanopusButtonStyle(kind: startTier == 0 ? .primary : .ghost, small: true))
                    ForEach(Array(1..<tier), id: \.self) { t in
                        Button("buying P\(t) at Jita") { startTier = t }.buttonStyle(CanopusButtonStyle(kind: startTier == t ? .primary : .ghost, small: true))
                    }
                }
            }
            FlowRow(spacing: 10) {
                NumberField(label: "Output, units/h", value: $rateInput)
                NumberField(label: "Customs tax, %", value: $tax)
            }
            HStack(spacing: 6) {
                Text("Sell the product").font(.ui(11)).foregroundStyle(C.muted)
                Button("Jita sell") { sellToBuy = false }.buttonStyle(CanopusButtonStyle(kind: sellToBuy ? .ghost : .primary, small: true))
                Button("Jita buy") { sellToBuy = true }.buttonStyle(CanopusButtonStyle(kind: sellToBuy ? .primary : .ghost, small: true))
            }
            Button(taxImports ? String(localized: "✓ Import tax on bought inputs") : String(localized: "Import tax on bought inputs")) { taxImports.toggle() }
                .buttonStyle(CanopusButtonStyle(kind: taxImports ? .primary : .ghost, small: true))
            if let product, let top = byOutput[product] {
                Text("One factory: \(top.output.quantity) units per \(top.cycleTime / 60) min cycle = \(rate(perFactory(top))) units/h.")
                    .font(.ui(11)).foregroundStyle(C.faint)
            }
        }
    }

    private func pick(_ id: Int) {
        product = id
        if let s = byOutput[id] { rateInput = perFactory(s) }
    }

    private func perFactory(_ s: PlanetSchematic) -> Double {
        Double(s.output.quantity) * 3600 / Double(max(1, s.cycleTime))
    }

    // MARK: Result

    private func build(_ type: Int, _ r: Double, depth: Int) -> PINode {
        let t = tiers[type] ?? 0
        if t == 0 { return PINode(type: type, tier: 0, rate: r, source: .extract) }
        guard depth == 0 || t > startTier, let s = byOutput[type], depth <= 6 else { return PINode(type: type, tier: t, rate: r, source: .buy) }
        let perCycle = Double(s.output.quantity) * 3600 / Double(max(1, s.cycleTime))
        return PINode(type: type, tier: t, rate: r, factories: r / perCycle, source: .build,
                      children: s.inputs.map { build($0.typeId, r / Double(s.output.quantity) * Double($0.quantity), depth: depth + 1) })
    }

    @ViewBuilder private func result(_ product: Int, _ top: PlanetSchematic) -> some View {
        let tree = build(product, max(0, rateInput), depth: 0)
        var buy: [Int: Double] = [:]
        var extract: [Int: Double] = [:]
        var factories: [Int: Double] = [:]
        let _ = walk(tree, buy: &buy, extract: &extract, factories: &factories)
        let sellPrice = sellToBuy ? (prices[product]?.buy ?? 0) : (prices[product]?.sell ?? 0)
        let revenue = rateInput * sellPrice
        let buyCost = buy.reduce(0) { $0 + $1.value * (prices[$1.key]?.sell ?? 0) }
        let exportTax = rateInput * (bases[product] ?? 0) * tax / 100
        let importTax = taxImports ? buy.reduce(0) { $0 + $1.value * (bases[$1.key] ?? 0) * tax / 100 * 0.5 } : 0
        let profit = revenue - buyCost - exportTax - importTax

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
            StatTile(label: "Revenue per hour", value: Fmt.isk(revenue), sub: "\(rate(rateInput)) × \(Fmt.isk(sellPrice))")
            StatTile(label: "Inputs per hour", value: Fmt.isk(buyCost), sub: startTier > 0 ? String(localized: "buying P\(startTier) at Jita sell") : String(localized: "all extracted"))
            StatTile(label: "Customs per hour", value: Fmt.isk(exportTax + importTax), sub: String(localized: "export \(Fmt.isk(exportTax)) · import \(Fmt.isk(importTax))"))
            StatTile(label: "Profit per hour", value: Fmt.isk(profit), sub: String(localized: "\(Fmt.isk(profit * 24)) a day"), valueColor: profit >= 0 ? C.good : C.bad)
        }
        Card(String(localized: "Production chain")) {
            nodeView(tree, depth: 0)
            Text("Factories: \(factories.sorted { $0.key > $1.key }.map { "P\($0.key) ×\(Int(($0.value - 1e-9).rounded(.up)))" }.joined(separator: " · "))")
                .font(.ui(11)).foregroundStyle(C.muted)
        }
        if !extract.isEmpty {
            Card(String(localized: "Raw resources and planets")) {
                ForEach(extract.sorted { $0.value > $1.value }, id: \.key) { id, r in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            EVETypeIcon(typeId: id, size: 20)
                            Text(verbatim: names[id] ?? "#\(id)").font(.ui(13)).foregroundStyle(C.text)
                            Spacer(minLength: 4)
                            Text(verbatim: "\(rate(r))/h").font(.mono(12)).foregroundStyle(C.muted)
                        }
                        Text(verbatim: (PlanetTypes.p0Planets[id] ?? []).map(planetTypeName).joined(separator: ", ")).font(.ui(11)).foregroundStyle(C.faint)
                    }
                }
                Text("What an extractor gives depends on the planet, the spot and the cycle time — check the resource scanner in the game.").font(.ui(11)).foregroundStyle(C.faint)
            }
        }
        if !buy.isEmpty {
            Card(String(localized: "Buy at Jita")) {
                ForEach(buy.sorted { $0.value > $1.value }, id: \.key) { id, r in
                    HStack(spacing: 6) {
                        EVETypeIcon(typeId: id, size: 20)
                        Text(verbatim: names[id] ?? "#\(id)").font(.ui(13)).foregroundStyle(C.text).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(verbatim: "\(rate(r))/h").font(.mono(12)).foregroundStyle(C.muted)
                        Text(verbatim: Fmt.isk(r * (prices[id]?.sell ?? 0))).font(.mono(12)).foregroundStyle(C.text)
                    }
                }
            }
        }
        if !extract.isEmpty { ColonyFinder(resources: extract.sorted { $0.value > $1.value }.map(\.key), names: names) }
        Text("Customs tax: the unit's base value from the SDE (P0 5, P1 400, P2 7 200, P3 60 000, P4 1 200 000 ISK) × the rate; import is half of export (EVE University). Moving goods between your planets isn't counted.")
            .font(.ui(11)).foregroundStyle(C.faint)
    }

    private func walk(_ n: PINode, buy: inout [Int: Double], extract: inout [Int: Double], factories: inout [Int: Double]) -> Bool {
        switch n.source {
        case .buy: buy[n.type, default: 0] += n.rate
        case .extract: extract[n.type, default: 0] += n.rate
        case .build: factories[n.tier, default: 0] += n.factories
        }
        for c in n.children { _ = walk(c, buy: &buy, extract: &extract, factories: &factories) }
        return true
    }

    private func nodeView(_ n: PINode, depth: Int) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                EVETypeIcon(typeId: n.type, size: 18)
                Text(verbatim: names[n.type] ?? "#\(n.type)").font(.ui(12)).foregroundStyle(C.text).lineLimit(1)
                Pill(text: "P\(n.tier)", color: C.muted)
                Text(verbatim: "\(rate(n.rate))/h").font(.mono(11)).foregroundStyle(C.muted)
                switch n.source {
                case .build: Text("· factories \(rate(n.factories))").font(.ui(11)).foregroundStyle(C.text2)
                case .buy: Text("· buy").font(.ui(11)).foregroundStyle(C.warn)
                case .extract: Text(verbatim: "· " + (PlanetTypes.p0Planets[n.type] ?? []).map(planetTypeName).joined(separator: ", ")).font(.ui(11)).foregroundStyle(C.good).lineLimit(1)
                }
            }
            ForEach(n.children) { c in nodeView(c, depth: depth + 1) }
        }
        .padding(.leading, depth > 0 ? 14 : 0))
    }

    private func load() async {
        guard let repo = env.repository else { return }
        let all = (try? await repo.planetSchematics()) ?? [:]
        let ids = Set(all.values.flatMap { [$0.output.typeId] + $0.inputs.map(\.typeId) })
        tiers = (try? await repo.piTiers(typeIds: ids)) ?? [:]
        bases = (try? await repo.piBaseValues(typeIds: ids)) ?? [:]
        names = ((try? await repo.types(ids: ids)) ?? [:]).mapValues(\.name)
        schematics = all
        #if DEBUG
        // Debug builds: `-piProduct 2867` picks a product (screenshots).
        let id = UserDefaults.standard.integer(forKey: "piProduct")
        if id > 0, product == nil, let t = tiers[id] { tier = t; pick(id) }
        #endif
    }

    private func loadPrices() async {
        guard let product else { return }
        var ids: Set<Int> = [product]
        var buy: [Int: Double] = [:], extract: [Int: Double] = [:], factories: [Int: Double] = [:]
        _ = walk(build(product, 1, depth: 0), buy: &buy, extract: &extract, factories: &factories)
        ids.formUnion(buy.keys)
        if let p = try? await HubPrices.hub(station: HubPrices.jitaStation, typeIds: ids) { prices.merge(p) { _, b in b } }
    }
}

// MARK: - Colony finder

/// Where to put the colonies: systems near you with planets for every raw resource of the chain.
private struct ColonyFinder: View {
    let resources: [Int]
    let names: [Int: String]
    @Environment(AppEnvironment.self) private var env
    @State private var origin: (id: Int, name: String)?
    @State private var radius = 5
    @State private var space = 0 // 0 any, 1 highsec, 2 low and below
    @State private var galaxy: GalaxyData?
    @State private var sites: [(id: Int, jumps: Int, planets: [Int: Int], missing: [Int])]?

    var body: some View {
        Card(String(localized: "Where to put the colonies")) {
            SystemPicker(label: "From system", picked: $origin)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("Radius, jumps").font(.ui(11)).foregroundStyle(C.muted)
                    ForEach([0, 1, 2, 3, 5, 7, 10], id: \.self) { r in
                        Button("\(r)") { radius = r }.buttonStyle(CanopusButtonStyle(kind: radius == r ? .primary : .ghost, small: true))
                    }
                }
            }
            HStack(spacing: 6) {
                Text("Security").font(.ui(11)).foregroundStyle(C.muted)
                Button("any") { space = 0 }.buttonStyle(CanopusButtonStyle(kind: space == 0 ? .primary : .ghost, small: true))
                Button("highsec only") { space = 1 }.buttonStyle(CanopusButtonStyle(kind: space == 1 ? .primary : .ghost, small: true))
                Button("lowsec and below") { space = 2 }.buttonStyle(CanopusButtonStyle(kind: space == 2 ? .primary : .ghost, small: true))
            }
            if origin == nil {
                Text("Pick the system to search from: systems nearby with planets for every raw resource of the chain.").font(.ui(12)).foregroundStyle(C.muted)
            } else if let sites, let g = galaxy {
                let shown = sites.filter { s in
                    let sec = C.roundSec(g.index[s.id].map { g.security[$0] } ?? 0)
                    return space == 0 || (space == 1 ? sec >= 0.5 : sec < 0.5)
                }
                if shown.isEmpty { Text("No suitable systems in this radius — widen it.").font(.ui(12)).foregroundStyle(C.muted) }
                ForEach(shown.prefix(60), id: \.id) { s in
                    let i = g.index[s.id]
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            SecText(value: i.map { g.security[$0] } ?? 0)
                            Text(verbatim: i.map { g.names[$0] } ?? "").font(.ui(13, .semibold)).foregroundStyle(C.text)
                            Spacer(minLength: 4)
                            Text("\(s.jumps) j.").font(.mono(12)).foregroundStyle(C.muted)
                        }
                        Text(verbatim: s.planets.filter { PlanetTypes.names[$0.key] != nil }.sorted { $0.key < $1.key }
                            .map { "\(planetTypeName($0.key))\($0.value > 1 ? " ×\($0.value)" : "")" }.joined(separator: ", "))
                            .font(.ui(11)).foregroundStyle(C.muted)
                        if s.missing.isEmpty {
                            Text("✔ every raw resource").font(.ui(11)).foregroundStyle(C.good)
                        } else {
                            Text("missing: \(s.missing.map { names[resources[$0]] ?? "" }.joined(separator: ", "))").font(.ui(11)).foregroundStyle(C.warn)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else {
                ProgressView().tint(C.accent).frame(maxWidth: .infinity)
            }
            Text("Planet types are from the SDE. Planetary industry is not possible in some systems (trade hubs such as Jita) — check in the game.")
                .font(.ui(11)).foregroundStyle(C.faint)
        }
        .task(id: env.repositoryVersion) { if galaxy == nil { galaxy = try? await env.repository?.galaxy() } }
        .task(id: env.dataKey) {
            guard origin == nil, let svc = env.characterStore.selectedService, let loc = try? await svc.location(),
                  let s = try? await env.repository?.systems(ids: [loc.solarSystemId])[loc.solarSystemId] else { return }
            origin = (loc.solarSystemId, s.name)
        }
        .task(id: "\(origin?.id ?? 0)/\(radius)/\(resources)/\(galaxy?.count ?? 0)") { await search() }
    }

    /// Systems within the radius (gate jumps), those covering every need first, then nearest, then safest.
    private func search() async {
        guard let g = galaxy, let origin, let start = g.index[origin.id] else { sites = nil; return }
        var dist: [Int: Int] = [start: 0]
        var frontier = [start]
        for d in 0..<radius {
            var next: [Int] = []
            for i in frontier { for n in g.neighbors[i] where dist[n] == nil { dist[n] = d + 1; next.append(n) } }
            frontier = next
        }
        let ids = Set(dist.keys.map { g.ids[$0] })
        let planets = (try? await env.repository?.systemPlanets(ids: ids)) ?? [:]
        let needs = resources.map { PlanetTypes.p0Planets[$0] ?? [] }
        sites = dist.map { i, jumps in
            let id = g.ids[i]
            let p = planets[id] ?? [:]
            let missing = needs.indices.filter { k in !needs[k].contains { (p[$0] ?? 0) > 0 } }
            return (id, jumps, p, missing)
        }
        .sorted { a, b in
            if a.missing.count != b.missing.count { return a.missing.count < b.missing.count }
            if a.jumps != b.jumps { return a.jumps < b.jumps }
            return (g.index[a.id].map { g.security[$0] } ?? 0) > (g.index[b.id].map { g.security[$0] } ?? 0)
        }
    }
}
