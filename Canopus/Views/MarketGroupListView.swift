import SwiftUI
import Domain
import EVEStaticData

struct MarketGroupListView: View {
    let marketGroup: MarketGroup

    @Environment(AppEnvironment.self) private var env
    @State private var children: [MarketGroup] = []
    @State private var types: [ItemType] = []
    @State private var iconTypeIds: [Int: Int] = [:]
    @State private var error: Error?
    @State private var isLoading = true

    var body: some View {
        List {
            if !children.isEmpty {
                Section {
                    ForEach(children) { child in
                        NavigationLink(value: child) {
                            HStack(spacing: 12) {
                                marketGroupIcon(child, size: 30)
                                Text(child.name)
                            }
                            .padding(.vertical, 1)
                        }
                    }
                }
            }

            ForEach(groupedTypes) { section in
                Section(section.title) {
                    ForEach(section.types) { type in
                        NavigationLink(value: type) {
                            HStack(spacing: 10) {
                                EVETypeIcon(typeId: type.id, size: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(type.name)
                                        .lineLimit(2)
                                    HStack(spacing: 8) {
                                        TypeMetaBadge(metaGroupId: type.metaGroupId)
                                        if let vol = type.volume {
                                            Text("\(vol, format: .number.precision(.fractionLength(2))) m³")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .eveTabBarClearance()
        .navigationTitle(marketGroup.name)
        .overlay {
            if isLoading {
                ProgressView()
            } else if children.isEmpty && types.isEmpty {
                ContentUnavailableView("No items in this group", systemImage: "tray")
            }
        }
        .task { await load() }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error?.localizedDescription ?? "")
        }
    }

    private struct TypeSection: Identifiable {
        let id: Int
        let title: String
        let types: [ItemType]
    }

    private var groupedTypes: [TypeSection] {
        let grouped = Dictionary(grouping: types) { type in
            EVETypeMetaPresentation.rank(for: type.metaGroupId)
        }
        return grouped.keys.sorted().compactMap { rank in
            guard let sectionTypes = grouped[rank], !sectionTypes.isEmpty else { return nil }
            let sortedTypes = sectionTypes.sorted {
                if EVETypeMetaPresentation.metaLevel(for: $0.metaGroupId) != EVETypeMetaPresentation.metaLevel(for: $1.metaGroupId) {
                    return EVETypeMetaPresentation.metaLevel(for: $0.metaGroupId) < EVETypeMetaPresentation.metaLevel(for: $1.metaGroupId)
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return TypeSection(
                id: rank,
                title: EVETypeMetaPresentation.sectionTitle(for: sortedTypes.first?.metaGroupId),
                types: sortedTypes
            )
        }
    }

    private func load() async {
        guard let repo = env.repository else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            async let childGroups = repo.marketGroups(parentId: marketGroup.id)
            async let directTypes = repo.types(marketGroupId: marketGroup.id)
            async let icons = repo.representativeTypeIdsByMarketGroup()
            (children, types, iconTypeIds) = try await (childGroups, directTypes, icons)
        } catch {
            self.error = error
        }
    }

    @ViewBuilder
    private func marketGroupIcon(_ group: MarketGroup, size: CGFloat) -> some View {
        if let iconId = group.iconId {
            EVEIconImage(iconId: iconId, size: size)
        } else if let typeId = iconTypeIds[group.id] {
            EVETypeIcon(typeId: typeId, size: size)
        } else {
            Image(systemName: "folder")
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        }
    }
}
