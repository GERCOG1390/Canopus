import SwiftUI
import Charts
import EVEAuth

struct MarketDetailView: View {
    let typeId: Int
    let typeName: String

    private static let historyDateParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .init(identifier: "UTC")
        return formatter
    }()

    @State private var region: EVERegion = .theForge
    @State private var chartData: [HistoryPoint] = []
    @State private var orders: [ESIRegionalOrder] = []
    @State private var isLoadingChart = true
    @State private var isLoadingOrders = true
    @State private var error: Error?

    private let market = MarketService()

    private var sellOrders: [ESIRegionalOrder] { orders.filter { !$0.isBuyOrder }.sorted { $0.price < $1.price } }
    private var buyOrders:  [ESIRegionalOrder] { orders.filter {  $0.isBuyOrder }.sorted { $0.price > $1.price } }
    private var bestSell: Double? { sellOrders.first?.price }
    private var bestBuy:  Double? { buyOrders.first?.price }
    private var spread: Double? {
        guard let s = bestSell, let b = bestBuy, b > 0 else { return nil }
        return (s - b) / s * 100
    }

    var body: some View {
        ZStack {
            Color.eveBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    regionPicker
                    Color.eveAmber.opacity(0.14).frame(height: 1)
                    priceHeader
                    Color.eveAmber.opacity(0.14).frame(height: 1)
                    chartSection
                    Color.eveAmber.opacity(0.14).frame(height: 1)
                    ordersSection
                }
                .padding(.bottom, EVELayout.scrollBottomClearance)
            }
            if isLoadingOrders && orders.isEmpty && isLoadingChart && chartData.isEmpty {
                ProgressView().tint(Color.eveCyan)
            }
        }
        .navigationTitle(typeName.uppercased())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.eveBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: region) { await loadAll() }
        .alert("Error", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } })
        ) {
            Button("Retry") { Task { await loadAll() } }
            Button("Dismiss", role: .cancel) {}
        } message: { Text(error?.localizedDescription ?? "") }
    }

    // MARK: - Region picker

    private var regionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EVERegion.allCases, id: \.self) { r in
                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) { region = r }
                    } label: {
                        let active = region == r
                        VStack(spacing: 3) {
                            Text(r.hubName)
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(1.0)
                                .foregroundStyle(active ? Color.eveAmber : Color.eveText.opacity(0.50))
                            Text(r.displayName)
                                .font(.system(size: 8.5))
                                .foregroundStyle((active ? Color.eveAmber : Color.eveText).opacity(0.38))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .overlay(CutCorner(size: 5).stroke(
                            active ? Color.eveAmber.opacity(0.6) : Color.white.opacity(0.10),
                            lineWidth: 1))
                        .background(active ? Color.eveAmber.opacity(0.08) : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color.eveCard)
    }

    // MARK: - Price header

    private var priceHeader: some View {
        HStack(spacing: 0) {
            priceCell(label: "BEST SELL", price: bestSell, loading: isLoadingOrders, color: Color.eveRed)
            Color.white.opacity(0.08).frame(width: 1)
            priceCell(label: "BEST BUY", price: bestBuy, loading: isLoadingOrders, color: Color.eveGreen)
            if let sp = spread {
                Color.white.opacity(0.08).frame(width: 1)
                VStack(spacing: 4) {
                    Text("SPREAD").hudLabel()
                    Text(String(format: "%.2f%%", sp))
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.eveText.opacity(0.70))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
        }
        .background(Color.eveCard)
    }

    private func priceCell(label: String, price: Double?, loading: Bool, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label).hudLabel()
            if loading && price == nil {
                ProgressView().tint(color).scaleEffect(0.8).padding(.top, 4)
            } else if let p = price {
                Text(formatPrice(p))
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(color)
                Text("ISK")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.eveText.opacity(0.30))
            } else {
                Text("—")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.eveText.opacity(0.28))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Chart

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PRICE HISTORY · 30 DAYS").hudLabel().padding(.horizontal, 20)

            if isLoadingChart && chartData.isEmpty {
                ProgressView().tint(Color.eveCyan).frame(maxWidth: .infinity).padding(.vertical, 30)
            } else if chartData.isEmpty {
                Text("No history data available")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.eveText.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            } else {
                HUDPriceChart(data: Array(chartData.suffix(30)))
                    .frame(height: 180)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 16)
    }

    // MARK: - Order book

    private var ordersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SELL ORDERS · \(sellOrders.count)").hudLabel()
                Spacer()
                Text("BUY ORDERS · \(buyOrders.count)").hudLabel()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Color.white.opacity(0.06).frame(height: 1)

            if isLoadingOrders && orders.isEmpty {
                ProgressView().tint(Color.eveCyan).frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    // Sell side (left)
                    VStack(spacing: 0) {
                        ForEach(sellOrders.prefix(15)) { o in
                            orderCell(o, isBuy: false)
                            Color.white.opacity(0.04).frame(height: 1)
                        }
                    }

                    Color.white.opacity(0.08).frame(width: 1)

                    // Buy side (right)
                    VStack(spacing: 0) {
                        ForEach(buyOrders.prefix(15)) { o in
                            orderCell(o, isBuy: true)
                            Color.white.opacity(0.04).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private func orderCell(_ order: ESIRegionalOrder, isBuy: Bool) -> some View {
        VStack(alignment: isBuy ? .trailing : .leading, spacing: 3) {
            Text(formatPrice(order.price))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(isBuy ? Color.eveGreen : Color.eveRed)
            Text(formatVol(order.volumeRemain))
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Color.eveText.opacity(0.38))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: isBuy ? .trailing : .leading)
    }

    // MARK: - Load

    private func loadAll() async {
        isLoadingChart = true; isLoadingOrders = true
        chartData = []; orders = []; error = nil

        await withTaskGroup(of: Void.self) { g in
            g.addTask { await self.loadHistory() }
            g.addTask { await self.loadOrders() }
        }
    }

    private func loadHistory() async {
        defer { isLoadingChart = false }
        guard let raw = try? await market.history(regionId: region.rawValue, typeId: typeId) else { return }
        chartData = raw.compactMap { h -> HistoryPoint? in
            guard let d = Self.historyDateParser.date(from: h.date) else { return nil }
            return HistoryPoint(date: d, average: h.average, highest: h.highest, lowest: h.lowest, volume: h.volume)
        }.sorted { $0.date < $1.date }
    }

    private func loadOrders() async {
        defer { isLoadingOrders = false }
        orders = (try? await market.orders(regionId: region.rawValue, typeId: typeId)) ?? []
    }

    // MARK: - Formatting

    private func formatPrice(_ v: Double) -> String {
        if v >= 1_000_000_000 { return String(format: "%.2fB", v / 1_000_000_000) }
        if v >= 1_000_000     { return String(format: "%.2fM", v / 1_000_000) }
        if v >= 1_000         { return String(format: "%.1fK", v / 1_000) }
        return String(format: "%.2f", v)
    }

    private func formatVol(_ v: Int) -> String {
        if v >= 1_000_000 { return String(format: "%.1fM", Double(v) / 1_000_000) }
        if v >= 1_000     { return String(format: "%.0fK", Double(v) / 1_000) }
        return "\(v)"
    }
}

// MARK: - Chart data model

struct HistoryPoint: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let average: Double
    let highest: Double
    let lowest: Double
    let volume: Int
}

