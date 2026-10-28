// The desktop's line icons for the app chrome (canopus-desktop src/renderer/src/components/Glyph.tsx):
// the same SVG paths on a 24×24 grid, stroked 1.6 like on the desktop. Game things use CCP's own icons
// (GameIcon / EVETypeIcon), never invented symbols.

import SwiftUI
import UIKit

enum GlyphName: String, CaseIterable {
    case stream, character, mail, fleet, intel, fitting, pvp, market, industry, map, activities, settings
    case search, chevron, star, bolt, palette, update, user, globe, rows, assistant, alert

    /// Copied verbatim from Glyph.tsx.
    var path: String {
        switch self {
        case .stream: "M12 12m-2 0a2 2 0 1 0 4 0a2 2 0 1 0-4 0M8.5 8.5a5 5 0 0 0 0 7M15.5 8.5a5 5 0 0 1 0 7M5.6 5.6a9 9 0 0 0 0 12.8M18.4 5.6a9 9 0 0 1 0 12.8"
        case .character: "M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 20c1.5-3.5 4.5-5 8-5s6.5 1.5 8 5"
        case .mail: "M3 6h18v12H3zM3 7l9 6 9-6"
        case .fleet: "M5 21V4M5 4h11l-2 4 2 4H5"
        case .intel: "M12 12m-8 0a8 8 0 1 0 16 0a8 8 0 1 0-16 0M12 12m-3.5 0a3.5 3.5 0 1 0 7 0a3.5 3.5 0 1 0-7 0M12 12L18 6"
        case .fitting: "M12 3l7.8 4.5v9L12 21l-7.8-4.5v-9zM12 8.5l3 1.75v3.5L12 15.5l-3-1.75v-3.5z"
        case .pvp: "M12 12m-7 0a7 7 0 1 0 14 0a7 7 0 1 0-14 0M12 2v5M12 17v5M2 12h5M17 12h5"
        case .market: "M4 19V5M4 19h16M8 15l3-4 3 2 5-6"
        case .industry: "M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9L7 7M17 17l2.1 2.1M4.9 19.1L7 17M17 7l2.1-2.1"
        case .map: "M9 4L3 7v13l6-3 6 3 6-3V4l-6 3-6-3zM9 4v13M15 7v13"
        case .activities: "M12 3l9 9-9 9-9-9zM12 8l4 4-4 4-4-4z"
        case .settings: "M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12M14 4v4M8 10v4M16 16v4"
        case .search: "M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14zM20 20l-4-4"
        case .chevron: "M9 6l6 6-6 6"
        case .star: "M12 2l2.2 7.8L22 12l-7.8 2.2L12 22l-2.2-7.8L2 12l7.8-2.2z"
        case .bolt: "M13 2L4 14h7l-1 8 9-12h-7z"
        case .palette: "M12 3a9 9 0 1 0 0 18c1 0 1.5-.8 1.5-1.6 0-1.2-1-1.4-1-2.4 0-.8.6-1.5 1.5-1.5H16a5 5 0 0 0 5-5c0-4-4-7.5-9-7.5zM7.5 11.5h0M10 7.5h0M14.5 7.5h0"
        case .update: "M20 12a8 8 0 1 1-2.3-5.7M20 4v4h-4"
        case .user: "M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 20c1.5-3.5 4.5-5 8-5s6.5 1.5 8 5M19 8v6M16 11h6"
        case .globe: "M12 12m-9 0a9 9 0 1 0 18 0a9 9 0 1 0-18 0M3 12h18M12 3c2.5 2.5 3.5 5.5 3.5 9s-1 6.5-3.5 9c-2.5-2.5-3.5-5.5-3.5-9s1-6.5 3.5-9z"
        case .rows: "M4 6h16M4 12h16M4 18h16"
        case .assistant: "M4 5h16v11H10l-5 4v-4H4zM8 9.5h8M8 12.5h5"
        case .alert: "M12 3l10 18H2zM12 10v5M12 18v.5"
        }
    }
}

/// A desktop glyph, stroked in the current foreground color.
struct Glyph: View {
    let name: GlyphName
    var size: CGFloat = 18

