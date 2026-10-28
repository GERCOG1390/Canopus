// Fit snapshot: the whole fit on one card — every module, drones and implants, and the stats they give —
// drawn into a picture to save or send (the desktop's FitShot.tsx). The card is rendered with
// ImageRenderer, so every picture it shows is loaded first.

import SwiftUI
import EVEStaticData

/// Everything a snapshot shows, resolved up front.
struct FitShotData: Identifiable {
    let id = UUID()
    let spec: JSFitSpec
    let stats: JSFitStats
    let names: [Int: String]
    /// The pilot whose skills the stats use; nil for all skills at V.
    let pilot: String?
    var icons: [Int: UIImage] = [:]
    var render: UIImage?

    func name(_ id: Int) -> String { names[id] ?? "#\(id)" }

    /// The ship render and every module, charge, drone and implant icon.
    mutating func loadImages() async {
        let ids = Set(spec.modules.flatMap { [$0.typeId, $0.chargeTypeId].compactMap { $0 } }
            + spec.drones.map(\.typeId) + spec.implants)
        render = await EVETypeImages.image(typeId: spec.shipTypeId, render: true, size: 84)
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for id in ids {
                group.addTask { (id, await EVETypeImages.image(typeId: id, size: 24)) }
            }
            for await (id, img) in group {
                if let img { icons[id] = img }
            }
        }
    }
}

// MARK: - Sheet

/// Shows the snapshot and offers it to the share sheet (save to Photos, copy, send).
struct FitShotSheet: View {
    let data: FitShotData
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        ScrollView {
            if let image {
                // Fitted to the sheet's width; the picture itself keeps its full size for sharing.
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: FitShotCard.width)
                    .frame(maxWidth: .infinity)
                    .padding(16)
            } else {
                ProgressView().tint(C.accent).padding(.top, 80).frame(maxWidth: .infinity)
            }
        }
        .background(C.bg)
        .navigationTitle("Fit snapshot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                if let image {
                    let picture = Image(uiImage: image)
                    ShareLink(item: picture, preview: SharePreview(data.spec.name, image: picture)) {
                        Text("Share")
                    }
                }
            }
        }
        .task {
            let renderer = ImageRenderer(content: FitShotCard(data: data))
            renderer.scale = max(2, displayScale)
            image = renderer.uiImage
        }
    }
}

// MARK: - Card

private let slotOrder: [(key: String, attr: Int, title: LocalizedStringKey)] = [
    ("hi", 14, "High slots"), ("med", 13, "Mid slots"), ("lo", 12, "Low slots"),
    ("rig", 1137, "Rig slots"), ("sub", 1367, "Subsystems"),
]
private let resistIcons = [271, 274, 273, 272]
private let damageColors = [C.dmgEM, C.dmgThermal, C.dmgKinetic, C.dmgExplosive]

struct FitShotCard: View {
    static let width: CGFloat = 860
    let data: FitShotData

