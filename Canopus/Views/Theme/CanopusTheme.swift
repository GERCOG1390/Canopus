// Canopus design system, taken from the desktop app (canopus-desktop src/renderer/src/styles.css):
// the same colors, fonts (IBM Plex Sans, Exo 2, IBM Plex Mono), EVE-window cards with the top-left and
// bottom-right corners cut, stat tiles, "LABEL ────" section headers, tabs and buttons.

import CoreText
import SwiftUI

// MARK: - Colors

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Desktop tokens (`:root` in styles.css).
enum C {
    static let bg = Color(hex: 0x131416)
    static let nav = Color(hex: 0x16171A)
    static let panel = Color(hex: 0x1A1B1E)
    static let card = Color(hex: 0x1F2024)
    static let panel2 = Color(hex: 0x25272B)
    static let hover = Color(hex: 0x2B2D32)
    static let border = Color(hex: 0x2D2F34)
    static let lineStrong = Color(hex: 0x3C3F45)
    static let text = Color(hex: 0xE6E6E2)
    static let text2 = Color(hex: 0xCBCBC6)
    static let muted = Color(hex: 0x9D9E99)
    static let faint = Color(hex: 0x74767B)
    static let star = Color(hex: 0xFFD98A)
    static let good = Color(hex: 0x4FC48A)
    static let bad = Color(hex: 0xF07A66)
    static let badFill = Color(hex: 0xE5533D)
    static let warn = Color(hex: 0xF0B44F)
    static let dmgEM = Color(hex: 0x4EA6E8)
    static let dmgThermal = Color(hex: 0xE5533D)
    static let dmgKinetic = Color(hex: 0xA9B6C4)
    static let dmgExplosive = Color(hex: 0xE8A33C)

    static var accent: Color { CanopusAccent.current.color }
    static var onAccent: Color { CanopusAccent.current.onColor }
    /// Accent for text and links: lighter than the fill accent.
    static var accentText: Color { accent.mix(with: .white, by: 0.35) }
    static var accentSoft: Color { accent.opacity(0.14) }
    static var accentLine: Color { accent.opacity(0.45) }

    /// Security status colors as the game shows them (0.5 and up high-sec).
    static func sec(_ value: Double) -> Color {
        let colors: [UInt32] = [0x8F2F69, 0xB52D2D, 0xBE3A1E, 0xE65C1E, 0xE6881E, 0xF0CE37, 0x8FD13B, 0x5BD13B, 0x3BD17F, 0x3BA5D1, 0x2C75E1]
        let r = roundSec(value)
        if r <= 0 { return Color(hex: colors[0]) }
        return Color(hex: colors[min(10, Int((r * 10).rounded()))])
    }

    /// Security rounded as the game shows it (0.45 is 0.5; anything above 0 is at least 0.1).
    static func roundSec(_ value: Double) -> Double {
        if value > 0 && value < 0.05 { return 0.1 }
        return (value * 10).rounded() / 10
    }
}

/// Accent themes, as in the desktop settings: the base stays Canopus, only the accent changes.
enum CanopusAccent: String, CaseIterable, Identifiable {
    case canopus, photon, amarr, caldari, gallente, minmatar

    var id: String { rawValue }
    static let storageKey = "accentTheme"

    static var current: CanopusAccent {
        CanopusAccent(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .canopus
    }

    var color: Color {
        switch self {
        case .canopus: Color(hex: 0x3DBF9C)
        case .photon: Color(hex: 0x4CC3F0)
        case .amarr: Color(hex: 0xD9A84E)
        case .caldari: Color(hex: 0x5BA8E8)
        case .gallente: Color(hex: 0x7CC25F)
        case .minmatar: Color(hex: 0xE0703F)
        }
    }

    var onColor: Color {
        switch self {
        case .canopus: Color(hex: 0x04140F)
        case .photon: Color(hex: 0x06121A)
        case .amarr: Color(hex: 0x1A1204)
        case .caldari: Color(hex: 0x041220)
        case .gallente: Color(hex: 0x0B1705)
        case .minmatar: Color(hex: 0x1D0A03)
        }
    }

    var title: String {
        switch self {
        case .canopus: "Canopus"
        case .photon: "Photon"
        case .amarr: "Amarr"
        case .caldari: "Caldari"
        case .gallente: "Gallente"
        case .minmatar: "Minmatar"
        }
    }
}

// MARK: - Fonts

enum CanopusFonts {
    /// Registers the bundled fonts once (no Info.plist entry needed).
    static func register() {
        for name in ["IBMPlexSans-Variable", "Exo2-Variable", "IBMPlexMono-Regular", "IBMPlexMono-Medium"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    /// Interface text: IBM Plex Sans.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("IBM Plex Sans", size: size, relativeTo: style).weight(weight)
    }

    /// Headings and big numbers: Exo 2.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("Exo 2", size: size, relativeTo: style).weight(weight)
    }

