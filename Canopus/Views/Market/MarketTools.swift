// Market tools (the desktop's MarketPage Appraisal and MarketTools.tsx): loot appraisal at Jita prices,
// arbitrage between the five trade hubs, and the LP store calculator (ISK per LP).

import SwiftUI
import Domain
import EVEAuth
import EVEStaticData

private func isk(_ v: Double) -> String { Fmt.isk(v) }
private func n0(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0))) }

/// A number field with a caption (tax, margin…).
private struct NumberField: View {
    let label: LocalizedStringKey
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.ui(11)).foregroundStyle(C.muted)
            TextField("", value: $value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .font(.mono(13))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(width: 90)
                .background(C.card, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(C.border, lineWidth: 1))
        }
    }
}

private struct ChipRow<ID: Hashable>: View {
    let options: [(id: ID, label: String)]
    @Binding var selection: ID

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(options, id: \.id) { o in
                    Button(LocalizedStringKey(o.label)) { selection = o.id }
                        .buttonStyle(CanopusButtonStyle(kind: selection == o.id ? .primary : .ghost, small: true))
                }
            }
        }
    }
}

// MARK: - Loot appraisal

/// Pasted item lists: EVE inventory copy (tab separated), "Name x 10", "10 x Name", "10 Name" (the desktop's parseItemList).
func parseItemList(_ text: String) -> [(name: String, qty: Int)] {
    var order: [String] = []
    var merged: [String: (name: String, qty: Int)] = [:]
    let num = { (s: Substring) -> Int in Int(s.filter(\.isNumber)) ?? 0 }
    for raw in text.split(whereSeparator: \.isNewline) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { continue }
        var name = line, qty = 1
        let tabs = line.split(separator: "\t", omittingEmptySubsequences: false)
        if tabs.count > 1 {
            name = tabs[0].trimmingCharacters(in: .whitespaces)
            let q = tabs[1].trimmingCharacters(in: .whitespaces)
            qty = q.isEmpty ? 1 : max(1, num(Substring(q)))
        } else if let m = line.firstMatch(of: #/^(.+?)\s+[xX]\s*([\d\s,.]+)$/#) {
            name = String(m.1); qty = max(1, num(m.2))
        } else if let m = line.firstMatch(of: #/^([\d\s,.]+?)\s*[xX]?\s+(.+)$/#) {
            name = String(m.2); qty = max(1, num(m.1))
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "*")).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { continue }
        let key = name.lowercased()
        if merged[key] == nil { order.append(key) }
        merged[key] = (name, (merged[key]?.qty ?? 0) + qty)
    }
    return order.compactMap { merged[$0] }
}

struct Appraisal: View {
    @Environment(AppEnvironment.self) private var env
    @State private var text = ""
    @State private var rows: [(type: ItemType, qty: Int, sell: Double, buy: Double, volume: Double)]?
    @State private var unknown: [String] = []
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card("Paste a list of items") {
                TextEditor(text: $text)
                    .font(.mono(12)).scrollContentBackground(.hidden)
                    .frame(minHeight: 120, maxHeight: 200).padding(6)
                    .background(C.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(C.border, lineWidth: 1))
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                Text("Copy from the inventory (Ctrl+A, Ctrl+C) or type one per line: Tritanium 10000 · 5 x Hobgoblin I").font(.ui(11)).foregroundStyle(C.faint)
                HStack(spacing: 8) {
                    Button("Paste") { if let s = UIPasteboard.general.string { text = s; Task { await appraise() } } }.buttonStyle(.canopusGhost)
                    Button(busy ? "Calculating…" : "Appraise at Jita") { Task { await appraise() } }
                        .buttonStyle(.canopus).disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Clear") { text = ""; rows = nil; unknown = [] }.buttonStyle(.canopusSmall)
                }
                if !unknown.isEmpty { Text("Not recognised: \(unknown.joined(separator: ", "))").font(.ui(12)).foregroundStyle(C.warn) }
            }
            if let rows {
                let total = rows.reduce((sell: 0.0, buy: 0.0, volume: 0.0)) { ($0.sell + $1.sell, $0.buy + $1.buy, $0.volume + $1.volume) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    StatTile(label: "Jita sell", value: isk(total.sell), sub: Fmt.isk(total.sell, compact: false))
                    StatTile(label: "Jita buy", value: isk(total.buy), sub: Fmt.isk(total.buy, compact: false))
                    StatTile(label: "Volume", value: "\(n0(total.volume)) m³")
                }
                Card {
                    ForEach(rows, id: \.type.id) { r in
                        HStack(spacing: 8) {
                            NavigationLink { TypeDetailView(typeId: r.type.id, typeName: r.type.name) } label: {
                                HStack(spacing: 6) {
                                    EVETypeIcon(typeId: r.type.id, size: 22)
                                    Text(verbatim: r.type.name).font(.ui(13)).foregroundStyle(C.accentText).lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer(minLength: 4)
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(verbatim: "×\(r.qty.formatted()) · \(isk(r.sell))").font(.mono(12)).foregroundStyle(C.text)
                                Text(verbatim: "buy \(isk(r.buy)) · \(n0(r.volume)) m³").font(.mono(10)).foregroundStyle(C.muted)
                            }
                        }
                    }
                }
            }
        }
    }

    private func appraise() async {
        guard let repo = env.repository else { return }
        busy = true
        defer { busy = false }
        var known: [(ItemType, Int)] = []
        var missing: [String] = []
        for item in parseItemList(text) {
            if let t = try? await repo.type(named: item.name) { known.append((t, item.qty)) } else { missing.append(item.name) }
        }
        unknown = missing
        let prices = (try? await HubPrices.hub(station: TradeHub.jita.stationId, typeIds: Set(known.map(\.0.id)))) ?? [:]
        rows = known.map { t, q in
            let p = prices[t.id]
            return (t, q, (p?.sell ?? 0) * Double(q), (p?.buy ?? 0) * Double(q), (t.volume ?? 0) * Double(q))
        }
        .sorted { $0.sell > $1.sell }
    }
}

