import SwiftUI
import EVEAuth
import EVEStaticData
import Domain

private struct AssetItem: Identifiable {
    let id: Int  // typeId — unique per location after aggregation
    var name: String
    var quantity: Int
    var unitPrice: Double?
    var flags: [String]
    var hasSingleton: Bool
    var hasBlueprintCopy: Bool

    var totalValue: Double? {
        unitPrice.map { $0 * Double(quantity) }
    }
}

private struct AssetLocation: Identifiable {
    let id: Int
    var name: String
    var systemName: String?
    var securityStatus: Double?
    var locationType: String
    var items: [AssetItem]
    var totalQuantity: Int { items.reduce(0) { $0 + $1.quantity } }
    var totalValue: Double {
        items.reduce(0) { $0 + ($1.totalValue ?? 0) }
    }
}

struct AssetsView: View {
    let characterService: CharacterService
    @Environment(AppEnvironment.self) private var env
    @State private var locationGroups: [AssetLocation] = []
    @State private var expandedIds: Set<Int> = []
    @State private var isLoading = true
    @State private var loadingPhase = "Loading assets…"
    @State private var error: Error?
    @State private var searchText = ""
    @State private var isRefiningJitaPrices = false
    @State private var jitaPriceCache: [Int: Double] = [:]

    private let market = MarketService()
    private let jitaStationId = 60_003_760
    private let jitaRefinementLimit = 120

    private var filteredGroups: [AssetLocation] {
        guard !searchText.isEmpty else { return locationGroups }
        return locationGroups.compactMap { loc in
            let filtered = loc.items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            guard !filtered.isEmpty else { return nil }
            return AssetLocation(id: loc.id, name: loc.name, systemName: loc.systemName,
                                 securityStatus: loc.securityStatus,
                                 locationType: loc.locationType, items: filtered)
        }
    }

    private var totalTypes: Int { locationGroups.reduce(0) { $0 + $1.items.count } }
    private var totalItems: Int { locationGroups.reduce(0) { $0 + $1.totalQuantity } }
    private var totalValue: Double { locationGroups.reduce(0) { $0 + $1.totalValue } }
    private var assetSummaryText: String {
        let summary = "\(locationGroups.count) locations · \(totalTypes) types · \(totalItems) items · \(formatISK(totalValue))"
        return isRefiningJitaPrices ? "\(summary) · updating Jita" : summary
    }

    var body: some View {
        List {
            ForEach(filteredGroups) { location in
                AssetLocationSection(
                    location: location,
                    isExpanded: expandedBinding(for: location.id)
                )
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.eveBackground)
        .searchable(text: $searchText, prompt: "Search assets…")
        .navigationTitle("Assets")
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(loadingPhase)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if locationGroups.isEmpty && error == nil {
                ContentUnavailableView(
                    "No assets found",
                    systemImage: "archivebox",
                    description: Text("Your in-game items will appear here.")
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !locationGroups.isEmpty && !isLoading {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.eveAmber.opacity(0.28))
                        .frame(height: 1)
                    Text(assetSummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.eveCard.opacity(0.92))

                    Color.clear
                        .frame(height: EVELayout.tabBarClearance)
                }
            }
        }
        .task { await load() }
        .alert("Error", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("Retry") { Task { await load() } }
            Button("Dismiss", role: .cancel) {}
        } message: { Text(error?.localizedDescription ?? "") }
    }

