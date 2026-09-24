import SwiftUI
import Domain
import EVEAuth
import EVEStaticData

struct LoyaltyPointsView: View {
    @Environment(AppEnvironment.self) private var env
    let characterService: CharacterService
    @State private var points: [ESILoyaltyPoint] = []
    @State private var corpNames: [Int: String] = [:]
    @State private var isLoading = true
    @State private var error: Error?

    private var sorted: [ESILoyaltyPoint] {
        points.sorted { $0.loyaltyPoints > $1.loyaltyPoints }
    }

    private var totalLP: Int { points.reduce(0) { $0 + $1.loyaltyPoints } }

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Total LP", systemImage: "star.circle.fill")
                        .foregroundStyle(.tint)
                    Spacer()
                    Text(totalLP.formatted())
                        .font(.headline.monospacedDigit())
                }
            }

            Section("By Corporation") {
                ForEach(sorted) { lp in
                    NavigationLink {
                        LoyaltyPointStoreView(
                            characterService: characterService,
                            corporationId: lp.corporationId,
                            corporationName: corpNames[lp.corporationId] ?? "Corp \(lp.corporationId)",
                            loyaltyPoints: lp.loyaltyPoints
                        )
                    } label: {
                        HStack(spacing: 12) {
                            EVECorpLogo(corpId: lp.corporationId, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(corpNames[lp.corporationId] ?? "Corp \(lp.corporationId)")
                                    .font(.body)
                                Text("\(lp.loyaltyPoints.formatted()) LP")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(lp.loyaltyPoints.formatted())
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.tint)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .eveTabBarClearance()
        .navigationTitle("Loyalty Points")
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if isLoading {
                ProgressView()
            } else if points.isEmpty && error == nil {
                ContentUnavailableView(
                    "No Loyalty Points",
                    systemImage: "star.slash",
                    description: Text("Complete missions to earn LP.")
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
            points = try await characterService.loyaltyPoints()
            let ids = points.map(\.corporationId)
            if let resolved = try? await characterService.resolveNames(ids: ids) {
                for r in resolved { corpNames[r.id] = r.name }
            }
        } catch {
            self.error = error
        }
    }
}

private struct LoyaltyPointStoreView: View {
    @Environment(AppEnvironment.self) private var env

    let characterService: CharacterService
    let corporationId: Int
    let corporationName: String
    let loyaltyPoints: Int

    @State private var offers: [ESILoyaltyStoreOffer] = []
    @State private var typesById: [Int: ItemType] = [:]
    @State private var isLoading = true
    @State private var error: Error?

    private var sortedOffers: [ESILoyaltyStoreOffer] {
        offers.sorted {
            if canAfford($0) != canAfford($1) { return canAfford($0) }
            if $0.lpCost != $1.lpCost { return $0.lpCost < $1.lpCost }
            return itemName($0.typeId) < itemName($1.typeId)
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    EVECorpLogo(corpId: corporationId, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(corporationName)
                            .font(.headline)
                        Text("\(loyaltyPoints.formatted()) LP available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }

            Section("LP Store") {
                ForEach(sortedOffers) { offer in
                    NavigationLink {
                        TypeDetailView(typeId: offer.typeId, typeName: itemName(offer.typeId))
                    } label: {
                        LoyaltyPointOfferRow(
                            offer: offer,
                            itemName: itemName(offer.typeId),
                            requiredItemNames: requiredItemNames(for: offer),
                            canAfford: canAfford(offer)
                        )
                    }
                }
            }
        }
        .eveTabBarClearance()
        .navigationTitle(corporationName)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading {
                ProgressView()
            } else if offers.isEmpty && error == nil {
                ContentUnavailableView(
                    "No LP Store Offers",
                    systemImage: "cart.badge.questionmark",
                    description: Text("This corporation has no public LP store offers.")
                )
            }
        }
        .task { await load() }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Retry") { Task { await load() } }
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text(error?.localizedDescription ?? "")
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let loadedOffers = try await characterService.loyaltyStoreOffers(corpId: corporationId)
            offers = loadedOffers

            let typeIds = Set(
                loadedOffers.flatMap { offer in
                    [offer.typeId] + offer.requiredItems.map(\.typeId)
                }
            )
            if let repository = env.repository {
                typesById = try await repository.types(ids: typeIds)
            }
        } catch {
            self.error = error
        }
    }

    private func itemName(_ typeId: Int) -> String {
        typesById[typeId]?.name ?? "Type \(typeId)"
    }

    private func canAfford(_ offer: ESILoyaltyStoreOffer) -> Bool {
        loyaltyPoints >= offer.lpCost
    }

    private func requiredItemNames(for offer: ESILoyaltyStoreOffer) -> [String] {
        offer.requiredItems.map { item in
            "\(item.quantity.formatted())x \(itemName(item.typeId))"
        }
    }
}

private struct LoyaltyPointOfferRow: View {
    let offer: ESILoyaltyStoreOffer
    let itemName: String
    let requiredItemNames: [String]
    let canAfford: Bool

    var body: some View {
        HStack(spacing: 12) {
            EVETypeIcon(typeId: offer.typeId, size: 42)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(itemName)
                    .font(.body)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text("\(offer.quantity.formatted())x")
                    Text("\(offer.lpCost.formatted()) LP")
                        .foregroundStyle(canAfford ? .green : .secondary)
                    if offer.iskCost > 0 {
                        Text(formatISK(offer.iskCost))
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

                if !requiredItemNames.isEmpty {
                    Text(requiredItemNames.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Text(canAfford ? "OK" : "LP")
                .font(.caption.bold().monospaced())
                .foregroundStyle(canAfford ? .green : .orange)
        }
        .padding(.vertical, 3)
    }

    private func formatISK(_ value: Int) -> String {
        let double = Double(value)
        if double >= 1_000_000_000 { return String(format: "%.2f B ISK", double / 1_000_000_000) }
        if double >= 1_000_000 { return String(format: "%.1f M ISK", double / 1_000_000) }
        if double >= 1_000 { return String(format: "%.0f K ISK", double / 1_000) }
        return "\(value.formatted()) ISK"
    }
}