// MARK: - Arbitrage

/// Cascading market group menus: category → group → subgroup (the desktop's GroupPicker).
private struct GroupPicker: View {
    @Binding var path: [MarketGroup]
    @Environment(AppEnvironment.self) private var env
    @State private var levels: [[MarketGroup]] = []

    var body: some View {
        FlowRow(spacing: 6) {
            ForEach(Array(levels.enumerated()), id: \.offset) { i, options in
                Menu {
                    Button(i == 0 ? String(localized: "— market category —") : String(localized: "— all —")) { path = Array(path.prefix(i)) }
                    ForEach(options) { g in Button(g.name) { path = Array(path.prefix(i)) + [g] } }
                } label: {
                    Text(verbatim: i < path.count ? path[i].name : (i == 0 ? String(localized: "— market category —") : String(localized: "— all —")))
                        .font(.ui(13)).lineLimit(1)
                }
                .buttonStyle(.canopusGhost)
            }
        }
        .task(id: path.map(\.id)) {
            guard let repo = env.repository else { return }
            var out = [(try? await repo.marketGroups(parentId: nil)) ?? []]
            for g in path {
                let next = (try? await repo.marketGroups(parentId: g.id)) ?? []
                if next.isEmpty { break }
                out.append(next)
            }
            levels = out
        }
    }
}

struct Arbitrage: View {
    @Environment(AppEnvironment.self) private var env
    @State private var path: [MarketGroup] = []
    @State private var instant = true
    @State private var from = 0
    @State private var to = 0
    @State private var tax = 3.37
    @State private var broker = 1.5
    @State private var minMargin = 5.0
    @State private var scan: (ids: [Int], names: [Int: ItemType], prices: [Int: [Int: HubPrice]], hubs: [TradeHub])?
    @State private var loading = false

