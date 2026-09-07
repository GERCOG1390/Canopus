import SwiftUI
import Domain
import EVEStaticData

struct SearchResultsView: View {
    let query: String
    @Environment(AppEnvironment.self) private var env
    @State private var results: [ItemType] = []
    @State private var isSearching = false
    @State private var error: Error?

    var body: some View {
        List(results) { type in
            NavigationLink(value: type) {
                HStack(spacing: 10) {
                    EVETypeIcon(typeId: type.id, size: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(type.name)
                }
            }
        }
        .overlay {
            if isSearching {
                ProgressView()
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .task(id: query) {
            await search(query: query)
        }
    }

    private func search(query: String) async {
        guard let repo = env.repository else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            try await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            results = try await repo.search(query)
        } catch is CancellationError {
            // new search cancelled this task — ignore
        } catch {
            self.error = error
        }
    }
}
