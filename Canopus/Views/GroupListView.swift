import SwiftUI
import Domain
import EVEStaticData

struct GroupListView: View {
    let category: ItemCategory
    @Environment(AppEnvironment.self) private var env
    @State private var groups: [ItemGroup] = []
    @State private var iconTypeIds: [Int: Int] = [:]
    @State private var error: Error?

    var body: some View {
        List(groups) { group in
            NavigationLink(value: group) {
                HStack(spacing: 12) {
                    if let typeId = iconTypeIds[group.id] {
                        EVETypeIcon(typeId: typeId, size: 30)
                    } else {
                        Image(systemName: "folder")
                            .frame(width: 30, height: 30)
                            .foregroundStyle(.tint)
                    }
                    Text(group.name)
                }
                .padding(.vertical, 1)
            }
        }
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

    private func load() async {
        guard let repo = env.repository else { return }
        do {
            async let grps = repo.groups(categoryId: category.id)
            async let icons = repo.representativeTypeIdsByGroup()
            (groups, iconTypeIds) = try await (grps, icons)
        } catch {
            self.error = error
        }
    }
}
