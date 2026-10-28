// The item database: categories, groups, market groups and types from the SDE, with search.

import Domain
import EVEStaticData
import SwiftUI

struct DatabasePage: View {
    @Environment(AppEnvironment.self) private var env
    @State private var query = ""

    var body: some View {
        browser
            .navigationTitle("Database")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Ship, module, skill, implant…")
            .navigationDestination(for: ItemCategory.self) { GroupListView(category: $0) }
            .navigationDestination(for: ItemGroup.self) { TypeListView(group: $0) }
            .navigationDestination(for: MarketGroup.self) { MarketGroupListView(marketGroup: $0) }
            .navigationDestination(for: ItemType.self) { TypeDetailView(typeId: $0.id, typeName: $0.name) }
    }

    @ViewBuilder
    private var browser: some View {
        switch env.loadState {
        case .idle, .loading:
            ProgressView("Loading the SDE database…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            EmptyState("Database unavailable", icon: "win_warning") { Text(error.localizedDescription) }
        case .ready:
            if query.isEmpty { CategoryListView() } else { SearchResultsView(query: query) }
        }
    }
}
