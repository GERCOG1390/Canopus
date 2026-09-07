import SwiftUI
import EVEAuth

struct ContractsView: View {
    let characterService: CharacterService
    @State private var contracts: [ESIContract] = []
    @State private var isLoading = true
    @State private var error: Error?

    private static let activeStatuses: Set<String> = ["outstanding", "in_progress"]

    private var activeContracts: [ESIContract] {
        contracts.filter { Self.activeStatuses.contains($0.status) }
            .sorted { $0.dateExpired < $1.dateExpired }
    }
    private var finishedContracts: [ESIContract] {
        contracts.filter { !Self.activeStatuses.contains($0.status) }
            .sorted { ($0.dateCompleted ?? $0.dateExpired) > ($1.dateCompleted ?? $1.dateExpired) }
    }

    var body: some View {
        List {
            if !activeContracts.isEmpty {
                Section("Active (\(activeContracts.count))") {
                    ForEach(activeContracts) { contract in
                        ContractRow(contract: contract)
                    }
                }
            }
            if !finishedContracts.isEmpty {
                Section("Completed") {
                    ForEach(finishedContracts.prefix(50)) { contract in
                        ContractRow(contract: contract)
                    }
                }
            }
        }
        .navigationTitle("Contracts")
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if isLoading {
                ProgressView()
            } else if contracts.isEmpty && error == nil {
                ContentUnavailableView(
                    "No contracts",
                    systemImage: "doc.text",
                    description: Text("Your contracts will appear here.")
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
            contracts = try await characterService.contracts()
        } catch {
            self.error = error
        }
    }
}

private struct ContractRow: View {
    let contract: ESIContract

    var body: some View {
        HStack(spacing: 12) {
            typeIcon
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(contract.title?.isEmpty == false ? contract.title! : typeLabel)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(typeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let value = displayValue {
                        Text(value)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 4) {
                    Text(statusLabel)
                        .font(.caption2)
                        .foregroundStyle(statusColor)
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(expiryText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 8) {
                    Text(contract.availability.capitalized)
                    if contract.forCorporation {
                        Text("Corp")
                    }
                    if let collateral = contract.collateral, collateral > 0 {
                        Text("Collateral \(isk(collateral))")
                    }
                    if let volume = contract.volume, volume > 0 {
                        Text(String(format: "%.1f m3", volume))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)
        }
        .padding(.vertical, 2)
    }

    private var typeIcon: some View {
        Image(systemName: typeSystemImage)
            .font(.system(size: 16))
            .foregroundStyle(typeColor)
            .frame(width: 36, height: 36)
            .background(typeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var typeSystemImage: String {
        switch contract.type {
        case "item_exchange": return "arrow.left.arrow.right"
        case "auction":       return "hammer.fill"
        case "courier":       return "shippingbox.fill"
        case "loan":          return "banknote.fill"
        default:              return "doc.text"
        }
    }

    private var typeColor: Color {
        switch contract.type {
        case "item_exchange": return Color.accentColor
        case "auction":       return .orange
        case "courier":       return .teal
        case "loan":          return .yellow
        default:              return .secondary
        }
    }

    private var typeLabel: String {
        switch contract.type {
        case "item_exchange": return "Item Exchange"
        case "auction":       return "Auction"
        case "courier":       return "Courier"
        case "loan":          return "Loan"
        default:              return contract.type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private var displayValue: String? {
        let reward = contract.reward ?? 0
        let price = contract.price ?? 0
        let amount = max(reward, price)
        guard amount > 0 else { return nil }
        if amount >= 1_000_000_000 { return String(format: "%.2fB ISK", amount / 1_000_000_000) }
        if amount >= 1_000_000     { return String(format: "%.2fM ISK", amount / 1_000_000) }
        return String(format: "%.0f ISK", amount)
    }

    private func isk(_ amount: Double) -> String {
        if amount >= 1_000_000_000 { return String(format: "%.2fB", amount / 1_000_000_000) }
        if amount >= 1_000_000     { return String(format: "%.2fM", amount / 1_000_000) }
        if amount >= 1_000         { return String(format: "%.1fK", amount / 1_000) }
        return String(format: "%.0f", amount)
    }

    private var statusLabel: String {
        switch contract.status {
        case "outstanding":         return "Outstanding"
        case "in_progress":         return "In Progress"
        case "finished_issuer":     return "Finished"
        case "finished_contractor": return "Finished"
        case "finished":            return "Finished"
        case "cancelled":           return "Cancelled"
        case "rejected":            return "Rejected"
        case "failed":              return "Failed"
        case "deleted":             return "Deleted"
        default:                    return contract.status.capitalized
        }
    }

    private var statusColor: Color {
        switch contract.status {
        case "outstanding", "in_progress": return .green
        case "finished", "finished_issuer", "finished_contractor": return .secondary
        case "cancelled", "rejected", "failed": return .red
        default: return .secondary
        }
    }

    private var expiryText: String {
        if let completed = contract.dateCompleted {
            return "Completed " + completed.formatted(date: .abbreviated, time: .omitted)
        }
        let remaining = contract.dateExpired.timeIntervalSinceNow
        if remaining <= 0 { return "Expired" }
        let days = Int(remaining / 86400)
        if days >= 1 { return "Expires in \(days)d" }
        let hours = Int(remaining / 3600)
        return "Expires in \(hours)h"
    }
}
