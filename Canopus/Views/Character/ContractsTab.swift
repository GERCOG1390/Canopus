// Contracts as the desktop's character/Contracts.tsx: newest first, "only active" filter, each one opens
// to its route, collateral, volume, expiry and the items given or asked for.

import SwiftUI
import Domain
import EVEAuth
import EVEStaticData

func contractTypeLabel(_ t: String) -> String {
    switch t {
    case "item_exchange": String(localized: "Item exchange")
    case "auction": String(localized: "Auction")
    case "courier": String(localized: "Courier")
    case "loan": String(localized: "Loan")
    default: "?"
    }
}

func contractStatusLabel(_ s: String) -> String {
    switch s {
    case "outstanding": String(localized: "Outstanding")
    case "in_progress": String(localized: "In progress")
    case "finished_issuer", "finished_contractor", "finished": String(localized: "Finished")
    case "cancelled", "reversed": String(localized: "Cancelled")
    case "rejected": String(localized: "Rejected")
    case "failed": String(localized: "Failed")
    case "deleted": String(localized: "Deleted")
    default: s
    }
}

struct ContractsTab: View {
    let characterService: CharacterService
    @Environment(AppEnvironment.self) private var env
    @State private var contracts: [ESIContract]?
    @State private var names: [Int: String] = [:]
    @State private var places: [Int: String] = [:]
    @State private var onlyActive = false
    @State private var open: Int?
    @State private var error: Error?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if error != nil {
                    ScopeHint(scope: "esi-contracts.read_character_contracts.v1")
                } else if let contracts {
                    Button(onlyActive ? "✓ Only active" : "Only active") { onlyActive.toggle() }
                        .buttonStyle(CanopusButtonStyle(kind: onlyActive ? .primary : .ghost, small: true))
                    let list = contracts.filter { !onlyActive || $0.status == "outstanding" || $0.status == "in_progress" }
                    Card {
                        if list.isEmpty { Text("No contracts").font(.ui(13)).foregroundStyle(C.muted) }
                        ForEach(list) { c in
                            row(c)
                            if c.id != list.last?.id { Rectangle().fill(C.border).frame(height: 1) }
                        }
                    }
                } else {
                    ProgressView().tint(C.accent).frame(maxWidth: .infinity).padding(.top, 30)
                }
            }
            .padding(16)
        }
        .refreshable { await load() }
        .task(id: env.dataKey) { await load() }
    }

    private func row(_ c: ESIContract) -> some View {
        let isOpen = open == c.id
        let amount = c.type == "courier" ? c.reward ?? 0 : c.price ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            Button { open = isOpen ? nil : c.id } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(verbatim: isOpen ? "▾" : "▸").font(.ui(11)).foregroundStyle(C.muted)
                        Text(verbatim: contractTypeLabel(c.type)).font(.ui(13, .medium)).foregroundStyle(C.text)
                        Text(verbatim: c.title?.isEmpty == false ? c.title! : String(localized: "untitled"))
                            .font(.ui(13)).foregroundStyle(c.title?.isEmpty == false ? C.text : C.muted).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(verbatim: Fmt.isk(amount)).font(.mono(12, medium: true)).foregroundStyle(C.text)
                    }
                    HStack(spacing: 6) {
                        Pill(text: contractStatusLabel(c.status), color: c.status == "outstanding" || c.status == "in_progress" ? C.accent : C.muted)
                        Text(verbatim: "\(names[c.issuerId] ?? "…") → \(c.assigneeId != 0 ? names[c.assigneeId] ?? "…" : String(localized: "public"))")
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(verbatim: c.dateIssued.formatted(date: .abbreviated, time: .omitted))
                    }
                    .font(.ui(11)).foregroundStyle(C.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen { ContractDetails(contract: c, service: characterService, places: places) }
        }
        .padding(.vertical, 6)
    }

    private func load() async {
        do {
            let list = try await characterService.contracts().sorted { $0.dateIssued > $1.dateIssued }
            contracts = list
            error = nil
            let people = Set(list.flatMap { [$0.issuerId, $0.assigneeId, $0.acceptorId] }.filter { $0 > 0 })
            if let resolved = try? await characterService.resolveNames(ids: Array(people)) {
                names = Dictionary(resolved.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
            }
            places = await LocationNames.resolve(list.flatMap { [$0.startLocationId ?? 0, $0.endLocationId ?? 0] }, service: characterService)
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }
}

private struct ContractDetails: View {
    let contract: ESIContract
    let service: CharacterService
    let places: [Int: String]
    @Environment(AppEnvironment.self) private var env
    @State private var items: [ESIContractItem]?
    @State private var typeNames: [Int: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let c = contract
            VStack(alignment: .leading, spacing: 2) {
                if let from = c.startLocationId { Text("From: \(places[from] ?? String(from))") }
                if let to = c.endLocationId, to != c.startLocationId { Text("To: \(places[to] ?? String(to))") }
                if let col = c.collateral, col > 0 { Text("Collateral: \(Fmt.isk(col))") }
                if let v = c.volume, v > 0 { Text("Volume: \(v.formatted(.number.precision(.fractionLength(0...1)))) m³") }
                Text("Expires: \(c.dateExpired.formatted(date: .abbreviated, time: .shortened))")
            }
            .font(.ui(12)).foregroundStyle(C.muted)
            if let items {
                if items.isEmpty {
                    Text("No items (or ESI doesn't give them for this contract).").font(.ui(12)).foregroundStyle(C.muted)
                }
                ForEach(items) { i in
                    HStack(spacing: 6) {
                        Text(i.isIncluded ? "gives" : "asks").font(.ui(11)).foregroundStyle(i.isIncluded ? C.good : C.bad).frame(width: 52, alignment: .leading)
                        EVETypeIcon(typeId: i.typeId, size: 22)
                        Text(verbatim: typeNames[i.typeId] ?? "#\(i.typeId)").font(.ui(13)).foregroundStyle(C.text).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(verbatim: "×\(i.quantity.formatted())").font(.mono(12)).foregroundStyle(C.muted)
                    }
                }
            } else {
                ProgressView().tint(C.accent)
            }
        }
        .padding(.leading, 18)
        .task {
            let list = (try? await service.contractItems(contractId: contract.contractId)) ?? []
            typeNames = ((try? await env.repository?.types(ids: Set(list.map(\.typeId)))) ?? [:]).mapValues(\.name)
            items = list
        }
    }
}

/// Explains a missing ESI scope (the token predates the scope or the app lacks it), as the desktop's.
struct ScopeHint: View {
    let scope: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No access to this data.").font(.ui(13, .medium)).foregroundStyle(C.warn)
            Text("The token lacks the \(scope) permission: sign in with this character again in Settings — the new token gets every permission.")
                .font(.ui(12)).foregroundStyle(C.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(C.warn.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(C.warn.opacity(0.4)))
    }
}
