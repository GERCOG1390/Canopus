import SwiftUI
import Domain
import EVEStaticData

struct GroupListView: View {
    let category: ItemCategory
    @Environment(AppEnvironment.self) private var env
    @State private var groups: [ItemGroup] = []
    @State private var marketGroups: [MarketGroup] = []
    @State private var iconTypeIds: [Int: Int] = [:]
    @State private var marketGroupIconTypeIds: [Int: Int] = [:]
    @State private var error: Error?

    var body: some View {
        List {
            if category.id == 7 {
                ForEach(marketGroups) { marketGroup in
                    marketGroupRow(marketGroup)
                }
            } else {
                ForEach(groups) { group in
                    groupRow(group)
                }
            }
        }
        .eveTabBarClearance()
        .navigationTitle(category.name)
        .overlay {
            if groups.isEmpty && error == nil {
                ProgressView()
            }
        }
        .task { await load() }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error?.localizedDescription ?? "")
        }
    }

    @ViewBuilder
    private func groupRow(_ group: ItemGroup) -> some View {
        NavigationLink(value: group) {
            HStack(spacing: 12) {
                if let typeId = iconTypeIds[group.id] {
                    EVETypeIcon(typeId: typeId, size: 30)
                }
                Text(group.name)
            }
            .padding(.vertical, 1)
        }
    }

    @ViewBuilder
    private func marketGroupRow(_ marketGroup: MarketGroup) -> some View {
        NavigationLink(value: marketGroup) {
            HStack(spacing: 12) {
                marketGroupIcon(marketGroup, size: 30)
                Text(marketGroup.name)
            }
            .padding(.vertical, 1)
        }
    }

    private func load() async {
        guard let repo = env.repository else { return }
        do {
            if category.id == 7, let shipEquipment = try await repo.marketGroup(id: 9) {
                async let children = repo.marketGroups(parentId: shipEquipment.id)
                async let marketIcons = repo.representativeTypeIdsByMarketGroup()
                (marketGroups, marketGroupIconTypeIds) = try await (children, marketIcons)
            } else {
                async let grps = repo.groups(categoryId: category.id)
                async let icons = repo.representativeTypeIdsByGroup()
                (groups, iconTypeIds) = try await (grps, icons)
            }
        } catch {
            self.error = error
        }
    }

    @ViewBuilder
    private func marketGroupIcon(_ marketGroup: MarketGroup, size: CGFloat) -> some View {
        if let iconId = marketGroup.iconId {
            EVEIconImage(iconId: iconId, size: size)
        } else if let typeId = marketGroupIconTypeIds[marketGroup.id] {
            EVETypeIcon(typeId: typeId, size: size)
        } else {
            Image(systemName: "folder")
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        }
    }
}
