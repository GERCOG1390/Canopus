import SwiftUI
import EVEAuth

struct WalletJournalView: View {
    let characterService: CharacterService
    @State private var entries: [ESIWalletEntry] = []
    @State private var isLoading = true
    @State private var error: Error?
    @State private var searchText = ""

    private var filtered: [ESIWalletEntry] {
        if searchText.isEmpty { return entries }
        return entries.filter {
            eveRefLabel($0.refType).localizedCaseInsensitiveContains(searchText) ||
            ($0.description?.localizedCaseInsensitiveContains(searchText) == true)
        }
    }

    var body: some View {
        List {
            ForEach(filtered.prefix(200)) { entry in
                WalletEntryRow(entry: entry)
            }
        }
        .eveTabBarClearance()
        .searchable(text: $searchText, prompt: "Search journal…")
        .navigationTitle("Wallet Journal")
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if isLoading {
                ProgressView()
            } else if entries.isEmpty && error == nil {
                ContentUnavailableView(
                    "No Journal Entries",
                    systemImage: "doc.text",
                    description: Text("Your wallet transactions will appear here.")
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
            let raw = try await characterService.walletJournal()
            entries = raw.sorted { $0.date > $1.date }
        } catch {
            self.error = error
        }
    }
}


private struct WalletEntryRow: View {
    let entry: ESIWalletEntry

    private var amountColor: Color {
        guard let a = entry.amount else { return .secondary }
        return a >= 0 ? .green : Color(red: 0.9, green: 0.3, blue: 0.2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(eveRefLabel(entry.refType))
                    .font(.body)
                Spacer()
                if let amount = entry.amount {
                    Text(formatISK(amount))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(amountColor)
                }
            }

            HStack {
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let balance = entry.balance {
                    Text("Balance: " + formatISK(balance))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if let desc = entry.description, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func formatISK(_ v: Double) -> String {
        let sign = v >= 0 ? "+" : ""
        if abs(v) >= 1_000_000_000 { return sign + String(format: "%.2fB", v / 1_000_000_000) }
        if abs(v) >= 1_000_000     { return sign + String(format: "%.2fM", v / 1_000_000) }
        if abs(v) >= 1_000         { return sign + String(format: "%.1fK", v / 1_000) }
        return sign + String(format: "%.2f", v)
    }
}
