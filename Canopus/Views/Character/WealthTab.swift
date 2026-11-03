// What the character is worth: ISK in the wallet, assets and the implants in the head and in jump clones
// at Jita sell (blueprint copies count as nothing), sell orders at their own price and the ISK held in
// buy orders. Each part loads on its own, so a missing permission leaves only that line empty.

import SwiftUI
import Domain
import EVEAuth
import EVEStaticData

struct WealthTab: View {
    let characterService: CharacterService
    @Environment(AppEnvironment.self) private var env
    @State private var parts: [Part] = []
    @State private var topItems: [(id: Int, value: Double)] = []
    @State private var names: [Int: String] = [:]
    @State private var loading = true

    struct Part: Identifiable {
        let id: String
        let label: String
        let value: Double?
        let color: Color
        var sub: String? = nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let total = parts.compactMap(\.value).reduce(0, +)
                Card(title: String(localized: "Net worth"), actions: {
                    Button(loading ? "Refreshing…" : "Refresh") { Task { await load() } }.buttonStyle(.canopusSmall).disabled(loading)
                }) {
                    Text(verbatim: Fmt.isk(total)).font(.display(30)).monospacedDigit().foregroundStyle(C.text)
                    if total > 0 { bar(total) }
                    ForEach(parts) { p in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(p.color).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(LocalizedStringKey(p.label)).font(.ui(13)).foregroundStyle(C.text)
                                if let sub = p.sub { Text(verbatim: sub).font(.ui(11)).foregroundStyle(C.muted) }
                            }
                            Spacer(minLength: 4)
                            if let v = p.value {
                                if total > 0 { Text(verbatim: "\(Int((v / total * 100).rounded()))%").font(.mono(11)).foregroundStyle(C.muted) }
                                Text(verbatim: Fmt.isk(v)).font(.mono(13, medium: true)).foregroundStyle(C.text).frame(minWidth: 96, alignment: .trailing)
                            } else if loading {
                                ProgressView().controlSize(.small).tint(C.accent)
                            } else {
                                Text("no access").font(.ui(11)).foregroundStyle(C.faint)
                            }
                        }
                    }
                    Text("Assets and implants at Jita sell (blueprint copies count as nothing); sell orders at their own price; buy orders by the ISK held in escrow.")
                        .font(.ui(11)).foregroundStyle(C.faint)
                }
                if !topItems.isEmpty {
                    Card(String(localized: "Most valuable items")) {
                        ForEach(topItems, id: \.id) { it in
                            HStack(spacing: 6) {
                                EVETypeIcon(typeId: it.id, size: 22)
                                Text(verbatim: names[it.id] ?? "#\(it.id)").font(.ui(13)).foregroundStyle(C.text).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(verbatim: Fmt.isk(it.value)).font(.mono(12)).foregroundStyle(C.text)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .task(id: env.dataKey) { await load() }
    }

    /// The parts side by side in one bar, as shares of the total.
    private func bar(_ total: Double) -> some View {
        GeometryReader { g in
            HStack(spacing: 2) {
                ForEach(parts.filter { ($0.value ?? 0) > 0 }) { p in
                    Rectangle().fill(p.color).frame(width: max(2, (g.size.width - 10) * (p.value ?? 0) / total))
                }
            }
        }
        .frame(height: 10)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let svc = characterService
        async let walletTask = try? svc.wallet()
        async let assetsTask = try? svc.assets()
        async let ordersTask = try? svc.marketOrders()
        async let implantsTask = try? svc.implants()
        async let clonesTask = try? svc.clones()
        let (wallet, assets, orders, implants, clones) = await (walletTask, assetsTask, ordersTask, implantsTask, clonesTask)

        let cloneImplants = (clones?.jumpClones ?? []).flatMap(\.implants)
        var ids = Set(assets?.map(\.typeId) ?? [])
        ids.formUnion(implants ?? [])
        ids.formUnion(cloneImplants)
        let prices = (try? await HubPrices.jitaSell(typeIds: ids)) ?? [:]

        var byType: [Int: Double] = [:]
        var assetValue: Double?
        if let assets {
            var sum = 0.0
            for a in assets where a.isBlueprintCopy != true {
                let v = (prices[a.typeId] ?? 0) * Double(a.quantity)
                sum += v
                byType[a.typeId, default: 0] += v
            }
            assetValue = sum
        }
        let headValue = implants.map { $0.reduce(0) { $0 + (prices[$1] ?? 0) } }
        let cloneValue = clones.map { _ in cloneImplants.reduce(0) { $0 + (prices[$1] ?? 0) } }
        let sell = orders.map { $0.filter { $0.isBuyOrder != true }.reduce(0) { $0 + $1.price * Double($1.volumeRemain) } }
        let escrow = orders.map { $0.filter { $0.isBuyOrder == true }.reduce(0) { $0 + ($1.escrow ?? 0) } }
        let sellCount = orders?.filter { $0.isBuyOrder != true }.count ?? 0
        let buyCount = orders?.filter { $0.isBuyOrder == true }.count ?? 0

        parts = [
            Part(id: "wallet", label: "Wallet", value: wallet, color: C.accent),
            Part(id: "assets", label: "Assets", value: assetValue, color: Color(hex: 0x5B8DEF), sub: assets.map { String(localized: "\($0.count) stacks") }),
            Part(id: "sell", label: "Sell orders", value: sell, color: Color(hex: 0xF0B44F), sub: orders == nil ? nil : String(localized: "\(sellCount) orders")),
            Part(id: "escrow", label: "Buy order escrow", value: escrow, color: Color(hex: 0xB07CE8), sub: orders == nil ? nil : String(localized: "\(buyCount) orders")),
            Part(id: "head", label: "Implants in the head", value: headValue, color: Color(hex: 0xE87C9A)),
            Part(id: "clones", label: "Implants in jump clones", value: cloneValue, color: Color(hex: 0x9AA4B2),
                 sub: clones.map { String(localized: "\($0.jumpClones?.count ?? 0) clones") }),
        ]
        topItems = byType.sorted { $0.value > $1.value }.prefix(15).map { ($0.key, $0.value) }
        names = ((try? await env.repository?.types(ids: Set(topItems.map(\.id)))) ?? [:]).mapValues(\.name)
    }
}
