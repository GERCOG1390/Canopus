// The wallet as the desktop's character/Wallet.tsx: balance, income / expense / net for 30 days, the main
// items of the month, then the journal and the market transactions.

import SwiftUI
import Domain
import EVEAuth
import EVEStaticData

struct WalletTab: View {
    let characterService: CharacterService
    @Environment(AppEnvironment.self) private var env
    @State private var balance: Double?
    @State private var journal: [ESIWalletEntry] = []
    @State private var txs: [ESIWalletTransaction] = []
    @State private var names: [Int: String] = [:]
    @State private var places: [Int: String] = [:]
    @State private var typeNames: [Int: String] = [:]
    @State private var showTx = false
    @State private var loaded = false
    @State private var error: Error?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error { Text(error.localizedDescription).font(.ui(13)).foregroundStyle(C.bad) }
                if loaded { content } else { ProgressView().tint(C.accent).frame(maxWidth: .infinity).padding(.top, 30) }
            }
            .padding(16)
        }
        .refreshable { await load() }
        .task(id: env.dataKey) { await load() }
    }

    @ViewBuilder private var content: some View {
        let month = Date().addingTimeInterval(-30 * 86_400)
        let recent = journal.filter { $0.date > month }
        let income = recent.reduce(0) { $0 + max(0, $1.amount ?? 0) }
        let expense = recent.reduce(0) { $0 + min(0, $1.amount ?? 0) }
        let byType = Dictionary(grouping: recent, by: \.refType).mapValues { $0.reduce(0) { $0 + ($1.amount ?? 0) } }
        let top = byType.sorted { abs($0.value) > abs($1.value) }.prefix(8)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            StatTile(label: "Balance", value: balance.map { Fmt.isk($0) } ?? "—", sub: balance.map { Fmt.isk($0, compact: false) })
            StatTile(label: "Income, 30 days", value: Fmt.isk(income), valueColor: C.good)
            StatTile(label: "Expenses, 30 days", value: Fmt.isk(expense), valueColor: C.bad)
            StatTile(label: "Net, 30 days", value: Fmt.isk(income + expense))
        }
        if !top.isEmpty {
            Card(String(localized: "Main items, 30 days")) {
                ForEach(Array(top), id: \.key) { type, sum in
                    HStack {
                        Text(verbatim: eveRefLabel(type)).font(.ui(13)).foregroundStyle(C.text)
                        Spacer()
                        Text(verbatim: Fmt.isk(sum)).font(.mono(12, medium: true)).foregroundStyle(sum >= 0 ? C.good : C.bad)
                    }
                }
            }
        }
        CanopusTabs(tabs: [(id: false, label: String(localized: "Journal (\(journal.count))")),
                           (id: true, label: String(localized: "Market transactions (\(txs.count))"))], selection: $showTx)
        Card {
            if showTx { transactions } else { journalList }
        }
    }

    @ViewBuilder private var journalList: some View {
        if journal.isEmpty { Text("No entries").font(.ui(13)).foregroundStyle(C.muted) }
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(journal.prefix(500)) { j in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: eveRefLabel(j.refType)).font(.ui(13, .medium)).foregroundStyle(C.text)
                        Spacer(minLength: 6)
                        Text(verbatim: Fmt.isk(j.amount ?? 0)).font(.mono(12, medium: true)).foregroundStyle((j.amount ?? 0) >= 0 ? C.good : C.bad)
                    }
                    if let d = j.description, !d.isEmpty {
                        Text(verbatim: d).font(.ui(11)).foregroundStyle(C.muted).lineLimit(2)
                    }
                    HStack {
                        Text(verbatim: j.date.formatted(date: .abbreviated, time: .shortened))
                        Spacer()
                        Text(verbatim: j.balance.map { Fmt.isk($0) } ?? "")
                    }
                    .font(.mono(10)).foregroundStyle(C.faint)
                }
                .padding(.vertical, 7)
                Rectangle().fill(C.border).frame(height: 1)
            }
        }
    }

    @ViewBuilder private var transactions: some View {
        if txs.isEmpty { Text("No transactions").font(.ui(13)).foregroundStyle(C.muted) }
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(txs) { t in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        EVETypeIcon(typeId: t.typeId, size: 22)
                        Text(verbatim: typeNames[t.typeId] ?? "#\(t.typeId)").font(.ui(13, .medium)).foregroundStyle(C.text).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(verbatim: (t.isBuy ? "−" : "+") + Fmt.isk(t.unitPrice * Double(t.quantity)))
                            .font(.mono(12, medium: true)).foregroundStyle(t.isBuy ? C.bad : C.good)
                    }
                    HStack {
                        Text(verbatim: "×\(t.quantity.formatted()) · \(Fmt.isk(t.unitPrice, compact: false))")
                        Spacer()
                        Text(verbatim: names[t.clientId] ?? "")
                    }
                    .font(.mono(10)).foregroundStyle(C.muted)
                    HStack {
                        Text(verbatim: t.date.formatted(date: .abbreviated, time: .shortened))
                        Spacer()
                        Text(verbatim: places[t.locationId] ?? String(localized: "Player structure")).lineLimit(1)
                    }
                    .font(.mono(10)).foregroundStyle(C.faint)
                }
                .padding(.vertical, 7)
                Rectangle().fill(C.border).frame(height: 1)
            }
        }
    }

    private func load() async {
        let s = characterService
        do {
            async let b = s.wallet()
            async let j = try? s.walletJournal()
            async let t = try? s.walletTransactions()
            balance = try await b
            journal = (await j ?? []).sorted { $0.date > $1.date }
            txs = (await t ?? []).sorted { $0.date > $1.date }
            loaded = true
            if let resolved = try? await s.resolveNames(ids: Array(Set(txs.map(\.clientId)))) {
                names = Dictionary(resolved.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
            }
            let stations = Set(txs.map(\.locationId)).filter { $0 < 100_000_000 }
            places = (try? await MarketService().names(ids: Array(stations))) ?? [:]
            typeNames = ((try? await env.repository?.types(ids: Set(txs.map(\.typeId)))) ?? [:]).mapValues(\.name)
        } catch {
            if !error.isCancellation { self.error = error }
            loaded = true
        }
    }
}
