import SwiftUI
import EVEAuth
import EVEStaticData
import Domain

struct MarketOrdersView: View {
    let characterService: CharacterService
    @Environment(AppEnvironment.self) private var env
    @State private var orders: [ESIMarketOrder] = []
    @State private var typeNames: [Int: String] = [:]
    @State private var isLoading = true
    @State private var error: Error?

    private var sellOrders: [ESIMarketOrder] {
        orders.filter { $0.state == "active" && !($0.isBuyOrder ?? false) }
            .sorted { $0.issued > $1.issued }
    }
    private var buyOrders: [ESIMarketOrder] {
        orders.filter { $0.state == "active" && ($0.isBuyOrder ?? false) }
            .sorted { $0.issued > $1.issued }
    }

    var body: some View {
        List {
            if !sellOrders.isEmpty {
                Section("Sell Orders (\(sellOrders.count))") {
                    ForEach(sellOrders) { order in
                        MarketOrderRow(order: order, typeNames: typeNames)
                    }
                }
            }
            if !buyOrders.isEmpty {
                Section("Buy Orders (\(buyOrders.count))") {
                    ForEach(buyOrders) { order in
                        MarketOrderRow(order: order, typeNames: typeNames)
                    }
                }
            }
        }
        .navigationTitle("Market Orders")
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if isLoading {
                ProgressView()
            } else if orders.isEmpty && error == nil {
                ContentUnavailableView(
                    "No active orders",
                    systemImage: "chart.bar",
                    description: Text("Place orders in EVE's market to see them here.")
                )
            }
        }
        .task { await load() }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Retry") { Task { await load() } }
            Button("Dismiss", role: .cancel) {}
        } message: { Text(error?.localizedDescription ?? "") }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            orders = try await characterService.marketOrders()
            let ids = Set(orders.map(\.typeId))
            if let repo = env.repository {
                for id in ids {
                    if let t = try? await repo.type(id: id) { typeNames[id] = t.name }
                }
            }
        } catch {
            self.error = error
        }
    }
}

private struct MarketOrderRow: View {
    let order: ESIMarketOrder
    let typeNames: [Int: String]

    private var isBuy: Bool { order.isBuyOrder ?? false }
    private var fillRatio: Double {
        guard order.volumeTotal > 0 else { return 0 }
        return Double(order.volumeTotal - order.volumeRemain) / Double(order.volumeTotal)
    }
    private var orderColor: Color { isBuy ? .blue : .green }

    var body: some View {
        HStack(spacing: 12) {
            EVETypeIcon(typeId: order.typeId, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(typeNames[order.typeId] ?? "Type \(order.typeId)")
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Text(priceFormatted(order.price))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(orderColor)
                    Text("\(order.volumeRemain) / \(order.volumeTotal)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: fillRatio)
                    .tint(orderColor)

                HStack(spacing: 8) {
                    Text("Region \(order.regionId)")
                    Text("Location \(order.locationId)")
                    if let minVolume = order.minVolume, minVolume > 1 {
                        Text("Min \(minVolume)")
                    }
                    if let range = order.range, !range.isEmpty {
                        Text(range.capitalized)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                Text(isBuy ? "BUY" : "SELL")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(orderColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(orderColor)
                Text(expiryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(ageText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var expiryText: String {
        let expires = order.issued.addingTimeInterval(Double(order.duration) * 86400)
        let remaining = expires.timeIntervalSinceNow
        if remaining <= 0 { return "Expired" }
        let days = Int(remaining / 86400)
        if days >= 1 { return "\(days)d left" }
        let hours = Int(remaining / 3600)
        return "\(hours)h left"
    }

    private var ageText: String {
        let days = max(0, Int(Date().timeIntervalSince(order.issued) / 86400))
        if days == 0 { return "Today" }
        return "\(days)d old"
    }

    private func priceFormatted(_ price: Double) -> String {
        if price >= 1_000_000_000 { return String(format: "%.2fB", price / 1_000_000_000) }
        if price >= 1_000_000     { return String(format: "%.2fM", price / 1_000_000) }
        if price >= 1_000         { return String(format: "%.1fK", price / 1_000) }
        return String(format: "%.2f", price)
    }
}
