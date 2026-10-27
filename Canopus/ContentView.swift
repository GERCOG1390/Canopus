import SwiftUI

// MARK: - Tab definition

// The old five tabs; the character overview still links through them (RootShell maps them to pages).

enum EVETab: Int, CaseIterable, Identifiable {
    case home, skills, assets, wallet, items
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .home:   return "HOME"
        case .skills: return "SKILLS"
        case .assets: return "ASSETS"
        case .wallet: return "WALLET"
        case .items:  return "ITEMS"
        }
    }

    var icon: String {
        switch self {
        case .home:   return "house.fill"
        case .skills: return "brain.head.profile"
        case .assets: return "shippingbox.fill"
        case .wallet: return "creditcard.fill"
        case .items:  return "cube.fill"
        }
    }
}
