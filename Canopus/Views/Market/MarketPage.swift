// The market page (the desktop's MarketPage.tsx): prices across the five trade hubs with the market tree
// and search, loot appraisal, hub arbitrage, the LP store, the pilot's orders and trades.

import SwiftUI
import Domain
import EVEAuth
import EVEStaticData

enum MarketTab: String, CaseIterable {
    case prices, appraisal, arbitrage, lp, orders, trades

    var label: String {
        switch self {
        case .prices: "Prices"
        case .appraisal: "Loot appraisal"
        case .arbitrage: "Arbitrage"
        case .lp: "LP store"
        case .orders: "My orders"
        case .trades: "My trades"
        }
    }
}

struct MarketPage: View {
    @State var tab: MarketTab

    init(tab: MarketTab = {
        #if DEBUG
        if let t = UserDefaults.standard.string(forKey: "marketTab").flatMap(MarketTab.init(rawValue:)) { return t }
        #endif
        return .prices
    }()) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CanopusTabs(tabs: MarketTab.allCases.map { (id: $0, label: $0.label) }, selection: $tab)
                .padding(.horizontal, 12).padding(.vertical, 8)
            switch tab {
            case .prices: MarketPrices()
            case .appraisal: ScrollView { Appraisal().padding(16) }
            case .arbitrage: ScrollView { Arbitrage().padding(16) }
            case .lp: ScrollView { LpStore().padding(16) }
            case .orders: ScrollView { MyOrders().padding(16) }
            case .trades: ScrollView { MyTrades().padding(16) }
            }
        }
        .background(C.bg)
        .navigationTitle("Market")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Prices: the market tree and search

private struct MarketPrices: View {
    @Environment(AppEnvironment.self) private var env
    @State private var query = ""
    @State private var hits: [ItemType] = []
    @State private var groups: [MarketGroup] = []
    @State private var debugType: Int?