    var body: some View {
        GlyphShape(name: name)
            .stroke(style: StrokeStyle(lineWidth: 1.6 * size / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }

    /// A template image of the glyph, for places that only take images (the tab bar).
    @MainActor static func image(_ name: GlyphName, size: CGFloat = 24) -> Image {
        let renderer = ImageRenderer(content: Glyph(name: name, size: size).foregroundStyle(.black).padding(1))
        renderer.scale = UIScreen.main.scale
        guard let ui = renderer.uiImage else { return Image(systemName: "circle") }
        return Image(uiImage: ui.withRenderingMode(.alwaysTemplate))
    }
}

struct GlyphShape: Shape {
    let name: GlyphName

    func path(in rect: CGRect) -> Path {
        let p = SVGPath.parse(name.path)
        return p.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24).translatedBy(x: rect.minX, y: rect.minY))
    }
}

/// A small SVG path-data parser (M L H V C S A Z, absolute and relative), enough for the glyph set.
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var path = Path()
        var tokens = tokenize(d)[...]
        var cmd: Character = "M"
        var cur = CGPoint.zero
        var start = CGPoint.zero
        var lastCtrl: CGPoint?

        func num() -> CGFloat {
            if case .number(let v) = tokens.first { tokens = tokens.dropFirst(); return v }
            return 0
        }

        while !tokens.isEmpty {
            if case .command(let c) = tokens.first {
                cmd = c
                tokens = tokens.dropFirst()
            }
            let rel = cmd.isLowercase
            let base = rel ? cur : .zero
            switch Character(cmd.uppercased()) {
            case "M":
                cur = CGPoint(x: base.x + num(), y: base.y + num())
                start = cur
                path.move(to: cur)
                cmd = rel ? "l" : "L"
                lastCtrl = nil
            case "L":
                cur = CGPoint(x: base.x + num(), y: base.y + num())
                path.addLine(to: cur)
                lastCtrl = nil
            case "H":
                cur = CGPoint(x: (rel ? cur.x : 0) + num(), y: cur.y)
                path.addLine(to: cur)
                lastCtrl = nil
            case "V":
                cur = CGPoint(x: cur.x, y: (rel ? cur.y : 0) + num())
                path.addLine(to: cur)
                lastCtrl = nil
            case "C":
                let c1 = CGPoint(x: base.x + num(), y: base.y + num())
                let c2 = CGPoint(x: base.x + num(), y: base.y + num())
                cur = CGPoint(x: base.x + num(), y: base.y + num())
                path.addCurve(to: cur, control1: c1, control2: c2)
                lastCtrl = c2
            case "S":
                let c1 = lastCtrl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let c2 = CGPoint(x: base.x + num(), y: base.y + num())
                cur = CGPoint(x: base.x + num(), y: base.y + num())
                path.addCurve(to: cur, control1: c1, control2: c2)
                lastCtrl = c2
            case "A":
                let rx = num(), ry = num(), rot = num(), large = num() != 0, sweep = num() != 0
                let end = CGPoint(x: base.x + num(), y: base.y + num())
                addArc(&path, from: cur, to: end, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep)
                cur = end
                lastCtrl = nil
            case "Z":
                path.closeSubpath()
                cur = start
                lastCtrl = nil
                continue
            default:
                tokens = tokens.dropFirst()
            }
        }
        return path
    }

    private enum Token { case command(Character), number(CGFloat) }

    private static func tokenize(_ d: String) -> [Token] {
        var out: [Token] = []
        var numStr = ""
        func flush() {
            if !numStr.isEmpty, let v = Double(numStr) { out.append(.number(CGFloat(v))) }
            numStr = ""
        }
        for ch in d {
            if ch.isLetter && ch != "e" {
                flush()
                out.append(.command(ch))
            } else if ch == "-" && !numStr.isEmpty && numStr.last != "e" {
                flush()
                numStr = "-"
            } else if ch == "." && numStr.contains(".") {
                flush()
                numStr = "."
            } else if ch == " " || ch == "," {
                flush()
            } else {
                numStr.append(ch)
            }
        }
        flush()
        return out
    }

    /// SVG elliptical arc to cubic Béziers (the endpoint parameterization of the SVG spec).
    private static func addArc(_ path: inout Path, from p0: CGPoint, to p1: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat, rotation: CGFloat, large: Bool, sweep: Bool) {
        if p0 == p1 { return }
        var rx = abs(rx0), ry = abs(ry0)
        if rx == 0 || ry == 0 { path.addLine(to: p1); return }
        let phi = rotation * .pi / 180
        let cosP = cos(phi), sinP = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosP * dx + sinP * dy, y1 = -sinP * dx + cosP * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var coef = sqrt(max(0, num / den))
        if large == sweep { coef = -coef }
        let cxp = coef * rx * y1 / ry, cyp = -coef * ry * x1 / rx
        let cx = cosP * cxp - sinP * cyp + (p0.x + p1.x) / 2
        let cy = sinP * cxp + cosP * cyp + (p0.y + p1.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let t1 = angle(1, 0, (x1 - cxp) / rx, (y1 - cyp) / ry)
        var dt = angle((x1 - cxp) / rx, (y1 - cyp) / ry, (-x1 - cxp) / rx, (-y1 - cyp) / ry)
        if !sweep && dt > 0 { dt -= 2 * .pi } else if sweep && dt < 0 { dt += 2 * .pi }
        let segments = Int(ceil(abs(dt) / (.pi / 2)))
        let delta = dt / CGFloat(segments)
        let k = 4 / 3 * tan(delta / 4)
        var t = t1
        for _ in 0..<segments {
            let c1 = point(cx, cy, rx, ry, cosP, sinP, t)
            let c2 = point(cx, cy, rx, ry, cosP, sinP, t + delta)
            let d1 = derivative(rx, ry, cosP, sinP, t)
            let d2 = derivative(rx, ry, cosP, sinP, t + delta)
            path.addCurve(
                to: c2,
                control1: CGPoint(x: c1.x + k * d1.x, y: c1.y + k * d1.y),
                control2: CGPoint(x: c2.x - k * d2.x, y: c2.y - k * d2.y)
            )
            t += delta
        }
    }

    private static func point(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ c: CGFloat, _ s: CGFloat, _ t: CGFloat) -> CGPoint {
        CGPoint(x: cx + rx * cos(t) * c - ry * sin(t) * s, y: cy + rx * cos(t) * s + ry * sin(t) * c)
    }

    private static func derivative(_ rx: CGFloat, _ ry: CGFloat, _ c: CGFloat, _ s: CGFloat, _ t: CGFloat) -> CGPoint {
        CGPoint(x: -rx * sin(t) * c - ry * cos(t) * s, y: -rx * sin(t) * s + ry * cos(t) * c)
    }
}