    private struct Deal: Identifiable {
        var id: Int { typeId }
        let typeId: Int, from: String, to: String, buy: Double, sell: Double, profit: Double, margin: Double, units: Double, total: Double, perM3: Double?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card("Arbitrage between trade hubs") {
                Text("Buy at the best sell price in one hub and sell in another: straight into buy orders or with your own sell order. Pick a market category: Canopus compares prices in all five hubs (Fuzzwork data, refreshed about every 30 minutes).")
                    .font(.ui(12)).foregroundStyle(C.muted)
                GroupPicker(path: $path)
                HStack(spacing: 6) {
                    hubMenu("From", $from)
                    hubMenu("To", $to)
                }
                ChipRow(options: [(true, "Straight into buy orders"), (false, "Place a sell order")], selection: $instant)
                FlowRow(spacing: 10) {
                    NumberField(label: "Sales tax, %", value: $tax)
                    if !instant { NumberField(label: "Broker fee, %", value: $broker) }
                    NumberField(label: "Min. margin, %", value: $minMargin)
                }
                Button(loading ? "Collecting prices…" : "Find deals") { Task { await run() } }
                    .buttonStyle(.canopus).disabled(path.isEmpty || loading)
            }
            if loading {
                ProgressView().tint(C.accent).frame(maxWidth: .infinity)
            } else if scan != nil {
                let list = deals
                Card(String(localized: "Deals: \(list.count)")) {
                    if list.isEmpty {
                        Text("No deals with that margin: lower the minimum margin or pick another category.").font(.ui(13)).foregroundStyle(C.muted)
                    } else {
                        ForEach(list) { d in dealRow(d) }
                    }
                    Text("The price is the best order in the hub; a big lot climbs the book, so \"total profit\" is an upper bound. Check the order book before buying and mind the hauling (ISK / m³ is the profit per cubic metre).")
                        .font(.ui(11)).foregroundStyle(C.faint)
                }
            } else {
                Text("Pick a market category and tap Find deals.").font(.ui(13)).foregroundStyle(C.muted)
            }
        }
    }

    private func hubMenu(_ label: LocalizedStringKey, _ value: Binding<Int>) -> some View {
        Menu {
            Button(String(localized: "Any hub")) { value.wrappedValue = 0 }
            ForEach(TradeHub.all) { h in Button(h.name) { value.wrappedValue = h.stationId } }
        } label: {
            HStack(spacing: 4) {
                Text(label).foregroundStyle(C.muted)
                Text(verbatim: TradeHub.all.first { $0.stationId == value.wrappedValue }?.name ?? String(localized: "Any hub")).foregroundStyle(C.text)
            }
            .font(.ui(13))
        }
        .buttonStyle(.canopusGhost)
    }

    private func dealRow(_ d: Deal) -> some View {
        let name = scan?.names[d.typeId]?.name ?? "#\(d.typeId)"
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                NavigationLink { TypeMarketView(typeId: d.typeId, name: name) } label: {
                    HStack(spacing: 6) {
                        EVETypeIcon(typeId: d.typeId, size: 22)
                        Text(verbatim: name).font(.ui(13, .medium)).foregroundStyle(C.accentText).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 4)
                Text(verbatim: isk(d.total)).font(.mono(13, medium: true)).foregroundStyle(C.good)
            }
            HStack(spacing: 10) {
                Text(verbatim: "\(d.from) → \(d.to)").foregroundStyle(C.text2)
                Text(verbatim: "\(isk(d.buy)) → \(isk(d.sell))")
                Text(verbatim: "+\(isk(d.profit)) · \(String(format: "%.1f%%", d.margin * 100))").foregroundStyle(C.good)
                Text(verbatim: "×\(n0(d.units))")
                if let m3 = d.perM3 { Text(verbatim: "\(isk(m3))/m³") }
            }
            .font(.mono(11)).foregroundStyle(C.muted)
        }
        .padding(.vertical, 4)
    }

    private func run() async {
        guard let scope = path.last, let repo = env.repository else { return }
        loading = true
        defer { loading = false }
        let ids = (try? await repo.marketTypes(in: scope.id)) ?? []
        let names = (try? await repo.types(ids: Set(ids))) ?? [:]
        let hubs = TradeHub.all.filter { from == 0 || to == 0 || $0.stationId == from || $0.stationId == to }
        var prices: [Int: [Int: HubPrice]] = [:]
        for h in hubs { prices[h.stationId] = (try? await HubPrices.hub(station: h.stationId, typeIds: Set(ids))) ?? [:] }
        scan = (ids, names, prices, hubs)
    }

    /// The best route per item, as the desktop's arbitrage: buy from sell orders, sell into buy orders or with an order.
    private var deals: [Deal] {
        guard let s = scan else { return [] }
        var out: [Deal] = []
        for id in s.ids {
            var best: Deal?
            for a in s.hubs where from == 0 || a.stationId == from {
                guard let pa = s.prices[a.stationId]?[id], pa.sell > 0, pa.sellVolume > 0 else { continue }
                for b in s.hubs where b != a && (to == 0 || b.stationId == to) {
                    guard let pb = s.prices[b.stationId]?[id] else { continue }
                    let sell = instant ? pb.buy : (pb.sell > 0 ? pb.sell - 0.01 : 0)
                    guard sell > 0 else { continue }
                    let revenue = sell * (1 - tax / 100 - (instant ? 0 : broker / 100))
                    let profit = revenue - pa.sell
                    let margin = profit / pa.sell
                    guard margin * 100 >= minMargin else { continue }
                    let units = (instant ? min(pa.sellVolume, pb.buyVolume) : pa.sellVolume).rounded(.down)
                    guard units > 0 else { continue }
                    let vol = s.names[id]?.volume ?? 0
                    let deal = Deal(typeId: id, from: a.name, to: b.name, buy: pa.sell, sell: sell, profit: profit, margin: margin,
                                    units: units, total: profit * units, perM3: vol > 0 ? profit / vol : nil)
                    if best == nil || deal.total > best!.total { best = deal }
                }
            }
            if let best { out.append(best) }
        }
        return Array(out.sorted { $0.total > $1.total }.prefix(300))
    }
}

