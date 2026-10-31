// The reference: any item's Show Info, found by name or in the market tree. The desktop opens it from
// Ctrl+K and the market tree; on the phone it is a page of its own.

import Domain
import EVEStaticData
import SwiftUI

struct DatabasePage: View {
    @Environment(AppEnvironment.self) private var env
    @State private var picked: ItemType?
    @State private var debugType: Int?
    @State private var treeSelected: Int?

    var body: some View {
        browser
            .background(C.bg)
            .navigationTitle("Database")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $picked) { TypeDetailView(typeId: $0.id, typeName: $0.name) }
            .navigationDestination(item: $debugType) { TypeDetailView(typeId: $0, typeName: "") }
            #if DEBUG
            // Debug builds: `-openType 24698 -typeTab traits` opens an item's info (screenshots).
            .task {
                let id = UserDefaults.standard.integer(forKey: "openType")
                if id > 0, debugType == nil { try? await Task.sleep(for: .milliseconds(400)); debugType = id }
                // `-treeType 2048` opens the tree down to an item.
                let tree = UserDefaults.standard.integer(forKey: "treeType")
                if tree > 0 { treeSelected = tree }
            }
            #endif
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
            ScrollView {
                ItemLookup(onPick: { treeSelected = $0.id; picked = $0 }, selected: treeSelected, infoButton: false,
                           hint: "Tap an item for its full info: description, attributes, requirements, variations, industry and prices.")
                    .padding(16)
            }
        }
    }
}