    var body: some View {
        List {
            Section {
                HStack(spacing: 6) {
                    Glyph(name: .search, size: 14).foregroundStyle(C.muted)
                    TextField("Item name…", text: $query).font(.ui(14)).autocorrectionDisabled().textInputAutocapitalization(.never)
                }
            }
            if !query.isEmpty {
                Section {
                    ForEach(hits.filter { $0.marketGroupId != nil }) { t in
                        NavigationLink { TypeMarketView(typeId: t.id, name: t.name) } label: { typeRow(t) }
                    }
                }
            } else {
                Section {
                    ForEach(groups) { g in
                        NavigationLink { MarketLevel(group: g) } label: { groupRow(g) }
                    }
                } footer: {
                    Text("Pick an item in the market tree or find it by name to compare prices across the trade hubs.").font(.ui(12)).foregroundStyle(C.faint)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationDestination(item: $debugType) { TypeMarketView(typeId: $0, name: "") }
        #if DEBUG
        // Debug builds: `-marketType 2048` opens an item's market (screenshots).
        .task {
            let id = UserDefaults.standard.integer(forKey: "marketType")
            if id > 0, debugType == nil { try? await Task.sleep(for: .milliseconds(400)); debugType = id }
        }
        #endif
        .task(id: query) {
            guard let repo = env.repository else { return }
            if query.isEmpty {
                if groups.isEmpty { groups = (try? await repo.marketGroups(parentId: nil)) ?? [] }
            } else {
                try? await Task.sleep(for: .milliseconds(200))
                hits = (try? await repo.search(query)) ?? []
            }
        }
    }
}

private func groupRow(_ g: MarketGroup) -> some View {
    HStack(spacing: 10) {
        if let icon = g.iconId { EVEIconImage(iconId: icon, size: 28) } else { Color.clear.frame(width: 28, height: 28) }
        Text(verbatim: g.name).font(.ui(14)).foregroundStyle(C.text)
    }
}

private func typeRow(_ t: ItemType) -> some View {
    HStack(spacing: 10) {
        EVETypeIcon(typeId: t.id, size: 28)
        Text(verbatim: t.name).font(.ui(14)).foregroundStyle(C.text)
        Spacer(minLength: 0)
        TypeMetaBadge(metaGroupId: t.metaGroupId)
    }
}

/// One level of the market tree: subgroups, then the items of the group.
private struct MarketLevel: View {
    let group: MarketGroup
    @Environment(AppEnvironment.self) private var env
    @State private var children: [MarketGroup] = []
    @State private var types: [ItemType] = []

    var body: some View {
        List {
            ForEach(children) { g in
                NavigationLink { MarketLevel(group: g) } label: { groupRow(g) }
            }
            ForEach(types) { t in
                NavigationLink { TypeMarketView(typeId: t.id, name: t.name) } label: { typeRow(t) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(C.bg)
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let repo = env.repository else { return }
            children = (try? await repo.marketGroups(parentId: group.id)) ?? []
            if group.hasTypes { types = (try? await repo.types(marketGroupId: group.id)) ?? [] }
        }
    }
}

// MARK: - One item's market (the desktop's TypeMarket)

struct TypeMarketView: View {
    let typeId: Int
    let name: String
    @Environment(AppEnvironment.self) private var env
    @State private var looked: String?
    @State private var hubs: [(hub: TradeHub, price: HubPrice?)]?
    @State private var sells: [ESIRegionalOrder] = []
    @State private var buys: [ESIRegionalOrder] = []
    @State private var history: [ESIMarketHistory] = []
    @State private var error: Error?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    EVETypeIcon(typeId: typeId, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        NavigationLink { TypeDetailView(typeId: typeId, typeName: title) } label: {
                            Text(verbatim: title).font(.display(20)).foregroundStyle(C.accentText).multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                        Text("type_id \(String(typeId)) · tap the name for full info").font(.ui(12)).foregroundStyle(C.muted)
                    }
                    Spacer(minLength: 0)
                }
                .canopusSurface(padding: 12)
                if let error { Text(error.localizedDescription).font(.ui(13)).foregroundStyle(C.bad) }
                if let hubs {
                    tiles(hubs)
                    hubTable(hubs)
                    historyCard
                    HStack(alignment: .top, spacing: 10) {
                        orderBook(String(localized: "Jita 4-4: selling"), sells)
                        orderBook(String(localized: "Jita 4-4: buying"), buys)
                    }
                } else {
                    ProgressView().tint(C.accent).frame(maxWidth: .infinity).padding(.top, 30)
                }
            }
            .padding(16)
        }
        .background(C.bg)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if name.isEmpty { looked = try? await env.repository?.types(ids: [typeId])[typeId]?.name }
            await load()
        }
    }

    private var title: String { name.isEmpty ? (looked ?? "") : name }

    private func load() async {
        var out: [(TradeHub, HubPrice?)] = []
        for hub in TradeHub.all {
            out.append((hub, try? await HubPrices.hub(station: hub.stationId, typeIds: [typeId])[typeId]))
        }
        let market = MarketService()
        let jita = TradeHub.jita
        async let ordersReq = market.orders(regionId: jita.regionId, typeId: typeId)
        async let historyReq = market.history(regionId: jita.regionId, typeId: typeId)
        let orders = ((try? await ordersReq) ?? []).filter { $0.locationId == jita.stationId }
        sells = Array(orders.filter { !$0.isBuyOrder }.sorted { $0.price < $1.price }.prefix(10))
        buys = Array(orders.filter(\.isBuyOrder).sorted { $0.price > $1.price }.prefix(10))
        history = Array(((try? await historyReq) ?? []).suffix(90))
        hubs = out.map { (hub: $0.0, price: $0.1) }
    }

    private func tiles(_ hubs: [(hub: TradeHub, price: HubPrice?)]) -> some View {
        let last30 = history.suffix(30)
        let avgPrice = last30.isEmpty ? 0 : last30.reduce(0) { $0 + $1.average } / Double(last30.count)
        let avgVolume = last30.isEmpty ? 0 : Double(last30.reduce(0) { $0 + $1.volume }) / Double(last30.count)
        let jita = hubs.first?.price
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            StatTile(label: "Jita: sell", value: jita.map { $0.sell > 0 ? Fmt.isk($0.sell) : "—" } ?? "—")
            StatTile(label: "Jita: buy", value: jita.map { $0.buy > 0 ? Fmt.isk($0.buy) : "—" } ?? "—")
            StatTile(label: "Avg price (30 d)", value: avgPrice > 0 ? Fmt.isk(avgPrice) : "—")
            StatTile(label: "Avg volume a day", value: avgVolume.formatted(.number.precision(.fractionLength(0))), sub: String(localized: "The Forge, 30 days"))
        }
    }

