import SwiftUI
import EVEAuth

/// Wallet as on the desktop: balance and the last 30 days (income, expenses, total), the main items of
/// the month by kind, and the journal.
struct WalletTabView: View {
    let characterService: CharacterService
    @State private var balance: Double?
    @State private var entries: [ESIWalletEntry] = []
    @State private var isLoading = true
    @State private var error: Error?
    @State private var searchText = ""

    private var filtered: [ESIWalletEntry] {
        guard !searchText.isEmpty else { return entries }
        return entries.filter {
            eveRefLabel($0.refType).localizedCaseInsensitiveContains(searchText) ||
            ($0.description?.localizedCaseInsensitiveContains(searchText) == true)
        }
    }

    private var month: [ESIWalletEntry] {
        let since = Date().addingTimeInterval(-30 * 86_400)
        return entries.filter { $0.date >= since }
    }

    private var income: Double { month.compactMap(\.amount).filter { $0 > 0 }.reduce(0, +) }
    private var expense: Double { month.compactMap(\.amount).filter { $0 < 0 }.reduce(0, +) }

    /// The month's amounts by kind of operation, biggest first.
    private var items: [(ref: String, amount: Double)] {
        Dictionary(grouping: month, by: \.refType)
            .map { (ref: $0.key, amount: $0.value.compactMap(\.amount).reduce(0, +)) }
            .filter { $0.amount != 0 }
            .sorted { abs($0.amount) > abs($1.amount) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                stats
                if !items.isEmpty { itemsCard }
                journalCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, EVELayout.scrollBottomClearance)
        }
        .background(C.bg)
        .overlay { if isLoading && entries.isEmpty { ProgressView() } }
        .refreshable { await load() }
        .navigationTitle("Wallet")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Filter transactions")
        .task { await load() }
        .alert("Error", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } })
        ) {
            Button("Retry") { Task { await load() } }
            Button("Dismiss", role: .cancel) {}
        } message: { Text(error?.localizedDescription ?? "") }
    }

    private var stats: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            StatTile(label: "Balance", value: balance.map { Fmt.isk($0) } ?? "—", sub: balance.map { Fmt.isk($0, compact: false) })
            StatTile(label: "Income, 30 days", value: Fmt.isk(income), valueColor: C.good)
            StatTile(label: "Expenses, 30 days", value: Fmt.isk(expense), valueColor: C.bad)
            StatTile(label: "Total, 30 days", value: Fmt.isk(income + expense), valueColor: income + expense >= 0 ? C.text : C.bad)
        }
    }

    private var itemsCard: some View {
        let top = Array(items.prefix(8))
        let maxAbs = top.map { abs($0.amount) }.max() ?? 1
        return Card("Main items, 30 days") {
            VStack(spacing: 9) {
                ForEach(top, id: \.ref) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(eveRefLabel(item.ref))
                                .font(.ui(14))
                                .foregroundStyle(C.text)
                                .lineLimit(1)
                            Spacer()
                            Text(Fmt.signed(item.amount))
                                .font(.ui(14, .medium))
                                .monospacedDigit()
                                .foregroundStyle(item.amount >= 0 ? C.good : C.bad)
                        }
                        GeometryReader { geo in
                            Capsule()
                                .fill((item.amount >= 0 ? C.good : C.bad).opacity(0.55))
                                .frame(width: max(3, geo.size.width * abs(item.amount) / maxAbs))
                        }
                        .frame(height: 4)
                    }
                }
            }
        }
    }

    private var journalCard: some View {
        Card(title: "Journal", actions: {
            Text("\(filtered.prefix(200).count)").font(.ui(12)).foregroundStyle(C.muted)
        }) {
            if filtered.isEmpty && !isLoading {
                Text("No transactions found.")
                    .font(.ui(14))
                    .foregroundStyle(C.muted)
            }
            LazyVStack(spacing: 0) {
                ForEach(filtered.prefix(200)) { entry in
                    row(entry)
                    if entry.id != filtered.prefix(200).last?.id {
                        Rectangle().fill(C.border).frame(height: 1)
                    }
                }
            }
        }
    }

    private func row(_ entry: ESIWalletEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(eveRefLabel(entry.refType))
                    .font(.ui(14))
                    .foregroundStyle(C.text)
                    .lineLimit(1)
                Text(entry.date, format: .relative(presentation: .named))
                    .font(.ui(12))
                    .foregroundStyle(C.muted)
                if let desc = entry.description, !desc.isEmpty {
                    Text(desc)
                        .font(.ui(12))
                        .foregroundStyle(C.faint)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let amt = entry.amount {
                Text(Fmt.signed(amt))
                    .font(.ui(14, .medium))
                    .monospacedDigit()
                    .foregroundStyle(amt >= 0 ? C.good : C.bad)
            }
        }
        .padding(.vertical, 10)
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            async let b = characterService.wallet()
            async let j = characterService.walletJournal()
            let (bal, journal) = try await (b, j)
            balance = bal
            entries = journal.sorted { $0.date > $1.date }
        } catch {
            self.error = error
        }
    }
}
