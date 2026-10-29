// Meta group badges (Tech I, Tech II, Faction…) used by item lists and the fitting screens.

import SwiftUI

// MARK: - Type Presentation

enum EVETypeMetaPresentation {
    static func title(for metaGroupId: Int?) -> String {
        switch metaGroupId {
        case 1: return "Tech I"
        case 2: return "Tech II"
        case 3: return "Storyline"
        case 4: return "Faction"
        case 5: return "Officer"
        case 6: return "Deadspace"
        case 14: return "Strategic Cruiser"
        case 15: return "Tech III"
        case 17: return "Structure Tech I"
        case 19: return "Structure Faction"
        case 52: return "Abyssal"
        case 53: return "Precursor"
        case 54: return "Mutaplasmid"
        case .some(let id): return "Meta Group \(id)"
        case .none: return "Standard"
        }
    }

    static func sectionTitle(for metaGroupId: Int?) -> String {
        switch metaGroupId {
        case 1, .none: return "Tech I / Standard"
        case 2: return "Tech II"
        case 3: return "Storyline"
        case 4: return "Faction"
        case 5: return "Officer"
        case 6: return "Deadspace"
        case 14, 15, 17, 19, 52, 53, 54: return title(for: metaGroupId)
        case .some: return "Other Variants"
        }
    }

    static func rank(for metaGroupId: Int?) -> Int {
        switch metaGroupId {
        case 1, .none: return 10
        case 2: return 20
        case 3: return 30
        case 4: return 40
        case 6: return 50
        case 5: return 60
        case 15: return 70
        case 14: return 71
        case 52: return 80
        case 53: return 81
        case 54: return 82
        case 17: return 90
        case 19: return 91
        case .some(let id): return 1000 + id
        }
    }

    static func metaLevel(for metaGroupId: Int?) -> Int {
        switch metaGroupId {
        case 2: return 5
        case 3: return 6
        case 4: return 8
        case 6: return 10
        case 5: return 12
        case 15: return 5
        default: return metaGroupId ?? 0
        }
    }

    static func color(for metaGroupId: Int?) -> Color {
        switch metaGroupId {
        case 2, 15: return .blue
        case 3: return .purple
        case 4, 19: return .orange
        case 5: return .red
        case 6: return .mint
        case 52, 53, 54: return .indigo
        default: return .secondary
        }
    }
}

struct TypeMetaBadge: View {
    let metaGroupId: Int?

    var body: some View {
        Text(EVETypeMetaPresentation.title(for: metaGroupId))
            .font(.ui(11, .semibold, relativeTo: .caption2))
            .textCase(.uppercase)
            .foregroundStyle(EVETypeMetaPresentation.color(for: metaGroupId))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(EVETypeMetaPresentation.color(for: metaGroupId).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .lineLimit(1)
    }
}