/// An original EVE client icon bundled in Assets.xcassets/GameIcons: a window icon (`win_skills`) or a
/// dogma attribute's icon (`attr_164`).
struct GameIcon: View {
    let name: String
    var size: CGFloat = 24

    init(_ name: String, size: CGFloat = 24) {
        self.name = name
        self.size = size
    }

    /// The icon the game shows next to a dogma attribute.
    static func attribute(_ attributeId: Int, size: CGFloat = 20) -> GameIcon {
        GameIcon("attr_\(attributeId)", size: size)
    }

    var body: some View {
        Image(name)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

/// An empty or error state with the game's window icon, in place of the system's ContentUnavailableView.
struct EmptyState<Description: View>: View {
    let title: LocalizedStringKey
    let icon: String
    @ViewBuilder var description: () -> Description

    init(_ title: LocalizedStringKey, icon: String, @ViewBuilder description: @escaping () -> Description) {
        self.title = title
        self.icon = icon
        self.description = description
    }

    var body: some View {
        VStack(spacing: 10) {
            GameIcon(icon, size: 48).opacity(0.7)
            Text(title)
                .font(.ui(17, .semibold))
                .foregroundStyle(C.text)
                .multilineTextAlignment(.center)
            description()
                .font(.ui(14))
                .foregroundStyle(C.muted)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

extension EmptyState where Description == EmptyView {
    init(_ title: LocalizedStringKey, icon: String) {
        self.init(title, icon: icon) { EmptyView() }
    }
}
