import SwiftUI

// MARK: - Color palette

extension Color {
    static let eveBackground = Color(red: 0.024, green: 0.031, blue: 0.039)  // #06080a
    static let eveCard       = Color(red: 0.047, green: 0.063, blue: 0.078)  // #0c1014
    static let eveAmber      = Color(red: 1.000, green: 0.690, blue: 0.125)  // #ffb020
    static let eveCyan       = Color(red: 0.208, green: 0.839, blue: 0.902)  // #35d6e6
    static let eveGreen      = Color(red: 0.490, green: 0.863, blue: 0.490)  // #7ddc7d
    static let eveRed        = Color(red: 1.000, green: 0.416, blue: 0.302)  // #ff6a4d
    static let eveText       = Color(red: 0.910, green: 0.918, blue: 0.929)  // #e8eaed
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

// MARK: - Scanlines overlay

private struct ScanlinesModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(alignment: .topLeading) {
            Canvas { ctx, size in
                var y: CGFloat = 0
                while y < size.height {
                    ctx.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                        with: .color(.white.opacity(0.045))
                    )
                    y += 3
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
    }
}

// MARK: - View extensions

extension View {
    func eveScanlinesOverlay() -> some View { modifier(ScanlinesModifier()) }

    func eveCard(cut: CGFloat = 10, border: Color = Color.white.opacity(0.08)) -> some View {
        self
            .background(Color.eveCard, in: CutCorner(size: cut))
            .overlay(CutCorner(size: cut).stroke(border, lineWidth: 1))
    }
}

// MARK: - HUD label modifier

struct HUDLabelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(2.2)
            .textCase(.uppercase)
            .foregroundStyle(Color.eveText.opacity(0.38))
    }
}

extension View {
    func hudLabel() -> some View { modifier(HUDLabelModifier()) }
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
