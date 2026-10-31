// The pilot's market (the desktop's MyOrders and Trades.tsx): open orders checked against the hub's best
// price (outbid in red), and real trading profit — each sell matched to earlier buys of the same item
// (first in, first out), sales tax and broker fees from the wallet journal, stock left valued at Jita.

import SwiftUI
import Domain
import EVEAuth
import EVEStaticData

private func isk(_ v: Double) -> String { Fmt.isk(v) }

private struct NeedsLogin: View {
    let what: LocalizedStringKey
    var body: some View { Text(what).font(.ui(13)).foregroundStyle(C.muted) }
}

// MARK: - My orders

struct MyOrders: View {
    @Environment(AppEnvironment.self) private var env
    @State private var orders: [ESIMarketOrder]?
    @State private var best: [Int: Double] = [:]
    @State private var places: [Int: String] = [:]
    @State private var names: [Int: String] = [:]
    @State private var error: Error?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if env.characterStore.selectedService == nil {
                NeedsLogin(what: "Sign in with a character to see your orders.")
            } else if let error {
                Text(error.localizedDescription).font(.ui(13)).foregroundStyle(C.bad)
            } else if let orders {
                if orders.isEmpty {
                    Text("No open orders.").font(.ui(13)).foregroundStyle(C.muted)
                } else {
                    Card {
                        ForEach(orders) { o in row(o) }
                        Text("Red: your order is outbid (hub data refreshes every few minutes).").font(.ui(11)).foregroundStyle(C.faint)
                    }
                }
            } else {
                ProgressView().tint(C.accent).frame(maxWidth: .infinity)
            }
        }
        .task(id: env.dataKey) { await load() }
    }

    private func row(_ o: ESIMarketOrder) -> some View {
        let buy = o.isBuyOrder == true
        let b = best[o.orderId]
        let outbid = b.map { buy ? $0 > o.price : $0 < o.price } ?? false
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                EVETypeIcon(typeId: o.typeId, size: 22)
                Text(verbatim: names[o.typeId] ?? "#\(o.typeId)").font(.ui(13, .medium)).foregroundStyle(C.text).lineLimit(1)
                Pill(text: buy ? String(localized: "Buy") : String(localized: "Sell"), color: buy ? C.accent : C.warn)
                Spacer(minLength: 4)
                Text(verbatim: isk(o.price)).font(.mono(12, medium: true)).foregroundStyle(C.text)
            }
            HStack(spacing: 10) {
                Text("best \(b.map(isk) ?? "—")").foregroundStyle(outbid ? C.bad : C.muted)
                Text(verbatim: "\(o.volumeRemain.formatted()) / \(o.volumeTotal.formatted())")
                Spacer(minLength: 4)
                Text(verbatim: places[o.locationId] ?? String(localized: "Structure")).lineLimit(1)
            }
            .font(.mono(10)).foregroundStyle(C.muted)
        }
        .padding(.vertical, 3)
    }

    private func load() async {
        guard let svc = env.characterStore.selectedService else { return }
        do {
            let list = try await svc.marketOrders()
            // Compare against the market at each order's station when it is a known hub.
            var bestPrice: [Int: Double] = [:]
            for hub in TradeHub.all {
                let here = list.filter { $0.locationId == hub.stationId }
                guard !here.isEmpty, let p = try? await HubPrices.hub(station: hub.stationId, typeIds: Set(here.map(\.typeId))) else { continue }
                for o in here {
                    if let price = p[o.typeId] { bestPrice[o.orderId] = o.isBuyOrder == true ? price.buy : price.sell }
                }
            }
            best = bestPrice
            let stations = Set(list.map(\.locationId)).filter { $0 < 100_000_000 }
            places = (try? await MarketService().names(ids: Array(stations))) ?? [:]
            names = ((try? await env.repository?.types(ids: Set(list.map(\.typeId)))) ?? [:]).mapValues(\.name)
            orders = list.sorted { (names[$0.typeId] ?? "") < (names[$1.typeId] ?? "") }
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }
}

// MARK: - My trades

struct MyTrades: View {
    @Environment(AppEnvironment.self) private var env
    @State private var txs: [ESIWalletTransaction]?
    @State private var journal: [ESIWalletEntry] = []
    @State private var names: [Int: String] = [:]
    @State private var jita: [Int: Double] = [:]
    @State private var days = 30
    @State private var stockView = false
    @State private var error: Error?