// MARK: - LP store

/// Corporations with popular LP stores (faction warfare, navies, pirates, Sisters), as the desktop.
private let popularLpCorps = [
    "Caldari Navy", "Federation Navy", "Amarr Navy", "Republic Fleet", "State Protectorate", "Federal Defense Union",
    "24th Imperial Crusade", "Tribal Liberation Force", "Sisters of EVE", "Guristas", "Serpentis Corporation", "Blood Raiders",
    "Sansha's Nation", "Angel Cartel", "Mordu's Legion Command", "Thukker Mix", "Ministry of War", "Center for Advanced Studies",
]

struct LpStore: View {
    @Environment(AppEnvironment.self) private var env
    @State private var mine: [(id: Int, name: String, lp: Int)] = []
    @State private var popular: [(id: Int, name: String)] = []
    @State private var corp: (id: Int, name: String)?
    @State private var sellOrder = true
    @State private var tax = 3.37
    @State private var showBpc = false
    @State private var manual = ""
    @State private var manualError: String?
    @State private var store: (offers: [ESILoyaltyStoreOffer], prices: [Int: HubPrice], types: [Int: ItemType], categories: [Int: Int])?
    @State private var loading = false
    @State private var error: Error?

    private struct Row: Identifiable {
        var id: Int { offer.offerId }
        let offer: ESILoyaltyStoreOffer
        let isBpc: Bool
        let unit: Double
        let required: Double
        let value: Double
        let perLp: Double
        let onSale: Double
        var priced: Bool { unit > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card("LP store: what pays best for loyalty points") {
                Menu {
                    if !mine.isEmpty {
                        Section("Your loyalty points") {
                            ForEach(mine, id: \.id) { m in Button("\(m.name) — \(m.lp.formatted()) LP") { corp = (m.id, m.name) } }
                        }
                    }
                    Section("Popular stores") {
                        ForEach(popular, id: \.id) { c in Button(c.name) { corp = c } }
                    }
                } label: {
                    Text(verbatim: corp?.name ?? String(localized: "— pick a corporation —")).font(.ui(14))
                }
                .buttonStyle(.canopusGhost)
                HStack(spacing: 6) {
                    TextField("Or the exact name, e.g. Caldari Navy", text: $manual)
                        .font(.ui(13)).autocorrectionDisabled().textInputAutocapitalization(.never)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(C.card, in: RoundedRectangle(cornerRadius: 6))
                        .onSubmit { Task { await pickManual() } }
                    Button("Open") { Task { await pickManual() } }.buttonStyle(.canopusSmall).disabled(manual.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let manualError { Text(manualError).font(.ui(12)).foregroundStyle(C.warn) }
                ChipRow(options: [(true, "With a sell order (Jita sell price)"), (false, "Straight into buy orders")], selection: $sellOrder)
                HStack(spacing: 12) {
                    NumberField(label: "Sales tax, %", value: $tax)
                    Button(showBpc ? "✓ Show blueprints" : "Show blueprints") { showBpc.toggle() }.buttonStyle(.canopusSmall)
                }
            }
            if corp == nil {
                Text("Pick a corporation: from your loyalty points or the popular stores.").font(.ui(13)).foregroundStyle(C.muted)
            } else if loading {
                HStack(spacing: 8) { ProgressView().tint(C.accent); Text("Loading the store and Jita prices…").font(.ui(13)).foregroundStyle(C.muted) }
            } else if let error {
                Text(error.localizedDescription).font(.ui(13)).foregroundStyle(C.bad)
            } else if store != nil {
                results
            }
        }
        .task { await loadCorps() }
        .task(id: corp?.id) { await loadStore() }
    }

    @ViewBuilder private var results: some View {
        let rows = self.rows
        let best = rows.first { $0.priced && $0.value > 0 }
        let myLp = mine.first { $0.id == corp?.id }?.lp ?? 0
        let name = { (id: Int) in store?.types[id]?.name ?? "#\(id)" }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            StatTile(label: "Offers", value: "\(rows.count)")
            StatTile(label: "Best rate", value: best.map { "\(n0($0.perLp)) ISK/LP" } ?? "—", sub: best.map { name($0.offer.typeId) })
            if myLp > 0, let best {
                StatTile(label: "Your LP", value: myLp.formatted(), sub: String(localized: "≈ \(isk(Double(myLp) * best.perLp)) at the best rate"))
            }
        }
        Card {
            ForEach(rows) { r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        NavigationLink { TypeMarketView(typeId: r.offer.typeId, name: name(r.offer.typeId)) } label: {
                            HStack(spacing: 6) {
                                EVETypeIcon(typeId: r.offer.typeId, size: 22)
                                Text(verbatim: (r.offer.quantity > 1 ? "\(r.offer.quantity.formatted())× " : "") + name(r.offer.typeId))
                                    .font(.ui(13)).foregroundStyle(r.isBpc ? C.muted : C.accentText).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer(minLength: 4)
                        Text(verbatim: r.priced ? "\(n0(r.perLp)) ISK/LP" : "—").font(.mono(13, medium: true)).foregroundStyle(C.text)
                    }
                    HStack(spacing: 10) {
                        Text(verbatim: "\(r.offer.lpCost.formatted()) LP")
                        if r.offer.iskCost > 0 { Text(verbatim: "+ \(isk(Double(r.offer.iskCost)))") }
                        if r.required > 0 { Text("items \(isk(r.required))") }
                        Spacer(minLength: 4)
                        Text(verbatim: r.priced ? isk(r.value) : String(localized: "no price")).foregroundStyle(r.value > 0 ? C.good : C.bad)
                        Text("on sale \(n0(r.onSale))")
                    }
                    .font(.mono(10)).foregroundStyle(C.muted)
                    ForEach(r.offer.requiredItems, id: \.typeId) { it in
                        Text(verbatim: "  \(it.quantity.formatted())× \(name(it.typeId))").font(.ui(11)).foregroundStyle(C.text2)
                    }
                }
                .padding(.vertical, 3)
            }
            Text("Result = revenue after tax − the store's ISK − the items to hand in at Jita sell price. Watch \"on sale\": a rare item sells slowly. Blueprint copies have no market price and are hidden by default.")
                .font(.ui(11)).foregroundStyle(C.faint)
        }
    }

