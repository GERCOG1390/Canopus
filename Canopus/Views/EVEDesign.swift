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
            Text(LocalizedStringKey(title)).hudLabel()
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
                    .font(.ui(11, .bold))
                    .foregroundStyle(Color.eveAmber)
                    .frame(width: 12)
                Text(LocalizedStringKey(title))
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
    case "player_trading":                  return String(localized: "Trade")
    case "market_transaction":              return String(localized: "Market Transaction")
    case "daily_goal_payouts":              return String(localized: "Daily Goal Payouts")
    case "corporation_account_deposit":     return String(localized: "Corp Deposit")
    case "industry_job_tax":                return String(localized: "Industry Tax")
    case "structure_gate_jump":             return String(localized: "Jump Bridge Fee")
    case "market_escrow":                   return String(localized: "Market Escrow")
    case "transaction_tax":                 return String(localized: "Transaction Tax")
    case "brokers_fee":                     return String(localized: "Brokers Fee")
    case "bounty_prizes":                   return String(localized: "Bounty")
    case "contract_price":                  return String(localized: "Contract")
    case "contract_reward":                 return String(localized: "Contract Reward")
    case "contract_collateral":             return String(localized: "Contract Collateral")
    case "contract_deposit":                return String(localized: "Contract Deposit")
    case "contract_deposit_refund":         return String(localized: "Contract Refund")
    case "agent_mission_reward":            return String(localized: "Mission Reward")
    case "agent_mission_time_bonus_reward": return String(localized: "Mission Bonus")
    case "character_donation":              return String(localized: "Donation")
    case "corporation_account_withdrawal":  return String(localized: "Corp Withdrawal")
    case "manufacturing":                   return String(localized: "Manufacturing")
    case "reprocessing_tax":                return String(localized: "Reprocessing Tax")
    case "jump_clone_activation_fee":       return String(localized: "Clone Jump Fee")
    case "planetary_export_tax":            return String(localized: "PI Export Tax")
    case "planetary_import_tax":            return String(localized: "PI Import Tax")
    case "skill_purchase":                  return String(localized: "Skill Purchase")
    case "insurance":                       return String(localized: "Insurance")
    case "inheritance":                     return String(localized: "Inheritance")
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
