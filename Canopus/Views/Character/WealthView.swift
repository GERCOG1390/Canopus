import SwiftUI
import Charts
import EVEAuth

struct WealthView: View {
    let characterService: CharacterService

    @State private var isLoading = true
    @State private var error: Error?

    @State private var walletISK: Double = 0
    @State private var assetsISK: Double = 0
    @State private var ordersISK: Double = 0
    @State private var implantsISK: Double = 0
    @State private var assetCount: Int = 0
    @State private var orderCount: Int = 0
    @State private var implantCount: Int = 0
    @State private var pricesMissing = false

    private var totalISK: Double { walletISK + assetsISK + ordersISK + implantsISK }

    private var segments: [WealthSegment] {
        [
            .init(label: "WALLET",   value: walletISK,   color: Color.eveCyan),
            .init(label: "ASSETS",   value: assetsISK,   color: Color.eveAmber),
            .init(label: "ORDERS",   value: ordersISK,   color: Color.eveGreen),
            .init(label: "IMPLANTS", value: implantsISK, color: Color(red: 0.85, green: 0.60, blue: 1.00)),
        ].filter { $0.value > 0 }
    }

    var body: some View {
        ZStack {
            Color.eveBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    totalHeader
                    Color.eveAmber.opacity(0.14).frame(height: 1)

                    if totalISK > 0 {
                        chartSection
                        Color.eveAmber.opacity(0.14).frame(height: 1)
                    }

                    breakdownSection

                    if pricesMissing {
                        Text("* Asset and implant values use ESI adjusted prices.\n  Items without market data are counted as 0 ISK.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.eveText.opacity(0.32))
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }
                }
                .padding(.bottom, EVELayout.scrollBottomClearance)
            }
            if isLoading { ProgressView().tint(Color.eveCyan) }
        }
        .navigationTitle("WEALTH")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.eveBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
        .alert("Error", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } })
        ) {
            Button("Retry") { Task { await load() } }
            Button("Dismiss", role: .cancel) {}
        } message: { Text(error?.localizedDescription ?? "") }
    }

    // MARK: - Total header

    private var totalHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TOTAL WEALTH").hudLabel()
            Text(iskFormatted(totalISK))
                .font(.system(size: 34, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.eveText)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.top, 10)
            Text("ISK ESTIMATED VALUE")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Color.eveText.opacity(0.32))
                .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    // MARK: - Donut chart

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 0) {
                // Donut
                Chart(segments) { seg in
                    SectorMark(
                        angle: .value("ISK", seg.value),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .foregroundStyle(seg.color)
                    .cornerRadius(3)
                }
                .frame(width: 160, height: 160)
                .chartBackground { _ in Color.clear }

                // Legend
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(segments) { seg in
                        legendRow(seg)
                    }
                }
                .padding(.leading, 20)
                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 20)
    }

    private func legendRow(_ seg: WealthSegment) -> some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 2)
                .fill(seg.color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(seg.label)
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Color.eveText.opacity(0.42))
                Text(iskCompact(seg.value))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(seg.color)
            }
        }
    }

    // MARK: - Breakdown

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BREAKDOWN").hudLabel().padding(.horizontal, 20)

            VStack(spacing: 0) {
                breakdownRow(
                    label: "WALLET BALANCE",
                    icon: "creditcard.fill",
                    value: walletISK,
                    color: Color.eveCyan,
                    detail: nil
                )
                thinDivider
                breakdownRow(
                    label: "ASSETS",
                    icon: "shippingbox.fill",
                    value: assetsISK,
                    color: Color.eveAmber,
                    detail: assetCount > 0 ? "\(assetCount) items" : nil
                )
                thinDivider
                breakdownRow(
                    label: "ACTIVE ORDERS",
                    icon: "chart.line.uptrend.xyaxis",
                    value: ordersISK,
                    color: Color.eveGreen,
                    detail: orderCount > 0 ? "\(orderCount) orders" : nil
                )
                thinDivider
                breakdownRow(
                    label: "IMPLANTS",
                    icon: "brain.head.profile",
                    value: implantsISK,
                    color: Color(red: 0.85, green: 0.60, blue: 1.00),
                    detail: implantCount > 0 ? "\(implantCount) implants" : nil
                )
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 16)
    }

    private func breakdownRow(label: String, icon: String, value: Double, color: Color, detail: String?) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Color.eveText.opacity(0.38))
                if let d = detail {
                    Text(d)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.eveText.opacity(0.28))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(iskCompact(value))
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(value > 0 ? Color.eveText : Color.eveText.opacity(0.28))
                if totalISK > 0 && value > 0 {
                    Text(String(format: "%.1f%%", value / totalISK * 100))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Color.eveText.opacity(0.35))
                }
            }
        }
        .padding(.vertical, 13)
    }

    private var thinDivider: some View {
        Color.white.opacity(0.06).frame(height: 1)
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            async let walletFetch  = characterService.wallet()
            async let assetsFetch  = characterService.assets()
            async let ordersFetch  = characterService.marketOrders()
            async let implantsFetch = characterService.implants()
            async let pricesFetch  = MarketService().marketPrices()

            let (wallet, assets, orders, implants, prices) =
                try await (walletFetch, assetsFetch, ordersFetch, implantsFetch, pricesFetch)

            // Build price lookup (prefer adjustedPrice, fall back to averagePrice)
            var priceMap: [Int: Double] = [:]
            for p in prices {
                priceMap[p.typeId] = p.adjustedPrice ?? p.averagePrice ?? 0
            }

            walletISK = wallet

            // Assets value
            var aValue = 0.0
            var aCount = 0
            for asset in assets {
                let unitPrice = priceMap[asset.typeId] ?? 0
                if unitPrice > 0 { aCount += 1 }
                aValue += Double(asset.quantity) * unitPrice
            }
            assetsISK = aValue
            assetCount = assets.count

            // Active orders: use escrow value (price × volumeRemain)
            let activeOrders = orders.filter { $0.state == "active" }
            ordersISK = activeOrders.reduce(0) { $0 + $1.price * Double($1.volumeRemain) }
            orderCount = activeOrders.count

            // Implants
            implantsISK = implants.reduce(0) { $0 + (priceMap[$1] ?? 0) }
            implantCount = implants.count

            pricesMissing = assets.contains { (priceMap[$0.typeId] ?? 0) == 0 }
                         || implants.contains { (priceMap[$0] ?? 0) == 0 }
        } catch {
            self.error = error
        }
    }

    // MARK: - Formatting

    private func iskFormatted(_ v: Double) -> String {
        if v >= 1_000_000_000_000 { return String(format: "%.2f T", v / 1_000_000_000_000) }
        if v >= 1_000_000_000     { return String(format: "%.2f B", v / 1_000_000_000) }
        if v >= 1_000_000         { return String(format: "%.2f M", v / 1_000_000) }
        return String(format: "%.0f", v)
    }

    private func iskCompact(_ v: Double) -> String {
        if v == 0 { return "—" }
        if v >= 1_000_000_000_000 { return String(format: "%.2fT ISK", v / 1_000_000_000_000) }
        if v >= 1_000_000_000     { return String(format: "%.2fB ISK", v / 1_000_000_000) }
        if v >= 1_000_000         { return String(format: "%.2fM ISK", v / 1_000_000) }
        if v >= 1_000             { return String(format: "%.1fK ISK", v / 1_000) }
        return String(format: "%.0f ISK", v)
    }
}

// MARK: - Model

private struct WealthSegment: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let color: Color
}