    private var rows: [Row] {
        guard let s = store else { return [] }
        return s.offers.compactMap { o -> Row? in
            let isBpc = s.categories[o.typeId] == 9
            guard o.lpCost > 0, showBpc || !isBpc else { return nil }
            let p = s.prices[o.typeId]
            let unit = sellOrder ? (p?.sell ?? 0) : (p?.buy ?? 0)
            let required = o.requiredItems.reduce(0.0) { $0 + (s.prices[$1.typeId]?.sell ?? 0) * Double($1.quantity) }
            let value = unit * Double(o.quantity) * (1 - tax / 100) - Double(o.iskCost) - required
            return Row(offer: o, isBpc: isBpc, unit: unit, required: required, value: value, perLp: value / Double(o.lpCost), onSale: p?.sellVolume ?? 0)
        }
        .sorted { $0.perLp > $1.perLp }
    }

    private func loadCorps() async {
        if popular.isEmpty {
            popular = ((try? await PublicESI.shared.corporationIds(names: popularLpCorps)) ?? []).sorted { $0.name < $1.name }
        }
        if mine.isEmpty, let svc = env.characterStore.selectedService, let lp = try? await svc.loyaltyPoints() {
            let names = (try? await MarketService().names(ids: lp.map(\.corporationId))) ?? [:]
            mine = lp.map { ($0.corporationId, names[$0.corporationId] ?? "#\($0.corporationId)", $0.loyaltyPoints) }.sorted { $0.lp > $1.lp }
            #if DEBUG
            if corp == nil, UserDefaults.standard.bool(forKey: "lpFirst"), let m = mine.first { corp = (m.id, m.name) }
            #endif
        }
    }

    private func pickManual() async {
        manualError = nil
        if let hit = try? await PublicESI.shared.corporationIds(names: [manual.trimmingCharacters(in: .whitespaces)]).first {
            corp = hit
        } else {
            manualError = String(localized: "No corporation with that exact name")
        }
    }

    private func loadStore() async {
        guard let corp, let repo = env.repository else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let offers = try await PublicESI.shared.loyaltyOffers(corporationId: corp.id)
            let ids = Set(offers.flatMap { [$0.typeId] + $0.requiredItems.map(\.typeId) })
            let prices = (try? await HubPrices.hub(station: TradeHub.jita.stationId, typeIds: ids)) ?? [:]
            let types = (try? await repo.types(ids: ids)) ?? [:]
            let groups = (try? await repo.groups(ids: Set(types.values.map(\.groupId)))) ?? [:]
            store = (offers, prices, types, types.mapValues { groups[$0.groupId]?.categoryId ?? 0 })
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }
}

/// Lays its children out in rows, wrapping like text.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(width, maxX), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