    private func hubTable(_ hubs: [(hub: TradeHub, price: HubPrice?)]) -> some View {
        let minSell = hubs.compactMap { $0.price?.sell }.filter { $0 > 0 }.min()
        let maxBuy = hubs.compactMap { $0.price?.buy }.filter { $0 > 0 }.max()
        return Card("Trade hubs") {
            HStack {
                Text("Hub").frame(maxWidth: .infinity, alignment: .leading)
                Text("Sell").frame(width: 92, alignment: .trailing)
                Text("Buy").frame(width: 92, alignment: .trailing)
                Text("Spread").frame(width: 56, alignment: .trailing)
            }
            .font(.ui(11, .medium)).foregroundStyle(C.muted)
            ForEach(hubs, id: \.hub) { h in
                let sell = h.price?.sell ?? 0, buy = h.price?.buy ?? 0
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: h.hub.name).font(.ui(13)).foregroundStyle(C.text)
                        if let v = h.price?.sellVolume, v > 0 { Text("on sale: \(v.formatted(.number.precision(.fractionLength(0))))").font(.ui(10)).foregroundStyle(C.faint) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: sell > 0 ? Fmt.isk(sell) : "—").foregroundStyle(sell > 0 && sell == minSell ? C.good : C.text2).frame(width: 92, alignment: .trailing)
                    Text(verbatim: buy > 0 ? Fmt.isk(buy) : "—").foregroundStyle(buy > 0 && buy == maxBuy ? C.good : C.text2).frame(width: 92, alignment: .trailing)
                    Text(verbatim: sell > 0 && buy > 0 ? String(format: "%.1f%%", (sell - buy) / sell * 100) : "—").foregroundStyle(C.muted).frame(width: 56, alignment: .trailing)
                }
                .font(.mono(12))
            }
            Text("Green: the best price to buy from sellers and the best price to sell into buy orders.").font(.ui(11)).foregroundStyle(C.faint)
        }
    }

    private var historyCard: some View {
        Card("Price history, The Forge (90 days)") {
            if history.count > 1 {
                Sparkline(values: history.map(\.average)).stroke(C.accent, lineWidth: 1.5).frame(height: 90)
                let lo = history.map(\.lowest).min() ?? 0, hi = history.map(\.highest).max() ?? 0
                Text(verbatim: "\(history.first!.date) — \(history.last!.date) · min \(Fmt.isk(lo)) · max \(Fmt.isk(hi))")
                    .font(.ui(11)).foregroundStyle(C.muted)
            } else {
                Text("No trade history").font(.ui(13)).foregroundStyle(C.muted)
            }
        }
    }

    private func orderBook(_ title: String, _ orders: [ESIRegionalOrder]) -> some View {
        Card(title) {
            if orders.isEmpty {
                Text("No orders").font(.ui(13)).foregroundStyle(C.muted)
            } else {
                ForEach(orders) { o in
                    HStack {
                        Text(verbatim: Fmt.isk(o.price)).foregroundStyle(C.text)
                        Spacer(minLength: 4)
                        Text(verbatim: o.volumeRemain.formatted()).foregroundStyle(C.text2)
                        if o.minVolume > 1 { Text(verbatim: "≥\(o.minVolume.formatted())").foregroundStyle(C.muted) }
                    }
                    .font(.mono(11))
                }
            }
        }
    }
}

/// A line through the values, scaled to the frame.
struct Sparkline: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return p }
        let span = max(hi - lo, 1e-9)
        for (i, v) in values.enumerated() {
            let pt = CGPoint(x: rect.minX + rect.width * CGFloat(i) / CGFloat(values.count - 1),
                             y: rect.maxY - rect.height * CGFloat((v - lo) / span))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}
