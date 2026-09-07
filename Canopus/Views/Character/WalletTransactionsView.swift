import SwiftUI
import EVEAuth
import EVEStaticData
import Domain

struct WalletTransactionsView: View {
    let characterService: CharacterService
    @Environment(AppEnvironment.self) private var env

    @State private var transactions: [ESIWalletTransaction] = []
    @State private var typeNames: [Int: String] = [:]
    @State private var clientNames: [Int: String] = [:]
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var hasMore = true
    @State private var showBuy  = true
    @State private var showSell = true
    @State private var error: Error?

    private var filtered: [ESIWalletTransaction] {
        transactions.filter { t in
            (showBuy && t.isBuy) || (showSell && !t.isBuy)
        }
    }

    private var totalBought: Double { transactions.filter(\.isBuy).reduce(0) { $0 + $1.unitPrice * Double($1.quantity) } }
    private var totalSold:   Double { transactions.filter { !$0.isBuy }.reduce(0) { $0 + $1.unitPrice * Double($1.quantity) } }

    var body: some View {
        ZStack {
            Color.eveBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                summaryHeader
                Color.eveAmber.opacity(0.14).frame(height: 1)
                filterRow
                Color.eveAmber.opacity(0.14).frame(height: 1)
                txList
            }
            if isLoading { ProgressView().tint(Color.eveCyan) }
        }
        .navigationTitle("TRANSACTIONS")
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

    // MARK: - Summary

    private var summaryHeader: some View {
        HStack(spacing: 0) {
            summaryCell(label: "BOUGHT", value: totalBought, color: Color.eveRed)
            Color.white.opacity(0.08).frame(width: 1)
            summaryCell(label: "SOLD", value: totalSold, color: Color.eveGreen)
            Color.white.opacity(0.08).frame(width: 1)
            summaryCell(label: "NET", value: totalSold - totalBought,
                        color: totalSold >= totalBought ? Color.eveGreen : Color.eveRed)
        }
        .background(Color.eveCard)
        .padding(.vertical, 2)
    }

    private func summaryCell(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label).hudLabel()
            Text(iskCompact(abs(value)))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(value == 0 ? Color.eveText.opacity(0.28) : color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    // MARK: - Filter

    private var filterRow: some View {
        HStack(spacing: 10) {
            filterChip(label: "BUY", active: showBuy, color: Color.eveRed)  { showBuy.toggle() }
            filterChip(label: "SELL", active: showSell, color: Color.eveGreen) { showSell.toggle() }
            Spacer()
            Text("\(filtered.count) RECORDS")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.eveText.opacity(0.28))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(Color.eveCard)
    }

    private func filterChip(label: String, active: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(active ? color : Color.eveText.opacity(0.35))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .overlay(CutCorner(size: 4).stroke(active ? color.opacity(0.5) : Color.white.opacity(0.12), lineWidth: 1))
                .background(active ? color.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - List

    private var txList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filtered) { tx in
                    txRow(tx)
                    Color.white.opacity(0.055).frame(height: 1)
                }
                if hasMore && !filtered.isEmpty {
                    Button {
                        Task { await loadMore() }
                    } label: {
                        HStack(spacing: 8) {
                            if isLoadingMore { ProgressView().tint(Color.eveCyan).scaleEffect(0.8) }
                            Text("LOAD MORE")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(1.6)
                                .foregroundStyle(Color.eveCyan)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingMore)
                }
            }
            .padding(.bottom, 40)
        }
    }

    private func txRow(_ tx: ESIWalletTransaction) -> some View {
        let total = tx.unitPrice * Double(tx.quantity)
        let color: Color = tx.isBuy ? .eveRed : .eveGreen

        return HStack(spacing: 12) {
            // Buy/sell indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(typeNames[tx.typeId] ?? "Type \(tx.typeId)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.eveText)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(tx.isBuy ? "BUY" : "SELL")
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(color)
                    Text("×\(tx.quantity.formatted())")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Color.eveText.opacity(0.45))
                    Text("@")
                        .foregroundStyle(Color.eveText.opacity(0.25))
                    Text(iskCompact(tx.unitPrice))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Color.eveText.opacity(0.45))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(iskCompact(total))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.eveText)
                Text(tx.date, style: .relative)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.eveText.opacity(0.32))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(Color.eveBackground)
    }

    // MARK: - Load

    private func load() async {
        isLoading = true; error = nil; defer { isLoading = false }
        do {
            let txs = try await characterService.walletTransactions()
            transactions = txs.sorted { $0.date > $1.date }
            hasMore = txs.count == 2500
            await resolveTypeNames(txs)
        } catch { self.error = error }
    }

    private func loadMore() async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true; defer { isLoadingMore = false }
        let fromId = transactions.map(\.transactionId).min()
        guard let more = try? await characterService.walletTransactions(fromId: fromId) else { return }
        let fresh = more.filter { m in !transactions.contains(where: { $0.transactionId == m.transactionId }) }
        transactions += fresh.sorted { $0.date > $1.date }
        hasMore = more.count == 2500
        await resolveTypeNames(fresh)
    }

    private func resolveTypeNames(_ txs: [ESIWalletTransaction]) async {
        guard let repo = env.repository else { return }
        let unknownTypes = Set(txs.map(\.typeId)).subtracting(typeNames.keys)
        for id in unknownTypes {
            if let t = try? await repo.type(id: id) { typeNames[id] = t.name }
        }
    }

    private func iskCompact(_ v: Double) -> String {
        if v >= 1_000_000_000 { return String(format: "%.2fB", v / 1_000_000_000) }
        if v >= 1_000_000     { return String(format: "%.2fM", v / 1_000_000) }
        if v >= 1_000         { return String(format: "%.1fK", v / 1_000) }
        return String(format: "%.2f", v)
    }
}