    private func expandedBinding(for locationId: Int) -> Binding<Bool> {
        Binding(
            get: { !searchText.isEmpty || expandedIds.contains(locationId) },
            set: { expanded in
                if expanded { expandedIds.insert(locationId) }
                else { expandedIds.remove(locationId) }
            }
        )
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        loadingPhase = "Loading assets…"
        error = nil
        defer { isLoading = false }
        do {
            let raw = try await characterService.assets()

            let byItemId = Dictionary(uniqueKeysWithValues: raw.map { ($0.itemId, $0) })

            func rootOf(_ asset: ESIAsset, depth: Int = 0) -> ESIAsset {
                if depth > 20 { return asset }
                if asset.locationType == "item", let parent = byItemId[asset.locationId] {
                    return rootOf(parent, depth: depth + 1)
                }
                return asset
            }

            var locationTypes: [Int: String] = [:]
            var locationAssets: [Int: [ESIAsset]] = [:]
            for asset in raw {
                let root = rootOf(asset)
                locationTypes[root.locationId] = root.locationType
                locationAssets[root.locationId, default: []].append(asset)
            }

            loadingPhase = "Loading item names…"
            var typeNames: [Int: String] = [:]
            if let repo = env.repository {
                let typeIds = Set(raw.map(\.typeId))
                if let map = try? await repo.types(ids: typeIds) {
                    typeNames = map.mapValues(\.name)
                }
            }

            loadingPhase = "Loading market prices…"
            let typeIds = Set(raw.map(\.typeId))
            var prices = try await loadEstimatedPrices(typeIds: typeIds)
            prices.merge(jitaPriceCache) { _, jita in jita }

            loadingPhase = "Loading locations…"
            var result: [AssetLocation] = []
            for (locId, assets) in locationAssets {
                let locType = locationTypes[locId] ?? "other"
                let location = await resolveLocation(id: locId, type: locType)

                var counts: [Int: Int] = [:]
                var flagsByType: [Int: Set<String>] = [:]
                var singletonTypes: Set<Int> = []
                var blueprintCopyTypes: Set<Int> = []
                for a in assets {
                    counts[a.typeId, default: 0] += a.isSingleton ? 1 : a.quantity
                    flagsByType[a.typeId, default: []].insert(a.locationFlag)
                    if a.isSingleton { singletonTypes.insert(a.typeId) }
                    if a.isBlueprintCopy == true { blueprintCopyTypes.insert(a.typeId) }
                }
                let items = counts
                    .map {
                        AssetItem(
                            id: $0.key,
                            name: typeNames[$0.key] ?? "Type \($0.key)",
                            quantity: $0.value,
                            unitPrice: prices[$0.key],
                            flags: Array(flagsByType[$0.key] ?? []).sorted(),
                            hasSingleton: singletonTypes.contains($0.key),
                            hasBlueprintCopy: blueprintCopyTypes.contains($0.key)
                        )
                    }
                    .sorted { $0.name < $1.name }

                result.append(AssetLocation(id: locId, name: location.name, systemName: location.systemName,
                                            securityStatus: location.securityStatus,
                                            locationType: locType, items: items))
            }

            let groups = result.sorted { $0.name < $1.name }
            locationGroups = groups
            expandedIds = []

            let refineIds = topTypeIdsForJitaRefinement(from: groups, limit: jitaRefinementLimit)
            Task { await refineJitaPrices(typeIds: refineIds) }
        } catch {
            self.error = error
        }
    }

    private func loadEstimatedPrices(typeIds: Set<Int>) async throws -> [Int: Double] {
        let fallbackPrices = try await market.marketPrices()
        return Dictionary(
            uniqueKeysWithValues: fallbackPrices.compactMap { price in
                guard typeIds.contains(price.typeId),
                      let value = price.averagePrice ?? price.adjustedPrice else {
                    return nil
                }
                return (price.typeId, value)
            }
        )
    }

    private func topTypeIdsForJitaRefinement(from groups: [AssetLocation], limit: Int) -> [Int] {
        var valuesByType: [Int: Double] = [:]
        for item in groups.flatMap(\.items) {
            guard let value = item.totalValue else { continue }
            valuesByType[item.id, default: 0] += value
        }

        return valuesByType
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }

    private func refineJitaPrices(typeIds: [Int]) async {
        guard !isRefiningJitaPrices else { return }
        let missingIds = typeIds.filter { jitaPriceCache[$0] == nil }
        guard !missingIds.isEmpty else { return }

        isRefiningJitaPrices = true
        defer { isRefiningJitaPrices = false }

        for typeId in missingIds {
            guard !Task.isCancelled else { return }
            do {
                let orders = try await market.orders(regionId: EVERegion.theForge.rawValue, typeId: typeId)
                if let lowestJitaSell = orders
                    .filter({ !$0.isBuyOrder && $0.locationId == jitaStationId && $0.volumeRemain > 0 })
                    .map(\.price)
                    .min() {
                    jitaPriceCache[typeId] = lowestJitaSell
                    applyJitaPrice(typeId: typeId, price: lowestJitaSell)
                }
            } catch {
                continue
            }
        }
    }

    private func applyJitaPrice(typeId: Int, price: Double) {
        locationGroups = locationGroups.map { location in
            var updatedLocation = location
            updatedLocation.items = location.items.map { item in
                guard item.id == typeId else { return item }
                var updatedItem = item
                updatedItem.unitPrice = price
                return updatedItem
            }
            return updatedLocation
        }
    }