    private struct Item {
        let type: Int
        var bought = 0, sold = 0, matched = 0, left = 0
        var boughtIsk = 0.0, soldIsk = 0.0, profit = 0.0, leftCost = 0.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if env.characterStore.selectedService == nil {
                NeedsLogin(what: "Sign in with a character to see your trades.")
            } else if let error {
                Text(error.localizedDescription).font(.ui(13)).foregroundStyle(C.bad)
            } else if let txs {
                content(txs)
            } else {
                ProgressView().tint(C.accent).frame(maxWidth: .infinity)
            }
        }
        .task(id: env.dataKey) { await load() }
    }

    @ViewBuilder private func content(_ txs: [ESIWalletTransaction]) -> some View {
        let since = Date().addingTimeInterval(-Double(days) * 86400)
        let items = Self.profitByItem(txs, since: since)
        let recent = journal.filter { $0.date >= since }
        let fee = { (type: String) in -recent.filter { $0.refType == type }.reduce(0) { $0 + ($1.amount ?? 0) } }
        let tax = fee("transaction_tax"), broker = fee("brokers_fee")
        let gross = items.reduce(0) { $0 + $1.profit }
        let turnover = items.reduce(0) { $0 + $1.soldIsk }
        let stock = items.filter { $0.left > 0 }
        let stockValue = stock.reduce(0) { $0 + Double($1.left) * (jita[$1.type] ?? 0) }
        HStack(spacing: 6) {
            ForEach([7, 30, 90], id: \.self) { d in
                Button("\(d) days") { days = d }.buttonStyle(CanopusButtonStyle(kind: days == d ? .primary : .ghost, small: true))
            }
            Spacer(minLength: 6)
            Button(stockView ? "Not sold" : "Profit by item") { stockView.toggle() }.buttonStyle(.canopusSmall)
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            StatTile(label: "Net profit", value: isk(gross - tax - broker), sub: String(localized: "from sales \(isk(gross)) minus taxes and fees"),
                     valueColor: gross - tax - broker >= 0 ? C.good : C.bad)
            StatTile(label: "Turnover (sales)", value: isk(turnover), sub: turnover > 0 ? String(localized: "margin \(String(format: "%.1f", gross / turnover * 100))%") : nil)
            StatTile(label: "Sales tax", value: isk(tax))
            StatTile(label: "Broker fees", value: isk(broker))
            StatTile(label: "Not sold", value: isk(stock.reduce(0) { $0 + $1.leftCost }), sub: stockValue > 0 ? String(localized: "at Jita \(isk(stockValue))") : nil)
        }
        Card {
            let rows = stockView ? stock.sorted { $0.leftCost > $1.leftCost } : items.filter { $0.matched > 0 }.sorted { $0.profit > $1.profit }
            if rows.isEmpty {
                Text(stockView ? "Everything bought has been sold." : "No sales with a known buy price in this period.").font(.ui(13)).foregroundStyle(C.muted)
            }
            ForEach(rows, id: \.type) { i in
                HStack(spacing: 6) {
                    EVETypeIcon(typeId: i.type, size: 22)
                    Text(verbatim: names[i.type] ?? "#\(i.type)").font(.ui(13)).foregroundStyle(C.text).lineLimit(1)
                    Spacer(minLength: 4)
                    if stockView {
                        let now = jita[i.type].map { $0 * Double(i.left) }
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(verbatim: "×\(i.left.formatted()) · \(isk(i.leftCost))").font(.mono(12)).foregroundStyle(C.text)
                            Text(verbatim: now.map { "Jita \(isk($0))" } ?? "—").font(.mono(10)).foregroundStyle(now.map { $0 < i.leftCost } == true ? C.bad : C.muted)
                        }
                    } else {
                        let avgSell = i.sold > 0 ? i.soldIsk / Double(i.sold) : 0
                        let perUnit = i.matched > 0 ? i.profit / Double(i.matched) : 0
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(verbatim: isk(i.profit)).font(.mono(12, medium: true)).foregroundStyle(i.profit < 0 ? C.bad : C.good)
                            Text(verbatim: "×\(i.sold.formatted()) · \(isk(perUnit))/u" + (avgSell > 0 ? String(format: " · %.1f%%", perUnit / avgSell * 100) : ""))
                                .font(.mono(10)).foregroundStyle(C.muted)
                        }
                    }
                }
            }
            Text("Sales are matched to earlier buys of the same item (oldest first). ESI gives about three months of transactions: goods bought earlier aren't counted. Taxes and fees come from the wallet journal.")
                .font(.ui(11)).foregroundStyle(C.faint)
        }
    }

    /// Sells matched to earlier buys of the same item, oldest buys first (the desktop's profitByItem).
    private static func profitByItem(_ txs: [ESIWalletTransaction], since: Date) -> [Item] {
        var out: [Item] = []
        for (type, list) in Dictionary(grouping: txs, by: \.typeId) {
            let sorted = list.sorted { $0.date != $1.date ? $0.date < $1.date : $0.transactionId < $1.transactionId }
            var lots: [(qty: Int, price: Double)] = []
            var r = Item(type: type)
            for t in sorted {
                let inPeriod = t.date >= since
                if t.isBuy {
                    lots.append((t.quantity, t.unitPrice))
                    if inPeriod { r.bought += t.quantity; r.boughtIsk += Double(t.quantity) * t.unitPrice }
                    continue
                }
                var qty = t.quantity
                while qty > 0, !lots.isEmpty {
                    let n = min(qty, lots[0].qty)
                    if inPeriod { r.matched += n; r.profit += Double(n) * (t.unitPrice - lots[0].price) }
                    lots[0].qty -= n
                    qty -= n
                    if lots[0].qty == 0 { lots.removeFirst() }
                }
                if inPeriod { r.sold += t.quantity; r.soldIsk += Double(t.quantity) * t.unitPrice }
            }
            r.left = lots.reduce(0) { $0 + $1.qty }
            r.leftCost = lots.reduce(0) { $0 + Double($1.qty) * $1.price }
            if r.bought > 0 || r.sold > 0 { out.append(r) }
        }
        return out
    }

    private func load() async {
        guard let svc = env.characterStore.selectedService else { return }
        do {
            // ESI gives the newest 2500 transactions and pages back with from_id.
            var all: [ESIWalletTransaction] = []
            var from: Int?
            for _ in 0..<6 {
                let batch = try await svc.walletTransactions(fromId: from)
                let fresh = batch.filter { t in !all.contains { $0.transactionId == t.transactionId } }
                guard !fresh.isEmpty else { break }
                all += fresh
                from = (fresh.map(\.transactionId).min() ?? 0) - 1
            }
            journal = (try? await svc.walletJournal()) ?? []
            let personal = all.filter(\.isPersonal)
            let ids = Set(personal.map(\.typeId))
            names = ((try? await env.repository?.types(ids: ids)) ?? [:]).mapValues(\.name)
            jita = (try? await HubPrices.jitaSell(typeIds: ids)) ?? [:]
            txs = personal
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }
}
