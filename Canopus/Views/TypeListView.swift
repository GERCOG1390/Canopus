import SwiftUI
import Domain
import EVEStaticData

struct TypeListView: View {
    let group: ItemGroup
    @Environment(AppEnvironment.self) private var env
    @State private var types: [ItemType] = []
    @State private var error: Error?

    var body: some View {
        List(types) { type in
            NavigationLink(value: type) {
                HStack(spacing: 10) {
                    EVETypeIcon(typeId: type.id, size: 36)
                        .cornerRadius(4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(type.name)
                        if let vol = type.volume {
                            Text("\(vol, format: .number.precision(.fractionLength(2))) m³")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
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

    private func load() async {
        guard let repo = env.repository else { return }
        do {
            types = try await repo.types(groupId: group.id)
        } catch {
            self.error = error
        }
    }
}
