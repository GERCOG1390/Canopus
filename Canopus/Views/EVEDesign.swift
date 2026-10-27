import SwiftUI

enum EVELayout {
    // The system tab bar now insets the content itself; kept small for existing call sites.
    static let tabBarClearance: CGFloat = 0
    static let scrollBottomClearance: CGFloat = 24
}

// MARK: - Color palette

// The old names now point at the desktop tokens (Theme/CanopusTheme.swift), so every screen gets the
// desktop palette; new code uses `C` directly.
extension Color {
    static var eveBackground: Color { C.bg }
    static var eveCard: Color { C.panel }
    static var eveAmber: Color { C.accent }
    static var eveCyan: Color { C.accentText }
    static var eveGreen: Color { C.good }
    static var eveRed: Color { C.bad }
    static var eveText: Color { C.text }
}

// MARK: - Cut-corner shape

struct CutCorner: Shape {
    var size: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to:    .init(x: rect.minX,        y: rect.minY))
        p.addLine(to: .init(x: rect.maxX - size, y: rect.minY))
        p.addLine(to: .init(x: rect.maxX,        y: rect.minY + size))
        p.addLine(to: .init(x: rect.maxX,        y: rect.maxY))
        p.addLine(to: .init(x: rect.minX + size, y: rect.maxY))
        p.addLine(to: .init(x: rect.minX,        y: rect.maxY - size))
        p.closeSubpath()
        return p
    }
}

// MARK: - View extensions

extension View {
    /// The desktop has no scanlines; kept as a no-op for existing call sites.
    func eveScanlinesOverlay() -> some View { self }

    func eveTabBarClearance(_ height: CGFloat = EVELayout.tabBarClearance) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: height)
                .allowsHitTesting(false)
        }
    }

    func eveCard(cut: CGFloat = 10, border: Color = C.border) -> some View {
        self
            .background(C.panel, in: EVECut(cut: cut))
            .overlay(EVECut(cut: cut).strokeBorder(border, lineWidth: 1))
    }
}

// MARK: - HUD label modifier

struct HUDLabelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.ui(11, .medium, relativeTo: .caption))
            .tracking(1.8)
            .textCase(.uppercase)
            .foregroundStyle(C.muted)
    }
}

extension View {
    func hudLabel() -> some View { modifier(HUDLabelModifier()) }
}

// MARK: - Shared section headers

struct EVESectionHeader<Trailing: View>: View {
    let title: String
    var accentColor: Color = Color.eveText.opacity(0.38)
    var backgroundColor: Color = Color.eveCard
    @ViewBuilder var trailing: () -> Trailing

    init(
        _ title: String,
        accentColor: Color = Color.eveText.opacity(0.38),
        backgroundColor: Color = Color.eveCard,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.accentColor = accentColor
        self.backgroundColor = backgroundColor
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title).hudLabel()
                .foregroundStyle(accentColor)
            Spacer(minLength: 10)
            trailing()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
    }
}

extension EVESectionHeader where Trailing == EmptyView {
    init(
        _ title: String,
        accentColor: Color = Color.eveText.opacity(0.38),
        backgroundColor: Color = Color.eveCard
    ) {
        self.init(title, accentColor: accentColor, backgroundColor: backgroundColor) {
            EmptyView()
        }
    }
}

struct EVEDisclosureSectionHeader: View {
    let title: String
    let count: Int
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.eveAmber)
                    .frame(width: 12)
                Text(title)
                    .font(.ui(11, .medium, relativeTo: .caption))
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundStyle(C.muted)
                    .lineLimit(2)
                Spacer(minLength: 10)
                Text("\(count)")
                    .font(.ui(12))
                    .monospacedDigit()
                    .foregroundStyle(C.faint)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.eveCard)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct EVESeparator: View {
    enum Kind {
        case subtle
        case section
    }

    var kind: Kind = .subtle

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 1)
    }

    private var color: Color {
        switch kind {
        case .subtle:
            return C.border.opacity(0.6)
        case .section:
            return C.border
        }
    }
}

struct EVEVerticalSeparator: View {
    var body: some View {
        Rectangle()
            .fill(C.border.opacity(0.6))
            .frame(width: 1)
    }
}

struct EVEActionIndicator: View {
    enum Kind {
        case navigate
        case add
    }

    let kind: Kind

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 18, height: 18)
    }

    private var systemName: String {
        switch kind {
        case .navigate: return "chevron.right"
        case .add: return "plus"
        }
    }

    private var color: Color {
        switch kind {
        case .navigate: return C.faint
        case .add: return Color.eveAmber
        }
    }

    private var size: CGFloat {
        switch kind {
        case .navigate: return 10
        case .add: return 12
        }
    }
}

// MARK: - Wallet journal ref-type labels

func eveRefLabel(_ refType: String) -> String {
    switch refType {
    case "player_trading":                  return "Trade"
    case "market_escrow":                   return "Market Escrow"
    case "transaction_tax":                 return "Transaction Tax"
    case "brokers_fee":                     return "Brokers Fee"
    case "bounty_prizes":                   return "Bounty"
    case "contract_price":                  return "Contract"
    case "contract_reward":                 return "Contract Reward"
    case "contract_collateral":             return "Contract Collateral"
    case "contract_deposit":                return "Contract Deposit"
    case "contract_deposit_refund":         return "Contract Refund"
    case "agent_mission_reward":            return "Mission Reward"
    case "agent_mission_time_bonus_reward": return "Mission Bonus"
    case "character_donation":              return "Donation"
    case "corporation_account_withdrawal":  return "Corp Withdrawal"
    case "manufacturing":                   return "Manufacturing"
    case "reprocessing_tax":                return "Reprocessing Tax"
    case "jump_clone_activation_fee":       return "Clone Jump Fee"
    case "planetary_export_tax":            return "PI Export Tax"
    case "planetary_import_tax":            return "PI Import Tax"
    case "skill_purchase":                  return "Skill Purchase"
    case "insurance":                       return "Insurance"
    case "inheritance":                     return "Inheritance"
    default:
        return refType.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - Shared string utilities

extension String {
    var strippedEVEHTML: String {
        var s = self
        s = s.replacingOccurrences(of: "<br>",  with: "\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&lt;",   with: "<")
        s = s.replacingOccurrences(of: "&gt;",   with: ">")
        s = s.replacingOccurrences(of: "&amp;",  with: "&")
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
