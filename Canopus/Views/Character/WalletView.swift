import SwiftUI
import EVEAuth

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

    var body: some View {
        ZStack {
            Color.eveBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    balanceHeader
                    searchBar
                    transactionList
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            if isLoading { ProgressView().tint(Color.eveCyan) }
        }
        .navigationTitle("WALLET")
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

    // MARK: - Balance header

    private var balanceHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("BALANCE").hudLabel()

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(balance.map(iskLarge) ?? "—")
                    .font(.system(size: 34, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.eveText)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("ISK")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Color.eveText.opacity(0.38))
            }
            .padding(.top, 10)
        }
        .overlay(alignment: .bottom) {
            Color.eveAmber.opacity(0.16).frame(height: 1).offset(y: 10)
        }
        .padding(.bottom, 14)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Color.eveText.opacity(0.35))
            TextField("", text: $searchText, prompt:
                Text("Filter transactions")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.eveText.opacity(0.28)))
            .font(.system(size: 13))
            .foregroundStyle(Color.eveText)
            .autocorrectionDisabled()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .eveCard()
    }

    // MARK: - Transaction list

    @ViewBuilder
    private var transactionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TRANSACTIONS · \(filtered.prefix(200).count)")
                .hudLabel()
                .padding(.bottom, 9)

            if filtered.isEmpty && !isLoading {
                Text("No transactions found.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.eveText.opacity(0.38))
                    .padding(.top, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(filtered.prefix(200)) { entry in
                        txRow(entry)
                        Color.white.opacity(0.055).frame(height: 1)
                    }
                }
            }
        }
    }

    private func txRow(_ entry: ESIWalletEntry) -> some View {
        let pos = (entry.amount ?? 0) >= 0
        let amtColor: Color = pos ? .eveGreen : .eveRed

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(eveRefLabel(entry.refType))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.eveText)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(entry.refType.replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(.system(size: 9.5))
                        .tracking(1.0)
                        .foregroundStyle(Color.eveText.opacity(0.38))
                    Text("·")
                        .foregroundStyle(Color.eveText.opacity(0.2))
                    Text(entry.date, style: .relative)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.eveText.opacity(0.38))
                }
                if let desc = entry.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.eveText.opacity(0.38))
                        .lineLimit(1)
                }
            }
            Spacer()
            if let amt = entry.amount {
                Text(formatAmt(amt))
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(amtColor)
            }
        }
        .padding(.vertical, 13)
        .background(Color.eveBackground)
    }

    // MARK: - Load

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

    // MARK: - Formatting

    private func iskLarge(_ v: Double) -> String {
        if v >= 1_000_000_000 { return String(format: "%.2f B", v / 1_000_000_000) }
        if v >= 1_000_000     { return String(format: "%.2f M", v / 1_000_000) }
        return String(format: "%.0f", v)
    }

    private func formatAmt(_ v: Double) -> String {
        let sign = v >= 0 ? "+" : ""
        if abs(v) >= 1_000_000_000 { return sign + String(format: "%.2fB", v / 1_000_000_000) }
        if abs(v) >= 1_000_000     { return sign + String(format: "%.2fM", v / 1_000_000) }
        if abs(v) >= 1_000         { return sign + String(format: "%.1fK", v / 1_000) }
        return sign + String(format: "%.0f", v)
    }
}

