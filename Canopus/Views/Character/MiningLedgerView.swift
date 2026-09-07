import SwiftUI
import EVEAuth

struct MiningLedgerView: View {
    let characterService: CharacterService

    @State private var entries: [ESIMiningEntry] = []
    @State private var typeNames: [Int: String] = [:]
    @State private var prices: [Int: Double] = [:]
    @State private var isLoading = true
    @State private var error: Error?

    // Group entries by date → array of entries
    private var grouped: [(date: String, rows: [ESIMiningEntry])] {
        var dict: [String: [ESIMiningEntry]] = [:]
        for e in entries { dict[e.date, default: []].append(e) }
        return dict.keys.sorted(by: >).map { date in
            (date: date, rows: dict[date]!.sorted { ($0.quantity * -1) < ($1.quantity * -1) })
        }
    }

    private func totalISK(_ rows: [ESIMiningEntry]) -> Double {
        rows.reduce(0) { $0 + Double($1.quantity) * (prices[$1.typeId] ?? 0) }
    }

    private var grandTotal: Double {
        entries.reduce(0.0) { acc, e in acc + Double(e.quantity) * (prices[e.typeId] ?? 0) }
    }
    private var grandTotalVol: Int { entries.reduce(0) { $0 + $1.quantity } }

    var body: some View {
        ZStack {
            Color.eveBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    totalHeader
                    Color.eveAmber.opacity(0.14).frame(height: 1)

                    if grouped.isEmpty && !isLoading {
                        ContentUnavailableView("No Mining Data", systemImage: "pickaxe",
                            description: Text("No mining activity recorded in the last 30 days."))
                        .foregroundStyle(Color.eveText)
                        .padding(.top, 60)
                    } else {
                        ForEach(grouped, id: \.date) { group in
                            daySection(group.date, rows: group.rows)
                            Color.eveAmber.opacity(0.10).frame(height: 1)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            if isLoading { ProgressView().tint(Color.eveCyan) }
        }
        .navigationTitle("MINING LEDGER")
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
            Text("30-DAY TOTAL").hudLabel()
            Text(iskFormatted(grandTotal))
                .font(.system(size: 28, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.eveText)
                .padding(.top, 8)
            HStack(spacing: 6) {
                Text(volFormatted(grandTotalVol))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.eveText.opacity(0.45))
                Text("M³  TOTAL VOLUME")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Color.eveText.opacity(0.28))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    // MARK: - Day section

    private func daySection(_ date: String, rows: [ESIMiningEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Day header
            HStack {
                Text(formattedDate(date))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Color.eveAmber)
                Spacer()
                let isk = totalISK(rows)
                if isk > 0 {
                    Text(iskFormatted(isk))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.eveText.opacity(0.55))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.eveCard)

            Color.white.opacity(0.06).frame(height: 1)

            ForEach(rows) { entry in
                oreRow(entry)
                Color.white.opacity(0.04).frame(height: 1)
            }
        }
    }

    private func oreRow(_ entry: ESIMiningEntry) -> some View {
        let unitPrice = prices[entry.typeId] ?? 0
        let total = Double(entry.quantity) * unitPrice

        return HStack(spacing: 12) {
            EVETypeIcon(typeId: entry.typeId, size: 36)
                .clipShape(CutCorner(size: 5))
                .overlay(CutCorner(size: 5).stroke(Color.white.opacity(0.08), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text(typeNames[entry.typeId] ?? "Type \(entry.typeId)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.eveText)
                Text("\(volFormatted(entry.quantity)) m³")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color.eveText.opacity(0.42))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if total > 0 {
                    Text(iskFormatted(total))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.eveGreen)
                } else {
                    Text("—")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color.eveText.opacity(0.28))
                }
                if unitPrice > 0 {
                    Text("@ \(iskFormatted(unitPrice))")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Color.eveText.opacity(0.30))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.eveBackground)
    }

    // MARK: - Load

    private func load() async {
        isLoading = true; error = nil; defer { isLoading = false }
        do {
            async let miningFetch = characterService.miningLedger()
            async let pricesFetch = MarketService().marketPrices()
            let (mined, marketPrices) = try await (miningFetch, pricesFetch)

            entries = mined
            for p in marketPrices {
                prices[p.typeId] = p.adjustedPrice ?? p.averagePrice ?? 0
            }

            // Resolve type names via ESI names endpoint
            let ids = Set(mined.map(\.typeId))
            if let resolved = try? await characterService.resolveNames(ids: Array(ids)) {
                for r in resolved { typeNames[r.id] = r.name }
            }
        } catch { self.error = error }
    }

    // MARK: - Formatting

    private func iskFormatted(_ v: Double) -> String {
        if v >= 1_000_000_000 { return String(format: "%.2fB ISK", v / 1_000_000_000) }
        if v >= 1_000_000     { return String(format: "%.2fM ISK", v / 1_000_000) }
        if v >= 1_000         { return String(format: "%.1fK ISK", v / 1_000) }
        if v == 0             { return "0 ISK" }
        return String(format: "%.0f ISK", v)
    }

    private func volFormatted(_ v: Int) -> String {
        if v >= 1_000_000 { return String(format: "%.1fM", Double(v) / 1_000_000) }
        if v >= 1_000     { return String(format: "%.0fK", Double(v) / 1_000) }
        return "\(v)"
    }

    private func formattedDate(_ dateStr: String) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: dateStr) else { return dateStr }
        let out = DateFormatter(); out.dateStyle = .medium; out.timeStyle = .none
        return out.string(from: d).uppercased()
    }
}