    /// Code, EFT and fixed-width numbers: IBM Plex Mono.
    static func mono(_ size: CGFloat, medium: Bool = false) -> Font {
        .custom(medium ? "IBMPlexMono-Medium" : "IBM Plex Mono", size: size, relativeTo: .body)
    }
}

// MARK: - EVE window cut

/// The desktop card shape: top-left and bottom-right corners cut, like the game's windows.
struct EVECut: InsettableShape {
    var cut: CGFloat = 10
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let c = max(0, cut - inset)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> EVECut {
        var s = self
        s.inset += amount
        return s
    }
}

extension View {
    /// A desktop card surface: panel background, 1 px border, cut corners. `nested` for a card inside a card.
    func canopusSurface(nested: Bool = false, padding: CGFloat? = 14) -> some View {
        self
            .padding(padding.map { EdgeInsets(top: $0, leading: $0 + 2, bottom: $0, trailing: $0 + 2) } ?? EdgeInsets())
            .background(nested ? C.card : C.panel, in: EVECut())
            .overlay(EVECut().strokeBorder(C.border, lineWidth: 1))
    }
}

// MARK: - Section header ("LABEL ────")

/// The desktop `h3`: small uppercase muted label followed by a rule, like the in-game window headers.
struct SectionLabel<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(LocalizedStringKey(title))
                .font(.ui(11, .medium, relativeTo: .caption))
                .tracking(1.8)
                .textCase(.uppercase)
                .foregroundStyle(C.muted)
                .lineLimit(1)
            Rectangle().fill(C.border).frame(height: 1)
            trailing()
        }
    }
}

extension SectionLabel where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

// MARK: - Card

/// A desktop card: optional section header, content, cut corners.
struct Card<Content: View, Actions: View>: View {
    var title: String?
    var nested = false
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                SectionLabel(title, trailing: actions)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .canopusSurface(nested: nested)
    }
}

extension Card where Actions == EmptyView {
    init(_ title: String? = nil, nested: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, nested: nested, actions: { EmptyView() }, content: content)
    }
}

// MARK: - Stat tile

/// The desktop `.stat`: uppercase label, big Exo 2 number, optional line under it.
struct StatTile: View {
    let label: String
    let value: String
    var sub: String?
    var valueColor: Color = C.text

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(label))
                .font(.ui(11, .medium, relativeTo: .caption))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(C.muted)
                .lineLimit(1)
            Text(value)
                .font(.display(22))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let sub {
                Text(LocalizedStringKey(sub))
                    .font(.ui(12))
                    .foregroundStyle(C.muted)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .canopusSurface(padding: 12)
    }
}

// MARK: - Tabs

/// The desktop `.tabs`: a pill row on the nav color, the active tab lifted with an accent underline.
struct CanopusTabs<ID: Hashable>: View {
    let tabs: [(id: ID, label: String)]
    @Binding var selection: ID

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(tabs, id: \.id) { tab in
                    let active = tab.id == selection
                    Button {
                        selection = tab.id
                    } label: {
                        Text(LocalizedStringKey(tab.label))
                            .font(.ui(14))
                            .foregroundStyle(active ? C.text : C.muted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(active ? C.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(alignment: .bottom) {
                                if active {
                                    Rectangle().fill(C.accent).frame(height: 2).padding(.horizontal, 4)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(C.nav, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(C.border, lineWidth: 1))
        }
    }
}

// MARK: - Buttons

/// Desktop buttons: filled accent (primary), card-colored with a border (ghost), small variants.
struct CanopusButtonStyle: ButtonStyle {
    enum Kind { case primary, ghost, danger }
    var kind: Kind = .primary
    var small = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.ui(small ? 12 : 14, kind == .primary ? .medium : .regular))
            .foregroundStyle(kind == .primary ? C.onAccent : kind == .danger ? C.bad : C.text)
            .padding(.horizontal, small ? 8 : 14)
            .padding(.vertical, small ? 3 : 8)
            .background(background(pressed), in: RoundedRectangle(cornerRadius: small ? 6 : 8))
            .overlay(RoundedRectangle(cornerRadius: small ? 6 : 8).strokeBorder(kind == .primary ? .clear : C.lineStrong, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.45)
    }

    private func background(_ pressed: Bool) -> Color {
        switch kind {
        case .primary: pressed ? C.accent.mix(with: .white, by: 0.15) : C.accent
        case .ghost, .danger: pressed ? C.panel2 : C.card
        }
    }
}

extension ButtonStyle where Self == CanopusButtonStyle {
    static var canopus: CanopusButtonStyle { CanopusButtonStyle() }
    static var canopusGhost: CanopusButtonStyle { CanopusButtonStyle(kind: .ghost) }
    static var canopusSmall: CanopusButtonStyle { CanopusButtonStyle(kind: .ghost, small: true) }
    static var canopusDanger: CanopusButtonStyle { CanopusButtonStyle(kind: .danger) }
}

// MARK: - Small pieces

/// Security status in its color, as the game shows it ("0.5").
struct SecText: View {
    let value: Double
    var body: some View {
        Text(String(format: "%.1f", C.roundSec(value)))
            .font(.ui(13, .semibold))
            .monospacedDigit()
            .foregroundStyle(C.sec(value))
    }
}

/// A colored pill ("КЕМП", "БУБЛИ", "Онлайн").
struct Pill: View {
    let text: String
    var color: Color = C.accent
    var filled = false

    var body: some View {
        Text(LocalizedStringKey(text))
            .font(.ui(10.5, .bold, relativeTo: .caption2))
            .tracking(0.4)
            .foregroundStyle(filled ? .white : color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(filled ? color : color.opacity(0.16), in: RoundedRectangle(cornerRadius: 3))
    }
}

/// Skill level as five squares, filled up to the trained level (the desktop's LevelPips).
struct LevelPips: View {
    let level: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i <= level ? (level == 5 ? C.accent : C.text2) : C.panel2)
                    .overlay(RoundedRectangle(cornerRadius: 1.5).strokeBorder(i <= level ? .clear : C.lineStrong, lineWidth: 1))
                    .frame(width: 9, height: 9)
            }
        }
    }
}
