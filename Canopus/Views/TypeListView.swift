import SwiftUI
import Domain
import EVEStaticData

struct TypeListView: View {
    let group: ItemGroup
    @Environment(AppEnvironment.self) private var env
    @State private var types: [ItemType] = []
    @State private var error: Error?

    var body: some View {
        List {
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
        .navigationTitle(group.name)
        .overlay {
            if types.isEmpty && error == nil {
                ProgressView()
            } else if types.isEmpty {
                ContentUnavailableView("No types in this group", systemImage: "tray")
            }
        }
        .task {
            await load()
        }
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
        do {
            types = try await repo.types(groupId: group.id)
        } catch {
            self.error = error
        }
    }
}