// MARK: - HUD price chart

struct HUDPriceChart: View {
    let data: [HistoryPoint]

    private var priceMin: Double { (data.map(\.lowest).min()  ?? 0) * 0.97 }
    private var priceMax: Double { (data.map(\.highest).max() ?? 1) * 1.03 }

    var body: some View {
        Chart {
            ForEach(data) { pt in
                AreaMark(
                    x: .value("Date", pt.date),
                    yStart: .value("Low",  pt.lowest),
                    yEnd:   .value("High", pt.highest)
                )
                .foregroundStyle(Color.eveCyan.opacity(0.10))
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Date", pt.date),
                    y: .value("Avg",  pt.average)
                )
                .foregroundStyle(Color.eveAmber)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartYScale(domain: priceMin...priceMax)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4))
                    .foregroundStyle(Color.white.opacity(0.10))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(Color.eveText.opacity(0.38))
                    .font(.system(size: 9))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4))
                    .foregroundStyle(Color.white.opacity(0.10))
                if let d = v.as(Double.self) {
                    AxisValueLabel { Text(compactISK(d)).font(.system(size: 9)) }
                        .foregroundStyle(Color.eveText.opacity(0.38))
                }
            }
        }
        .chartBackground { _ in Color.clear }
    }

    private func compactISK(_ v: Double) -> String {
        if v >= 1_000_000_000 { return String(format: "%.1fB", v / 1_000_000_000) }
        if v >= 1_000_000     { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1_000         { return String(format: "%.0fK", v / 1_000) }
        return String(format: "%.0f", v)
    }
}