    private var s: JSFitStats { data.stats }
    private var f: JSFitSpec { data.spec }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(alignment: .top, spacing: 18) {
                modules.frame(maxWidth: .infinity, alignment: .topLeading)
                stats.frame(width: 400, alignment: .topLeading)
            }
        }
        .padding(20)
        .frame(width: Self.width)
        .background(C.panel)
        .overlay(Rectangle().strokeBorder(C.border, lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            picture(data.render, size: 84)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: data.name(f.shipTypeId)).font(.display(26)).foregroundStyle(C.text)
                Text(verbatim: f.name).font(.ui(15)).foregroundStyle(C.text2)
                if let pilot = data.pilot {
                    Text("Skills: \(pilot)").font(.ui(12)).foregroundStyle(C.muted)
                } else {
                    Text("Skills: all V").font(.ui(12)).foregroundStyle(C.muted)
                }
            }
            Spacer()
            Text(verbatim: "Canopus").font(.display(18)).foregroundStyle(C.accentText)
        }
    }

    // MARK: Modules

    private var modules: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(slotOrder, id: \.key) { slot in
                let mods = f.modules.filter { $0.slot == slot.key }
                let total = Int(s.ship.slots[slot.key] ?? 0)
                if !mods.isEmpty || total > 0 {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            GameIcon.attribute(slot.attr, size: 16)
                            Text(slot.title)
                            Text(verbatim: "\(mods.count)/\(total)").foregroundStyle(C.muted)
                        }
                        .font(.ui(12, .medium)).tracking(1.2).textCase(.uppercase).foregroundStyle(C.text2)
                        ForEach(Array(groups(mods).enumerated()), id: \.offset) { _, g in
                            moduleLine(g.module, count: g.count)
                        }
                    }
                }
            }
        }
    }

    /// Identical modules (same type, charge and state) as one line: "3× 200mm AutoCannon II".
    private func groups(_ mods: [JSFitModule]) -> [(module: JSFitModule, count: Int)] {
        var out: [(module: JSFitModule, count: Int)] = []
        for m in mods {
            if let i = out.firstIndex(where: { $0.module.typeId == m.typeId && $0.module.chargeTypeId == m.chargeTypeId && $0.module.state == m.state }) {
                out[i].count += 1
            } else {
                out.append((m, 1))
            }
        }
        return out
    }

    private func moduleLine(_ m: JSFitModule, count: Int) -> some View {
        HStack(spacing: 7) {
            picture(data.icons[m.typeId], size: 22)
            Text(verbatim: (count > 1 ? "\(count)× " : "") + data.name(m.typeId))
                .font(.ui(13)).foregroundStyle(C.text).lineLimit(1)
                .layoutPriority(1)
            if let c = m.chargeTypeId {
                HStack(spacing: 4) {
                    picture(data.icons[c], size: 16)
                    Text(verbatim: data.name(c)).lineLimit(1)
                }
                .font(.ui(11)).foregroundStyle(C.muted)
            }
            if m.state == "offline" { Text("off").font(.ui(11)).foregroundStyle(C.muted) }
            if m.state == "overload" { Text("overheated").font(.ui(11)).foregroundStyle(C.bad) }
        }
        .opacity(m.state == "offline" ? 0.5 : 1)
    }

    // MARK: Stats

    private var stats: some View {
        let d = s.defense, o = s.offense, nav = s.navigation
        let repair = d.shieldBoost + d.armorRepair + d.hullRepair
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                big("DPS", n1(o.totalDps), sub: Text("volley \(n0(o.totalVolley))"), accent: true)
                big("EHP", n0(d.ehp), sub: repair > 0 ? Text("repair \(n1(d.activeTankEhp)) EHP/s") : Text("\(n0(d.hp)) HP"))
                big("Speed", String(localized: "\(n0(nav.maxVelocity)) m/s"), sub: Text("align \(n2(nav.alignSec)) s"))
            }
            resists
            VStack(spacing: 5) {
                kv("Capacitor", Text(capText), color: s.capacitor.stable ? C.good : C.text)
                if !o.weapons.isEmpty {
                    kv("Damage", Text(verbatim: damageParts.joined(separator: " · ")))
                }
                if repair > 0 {
                    kv("Repair", Text(verbatim: repairParts.joined(separator: " · ")))
                }
                kv("Signature", Text("\(n1(nav.signatureRadius)) m"))
                kv("Warp", Text("\(n2(nav.warpSpeed)) AU/s"))
                kv("Targeting", Text("\(km(s.targeting.maxRange)) · \(n0(s.targeting.scanResolution)) mm · \(Int(s.targeting.maxTargets)) targets"))
                kv("CPU", Text(verbatim: "\(n1(s.ship.cpu.used)) / \(n1(s.ship.cpu.total)) tf"), color: over(s.ship.cpu) ? C.bad : C.text)
                kv("Powergrid", Text(verbatim: "\(n1(s.ship.power.used)) / \(n1(s.ship.power.total)) MW"), color: over(s.ship.power) ? C.bad : C.text)
                if s.ship.calibration.total > 0 {
                    kv("Calibration", Text(verbatim: "\(n0(s.ship.calibration.used)) / \(n0(s.ship.calibration.total))"))
                }
            }
            if !f.drones.isEmpty {
                extra(Text("Drones"), Text(verbatim: "\(n0(s.ship.droneBay.used))/\(n0(s.ship.droneBay.total)) m³")) {
                    ForEach(f.drones, id: \.typeId) { x in
                        HStack(spacing: 7) {
                            picture(data.icons[x.typeId], size: 22)
                            Text(verbatim: "\(x.count)× \(data.name(x.typeId))").font(.ui(13)).foregroundStyle(C.text)
                            if x.active > 0 && x.active < x.count {
                                Text("\(x.active) launched").font(.ui(11)).foregroundStyle(C.muted)
                            }
                        }
                    }
                }
            }
            extra(Text("Implants"), f.implants.isEmpty ? Text("none") : nil) {
                ForEach(f.implants, id: \.self) { id in
                    HStack(spacing: 7) {
                        picture(data.icons[id], size: 22)
                        Text(verbatim: data.name(id)).font(.ui(13)).foregroundStyle(C.text).lineLimit(1)
                    }
                }
            }
        }
    }

    private var resists: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Color.clear.frame(width: 92, height: 1)
                ForEach(resistIcons, id: \.self) { GameIcon.attribute($0, size: 16).frame(maxWidth: .infinity) }
                Text(verbatim: "HP").font(.ui(11, .medium)).foregroundStyle(C.muted).frame(width: 64, alignment: .trailing)
            }
            layer("Shield", 263, s.defense.shield)
            layer("Armor", 265, s.defense.armor)
            layer("Hull", 9, s.defense.hull)
        }
        .padding(10)
        .background(C.card)
    }

    private func layer(_ name: LocalizedStringKey, _ icon: Int, _ l: JSFitStats.Layer) -> some View {
        HStack(spacing: 4) {
            HStack(spacing: 5) {
                GameIcon.attribute(icon, size: 16)
                Text(name).font(.ui(12)).foregroundStyle(C.text2)
            }
            .frame(width: 92, alignment: .leading)
            ForEach(0..<4, id: \.self) { i in
                let r = i < l.resist.count ? l.resist[i] : 0
                ZStack(alignment: .leading) {
                    Rectangle().fill(damageColors[i].opacity(0.10))
                    GeometryReader { g in
                        Rectangle().fill(damageColors[i].opacity(0.35)).frame(width: g.size.width * min(1, max(0, r)))
                    }
                    Text(verbatim: "\(Int((r * 100).rounded()))%")
                        .font(.mono(11, medium: true)).foregroundStyle(C.text).frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity).frame(height: 20)
            }
            Text(verbatim: n0(l.hp)).font(.mono(11)).foregroundStyle(C.text2).frame(width: 64, alignment: .trailing)
        }
    }

    // MARK: Pieces

    private func big(_ label: LocalizedStringKey, _ value: String, sub: Text, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.ui(11, .medium)).tracking(1.4).textCase(.uppercase).foregroundStyle(C.muted)
            Text(verbatim: value).font(.display(22)).foregroundStyle(accent ? C.accentText : C.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            sub.font(.ui(11)).foregroundStyle(C.muted).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(C.card)
    }

    private func kv(_ label: LocalizedStringKey, _ value: Text, color: Color = C.text) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.ui(12)).foregroundStyle(C.muted)
            Spacer(minLength: 8)
            value.font(.mono(12, medium: true)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func extra<Content: View>(_ title: Text, _ trailing: Text?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                title
                if let trailing { trailing.foregroundStyle(C.muted) }
            }
            .font(.ui(12, .medium)).tracking(1.2).textCase(.uppercase).foregroundStyle(C.text2)
            content()
        }
    }

    @ViewBuilder private func picture(_ image: UIImage?, size: CGFloat) -> some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Rectangle().fill(C.panel2).frame(width: size, height: size)
        }
    }

    // MARK: Text

    private var capText: String {
        let c = s.capacitor
        if c.stable {
            return String(localized: "\(n0(c.capacity)) GJ · stable \(Int(((c.stableLevel ?? 1) * 100).rounded()))%")
        }
        let sec = Int((c.lastsSec ?? 0).rounded())
        return String(localized: "\(n0(c.capacity)) GJ · lasts \(sec / 60):\(String(format: "%02d", sec % 60))")
    }

    private var damageParts: [String] {
        let o = s.offense
        var out: [String] = []
        if o.turretDps > 0 { out.append(String(localized: "turrets \(n1(o.turretDps))")) }
        if o.missileDps > 0 { out.append(String(localized: "missiles \(n1(o.missileDps))")) }
        if o.droneDps > 0 { out.append(String(localized: "drones \(n1(o.droneDps))")) }
        return out
    }

    private var repairParts: [String] {
        let d = s.defense
        var out: [String] = []
        if d.shieldBoost > 0 { out.append(String(localized: "shield \(n1(d.shieldBoost))")) }
        if d.armorRepair > 0 { out.append(String(localized: "armor \(n1(d.armorRepair))")) }
        if d.hullRepair > 0 { out.append(String(localized: "hull \(n1(d.hullRepair))")) }
        return [out.joined(separator: " · ") + " " + String(localized: "HP/s")]
    }

    private func over(_ u: JSFitStats.Use) -> Bool { u.used > u.total + 1e-6 }
}

private func n0(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0))) }
private func n1(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1))) }
private func n2(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...2))) }
private func km(_ m: Double) -> String { String(localized: "\(n1(m / 1000)) km") }
