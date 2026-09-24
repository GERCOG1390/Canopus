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
                    categoryIcon(for: category)
                    Text(category.name)
                }
                .padding(.vertical, 2)
            }
        }
        .eveTabBarClearance()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    env.showSDEUpdateSheet = true
                } label: {
                    Image(systemName: "externaldrive.badge.arrow.down")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.eveCyan)
                }
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

    @ViewBuilder
    private func categoryIcon(for category: ItemCategory) -> some View {
        switch CategoryIconSource.source(for: category.id, representativeTypeId: iconTypeIds[category.id]) {
        case .type(let typeId):
            EVETypeIcon(typeId: typeId, size: 32)
        case .icon(let iconId):
            EVEIconImage(iconId: iconId, size: 32)
        }
    }
}

private enum CategoryIconSource {
    case type(Int)
    case icon(Int)

    static func source(for categoryId: Int, representativeTypeId: Int?) -> CategoryIconSource {
        if let override = categoryOverrides[categoryId] {
            return override
        }

        if let representativeTypeId {
            return .type(representativeTypeId)
        }

        return .icon(2340)
    }

    private static let categoryOverrides: [Int: CategoryIconSource] = [
        5: .type(40520),       // Accessories: Large Skill Injector
        34: .type(30187),      // Ancient Relics: Intact Thruster Sections
        30: .icon(10256),      // Apparel
        25: .type(1230),       // Asteroid: Veldspar
        9: .icon(2703),        // Blueprints
        2: .type(25268),       // Celestial: harvestable cloud instead of corpse fallback
        8: .icon(1299),        // Ammunition & Charges
        2143: .icon(2881),     // Colony Resources
        17: .icon(2340),       // Trade Goods / Commodity
        35: .type(34201),      // Decryptors
        22: .type(33474),      // Deployable: Mobile Depot
        18: .icon(1084),       // Drones
        2100: .icon(21481),    // Expert Systems / Pilot services
        87: .icon(1084),       // Fighters
        20: .icon(2563),       // Implants & Boosters
        39: .icon(1436),       // Infrastructure Upgrades
        4: .type(34),          // Material: Tritanium
        7: .icon(1432),        // Ship Equipment / Module
        46: .type(3962),       // Orbitals: Customs Office Gantry
        2118: .icon(26056),    // Personalization
        43: .icon(2881),       // Planetary Commodities
        41: .icon(2881),       // Planetary Industry
        42: .icon(2881),       // Planetary Resources
        24: .icon(21783),      // Reaction Formulas
        91: .icon(21420),      // Ship SKINs
        6: .icon(1443),        // Ships
        16: .icon(33),         // Skills
        40: .type(32458),      // Sovereignty Structures: Sovereignty Hub
        63: .type(28840),      // Special Edition Assets: Magic Crystal Ball
        23: .type(12235),      // Starbase: Amarr Control Tower
        65: .type(35825),      // Structures: Raitaru
        66: .icon(21561),      // Structure Equipment
        32: .icon(2887)        // Subsystems / Modifications
    ]
}