    private func resolveLocation(id: Int, type: String) async -> (name: String, systemName: String?, securityStatus: Double?) {
        switch type {
        case "station":
            guard let info = try? await characterService.stationInfo(id: id) else {
                return ("Station \(id)", nil, nil)
            }
            let system = try? await characterService.systemInfo(id: info.systemId)
            return (info.name, system?.name, system?.securityStatus)
        case "solar_system":
            let system = try? await characterService.systemInfo(id: id)
            return (system?.name ?? "System \(id)", "In Space", system?.securityStatus)
        default:
            guard let info = try? await characterService.structureInfo(id: id) else {
                return ("Unknown Structure", nil, nil)
            }
            let system = try? await characterService.systemInfo(id: info.solarSystemId)
            return (info.name, system?.name, system?.securityStatus)
        }
    }
}

private func formatISK(_ value: Double) -> String {
    if value >= 1_000_000_000_000 { return String(format: "%.2f T ISK", value / 1_000_000_000_000) }
    if value >= 1_000_000_000 { return String(format: "%.2f B ISK", value / 1_000_000_000) }
    if value >= 1_000_000 { return String(format: "%.1f M ISK", value / 1_000_000) }
    if value >= 1_000 { return String(format: "%.0f K ISK", value / 1_000) }
    return String(format: "%.0f ISK", value)
}

// MARK: - Location label (always visible DisclosureGroup label)

private struct AssetLocationSection: View {
    let location: AssetLocation
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(location.items) { item in
                NavigationLink {
                    TypeDetailView(typeId: item.id, typeName: item.name)
                } label: {
                    AssetItemRow(item: item)
                }
                .listRowBackground(Color.eveCard.opacity(0.42))
            }
        } label: {
            LocationLabel(location: location)
        }
        .listRowBackground(Color.eveCard.opacity(0.62))
    }
}

private struct AssetItemRow: View {
    let item: AssetItem

    private var flagsText: String {
        item.flags.prefix(2).joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 12) {
            EVETypeIcon(typeId: item.id, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .lineLimit(1)
                Text("×\(item.quantity.formatted())")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let totalValue = item.totalValue {
                    Text(formatISK(totalValue))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.eveAmber)
                }

                HStack(spacing: 6) {
                    if item.hasBlueprintCopy {
                        Text("BPC")
                            .foregroundStyle(.blue)
                    } else if item.hasSingleton {
                        Text("Singleton")
                            .foregroundStyle(.tertiary)
                    }
                    if !flagsText.isEmpty {
                        Text(flagsText)
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption2)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct LocationLabel: View {
    let location: AssetLocation

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: locationIcon)
                .font(.caption)
                .foregroundStyle(.tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let security = location.securityStatus {
                        SecurityBadge(value: security)
                    }
                    Text(location.name)
                        .font(.footnote.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    if let sys = location.systemName {
                        Text(sys)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                    }
                    Text("\(location.items.count) types")
                        .foregroundStyle(.tertiary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(location.totalQuantity.formatted()) items")
                        .foregroundStyle(.tertiary)
                }
                .font(.caption2)

                if location.totalValue > 0 {
                    Text(formatISK(location.totalValue))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.eveAmber)
                }
            }
        }
        .padding(.vertical, 5)
    }

    private var locationIcon: String {
        switch location.locationType {
        case "station":      return "building.2"
        case "solar_system": return "scope"
        default:             return "hexagon"
        }
    }
}

private struct SecurityBadge: View {
    let value: Double

    var body: some View {
        Text(securityLabel(value))
            .font(.caption2.monospacedDigit().weight(.bold))
            .foregroundStyle(securityColor(value))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(securityColor(value).opacity(0.14), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(securityColor(value).opacity(0.34), lineWidth: 1)
            }
    }

    private func securityLabel(_ value: Double) -> String {
        let rounded = max(-1.0, min(1.0, (value * 10).rounded() / 10))
        return String(format: "%.1f", rounded)
    }

    private func securityColor(_ value: Double) -> Color {
        if value >= 0.9 { return .blue }
        if value >= 0.7 { return .eveGreen }
        if value >= 0.5 { return .yellow }
        if value >= 0.1 { return .orange }
        if value > 0 { return .eveRed }
        return .red
    }
}
