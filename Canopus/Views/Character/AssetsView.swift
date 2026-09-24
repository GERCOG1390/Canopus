import SwiftUI
import EVEAuth
import EVEStaticData
import Domain

private struct AssetItem: Identifiable {
    let id: Int  // typeId — unique per location after aggregation
    var name: String
    var quantity: Int
    var flags: [String]
    var hasSingleton: Bool
    var hasBlueprintCopy: Bool
}

private struct AssetLocation: Identifiable {
    let id: Int
    var name: String
    var systemName: String?
    var locationType: String
    var items: [AssetItem]
    var totalQuantity: Int { items.reduce(0) { $0 + $1.quantity } }
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

    private var filteredGroups: [AssetLocation] {
        guard !searchText.isEmpty else { return locationGroups }
        return locationGroups.compactMap { loc in
            let filtered = loc.items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            guard !filtered.isEmpty else { return nil }
            return AssetLocation(id: loc.id, name: loc.name, systemName: loc.systemName,
                                 locationType: loc.locationType, items: filtered)
        }
    }

    private var totalTypes: Int { locationGroups.reduce(0) { $0 + $1.items.count } }
    private var totalItems: Int { locationGroups.reduce(0) { $0 + $1.totalQuantity } }

    var body: some View {
        List {
            ForEach(filteredGroups) { location in
                DisclosureGroup(isExpanded: expandedBinding(for: location.id)) {
                    ForEach(location.items) { item in
                        HStack(spacing: 12) {
                            EVETypeIcon(typeId: item.id, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.body)
                                    .lineLimit(1)
                                Text("×\(item.quantity.formatted())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 6) {
                                    if item.hasBlueprintCopy {
                                        Text("BPC")
                                            .foregroundStyle(.blue)
                                    } else if item.hasSingleton {
                                        Text("Singleton")
                                            .foregroundStyle(.tertiary)
                                    }
                                    Text(item.flags.prefix(2).joined(separator: ", "))
                                        .foregroundStyle(.tertiary)
                                }
                                .font(.caption2)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                } label: {
                    LocationLabel(location: location)
                }
            }
        }
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
                Text("\(locationGroups.count) locations · \(totalTypes) types · \(totalItems) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.bar)
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

            loadingPhase = "Loading locations…"
            var result: [AssetLocation] = []
            for (locId, assets) in locationAssets {
                let locType = locationTypes[locId] ?? "other"
                let (locName, sysName) = await resolveLocation(id: locId, type: locType)

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
                            flags: Array(flagsByType[$0.key] ?? []).sorted(),
                            hasSingleton: singletonTypes.contains($0.key),
                            hasBlueprintCopy: blueprintCopyTypes.contains($0.key)
                        )
                    }
                    .sorted { $0.name < $1.name }

                result.append(AssetLocation(id: locId, name: locName, systemName: sysName,
                                            locationType: locType, items: items))
            }

            locationGroups = result.sorted { $0.name < $1.name }
            expandedIds = []
        } catch {
            self.error = error
        }
    }

    private func resolveLocation(id: Int, type: String) async -> (String, String?) {
        switch type {
        case "station":
            guard let info = try? await characterService.stationInfo(id: id) else {
                return ("Station \(id)", nil)
            }
            let sysName = (try? await characterService.systemInfo(id: info.systemId))?.name
            return (info.name, sysName)
        case "solar_system":
            let name = (try? await characterService.systemInfo(id: id))?.name ?? "System \(id)"
            return (name, "In Space")
        default:
            guard let info = try? await characterService.structureInfo(id: id) else {
                return ("Unknown Structure", nil)
            }
            let sysName = (try? await characterService.systemInfo(id: info.solarSystemId))?.name
            return (info.name, sysName)
        }
    }
}

// MARK: - Location label (always visible DisclosureGroup label)

private struct LocationLabel: View {
    let location: AssetLocation

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: locationIcon)
                    .font(.caption2)
                    .foregroundStyle(.tint)
                Text(location.name)
                    .font(.footnote.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            HStack(spacing: 0) {
                if let sys = location.systemName {
                    Text(sys)
                        .foregroundStyle(.secondary)
                    Text(" · ")
                        .foregroundStyle(.tertiary)
                }
                Text("\(location.items.count) types, \(location.totalQuantity.formatted()) items")
                    .foregroundStyle(.tertiary)
            }
            .font(.caption2)
            .padding(.leading, 18)
        }
        .padding(.vertical, 4)
    }

    private var locationIcon: String {
        switch location.locationType {
        case "station":      return "building.2"
        case "solar_system": return "scope"
        default:             return "hexagon"
        }
    }
}
