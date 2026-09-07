import SwiftUI
import Domain
import EVEStaticData

struct CategoryListView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var categories: [ItemCategory] = []
    @State private var iconTypeIds: [Int: Int] = [:]
    @State private var error: Error?

    var body: some View {
        List(categories) { category in
            NavigationLink(value: category) {
                HStack(spacing: 12) {
                    if let typeId = iconTypeIds[category.id] {
                        EVETypeIcon(typeId: typeId, size: 32)
                    } else {
                        Image(systemName: "folder")
                            .frame(width: 32, height: 32)
                            .foregroundStyle(.tint)
                    }
                    Text(category.name)
                }
                .padding(.vertical, 2)
            }
        }
        .overlay {
            if categories.isEmpty && error == nil {
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
            async let cats = repo.categories()
            async let icons = repo.representativeTypeIdsByCategory()
            (categories, iconTypeIds) = try await (cats, icons)
        } catch {
            self.error = error
        }
    }
}
