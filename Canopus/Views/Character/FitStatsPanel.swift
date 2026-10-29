// The fit's numbers laid out like the desktop's stats panel (canopus-desktop FittingPage.tsx: FitMetrics +
// StatsPanel): headline metrics, then resources, firepower, defense, capacitor, navigation and targeting,
// every line with the game's own attribute icon. Everything comes straight from the desktop engine's result.

import SwiftUI
import EVEStaticData

/// Dogma attribute IDs whose in-game icons label the stats (the desktop's `ICON`).
private enum StatAttr {
    static let cpu = 48, power = 11, calibration = 1132, turrets = 102, launchers = 101
    static let droneBandwidth = 1271, droneBay = 283
    static let shield = 263, armor = 265, hull = 9
    static let resist = [271, 274, 273, 272]
    static let damage = [114, 118, 117, 116]
    static let capacitor = 482, recharge = 55
    static let velocity = 37, agility = 70, signature = 552, mass = 4
    static let targetRange = 76, scanRes = 564, maxTargets = 192, cargo = 38, shieldRecharge = 479
    static let optimal = 54, explosionRadius = 654
}

private let damageColors = [C.dmgEM, C.dmgThermal, C.dmgKinetic, C.dmgExplosive]
private let damageNames: [LocalizedStringKey] = ["EM", "Thermal", "Kinetic", "Explosive"]

struct FitStatsPanel: View {
    let stats: JSFitStats
    /// Name of a module or charge type.
    let typeName: (Int) -> String
    var cargoUsed: Double = 0

    private var s: JSFitStats { stats }

    /// Damage per second split by type across all weapons.
    private var damage: [Double] {
        s.offense.weapons.reduce(into: [0, 0, 0, 0]) { acc, w in
            for i in 0..<min(4, w.damage.count) { acc[i] += w.damage[i] / (w.cycle > 0 ? w.cycle : 1) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let problems = self.problems
            if !problems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(problems, id: \.self) { p in
                        Text("⚠ " + p).font(.ui(13)).foregroundStyle(C.bad)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(C.badFill.opacity(0.12), in: EVECut())
                .overlay(EVECut().strokeBorder(C.bad.opacity(0.5), lineWidth: 1))
            }
            metrics
            resources.id("resources")
            firepower.id("firepower")
            defense.id("defense")
            capacitor.id("capacitor")
            navigation.id("navigation")
            targeting.id("targeting")
            Text("Calculated with the desktop engine from SDE dogma: skills, hull bonuses, modules, charges, implants and stacking penalties.")
                .font(.ui(12))
                .foregroundStyle(C.faint)
        }
    }

    // MARK: Headline metrics

    private var metrics: some View {
        let total = damage.reduce(0, +)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            MetricCard(label: "DPS") {
                Text(n1(s.offense.totalDps)).font(.display(24)).foregroundStyle(C.accentText)
            } sub: {
                Text("with reload \(n1(s.offense.totalDpsReload))")
            }
            MetricCard(label: "Volley") {
                Text(n0(s.offense.totalVolley)).font(.display(24)).foregroundStyle(C.text)
            } sub: {
                if total > 0 {
                    DamageBar(damage: damage).frame(height: 6).padding(.vertical, 5)
                } else {
                    Text("no weapons")
                }
            }
            MetricCard(label: "Effective HP") {
                Text(n0(s.defense.ehp)).font(.display(24)).foregroundStyle(C.text)
            } sub: {
                Text("\(n0(s.defense.hp)) HP without resists")
            }
            ResourceCard(label: "CPU", use: s.ship.cpu, unit: "tf")
            ResourceCard(label: "Powergrid", use: s.ship.power, unit: "MW")
        }
    }

    // MARK: Sections

    private var resources: some View {
        Card("Resources") {
            UsageBar(attr: StatAttr.calibration, label: "Calibration", use: s.ship.calibration, unit: "", digits: 0)
            HStack(spacing: 16) {
                IconLabel(attr: StatAttr.turrets, text: Text("Turrets \(Int(s.ship.turrets.used))/\(Int(s.ship.turrets.total))"))
                IconLabel(attr: StatAttr.launchers, text: Text("Launchers \(Int(s.ship.launchers.used))/\(Int(s.ship.launchers.total))"))
                Spacer(minLength: 0)
            }
            if s.ship.droneBandwidth.total > 0 {
                UsageBar(attr: StatAttr.droneBandwidth, label: "Drone bandwidth", use: s.ship.droneBandwidth, unit: " Mbit/s", digits: 0)
            }
            if s.ship.droneBay.total > 0 {
                UsageBar(attr: StatAttr.droneBay, label: "Drone bay", use: s.ship.droneBay, unit: " m³", digits: 0)
            }
        }
    }

    private var firepower: some View {
        let dmg = damage
        let total = dmg.reduce(0, +)
        let weapons = groupedWeapons
        return Card("Firepower") {
            if total > 0 {
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { i in
                        if dmg[i] > 0 {
                            HStack(spacing: 4) {
                                GameIcon.attribute(StatAttr.damage[i], size: 18)
                                Text("\(Int((dmg[i] / total * 100).rounded()))%")
                                    .font(.mono(12, medium: true))
                                    .foregroundStyle(damageColors[i])
                            }
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(damageColors[i].opacity(0.12), in: Capsule())
                            .accessibilityLabel(Text(damageNames[i]))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            if weapons.isEmpty {
                Text("No active weapons with charges.").font(.ui(13)).foregroundStyle(C.muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(weapons.enumerated()), id: \.offset) { i, w in
                        if i > 0 { Rectangle().fill(C.border).frame(height: 1) }
                        weaponRow(w)
                    }
                }
            }
        }
    }

    private func weaponRow(_ w: JSFitStats.Weapon) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                if w.count > 1 {
                    Text("\(Int(w.count))×").font(.mono(13, medium: true)).foregroundStyle(C.accentText)
                }
                Text(typeName(w.typeId)).font(.ui(14)).foregroundStyle(C.text).lineLimit(1)
                Spacer(minLength: 8)
                Text("\(n1(w.dps)) DPS").font(.mono(13, medium: true)).foregroundStyle(C.text)
            }
            HStack(spacing: 8) {
                if let c = w.chargeTypeId {
                    Text(typeName(c)).lineLimit(1)
                }
                Spacer(minLength: 4)
                if let range = rangeText(w) {
                    HStack(spacing: 3) {
                        GameIcon.attribute(w.kind == "missile" ? StatAttr.explosionRadius : StatAttr.optimal, size: 16)
                        Text(range)
                    }
                }
            }
            .font(.ui(12))
            .foregroundStyle(C.muted)
        }
        .padding(.vertical, 7)
    }

    private var defense: some View {
        let d = s.defense
        return Card("Defense") {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Color.clear.frame(width: LayerRow.nameWidth)
                    ForEach(0..<4, id: \.self) { i in
                        GameIcon.attribute(StatAttr.resist[i], size: 20)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel(Text(damageNames[i]))
                    }
                    Text("EHP").font(.ui(11, .medium)).tracking(1.2).foregroundStyle(C.muted)
                        .frame(width: LayerRow.ehpWidth, alignment: .trailing)
                }
                LayerRow(name: "Shield", attr: StatAttr.shield, layer: d.shield)
                LayerRow(name: "Armor", attr: StatAttr.armor, layer: d.armor)
                LayerRow(name: "Hull", attr: StatAttr.hull, layer: d.hull)
            }
            KVList {
                KV(attr: StatAttr.shieldRecharge, label: "Shield regeneration",
                   value: Text("\(n1(d.passiveShieldRegen)) HP/s · \(n0(d.shieldRechargeSec)) s"))
                if d.shieldBoost > 0 {
                    KV(attr: StatAttr.shield, label: "Shield boost", value: Text("\(n1(d.shieldBoost)) HP/s"))
                }
                if d.armorRepair > 0 {
                    KV(attr: StatAttr.armor, label: "Armor repair", value: Text("\(n1(d.armorRepair)) HP/s"))
                }
                if d.hullRepair > 0 {
                    KV(attr: StatAttr.hull, label: "Hull repair", value: Text("\(n1(d.hullRepair)) HP/s"))
                }
                if d.activeTankEhp > 0 {
                    KV(attr: nil, label: "Active tank", value: Text("\(n1(d.activeTankEhp)) EHP/s"))
                }
            }
        }
    }

    private var capacitor: some View {
        let c = s.capacitor
        return Card("Capacitor") {
            KVList {
                KV(attr: StatAttr.capacitor, label: "Capacitor capacity", value: Text("\(n0(c.capacity)) GJ"))
                KV(attr: StatAttr.recharge, label: "Recharge time", value: Text("\(n1(c.rechargeSec)) s"))
                KV(attr: nil, label: "Use / peak recharge", value: Text("\(n2(c.usePerSecond)) / \(n2(c.peakRecharge)) GJ/s"))
                KV(attr: nil, label: "Stability",
                   value: c.stable
                       ? Text("stable at \(String(format: "%.1f", (c.stableLevel ?? 1) * 100))%")
                       : Text("runs out in \(duration(c.lastsSec ?? 0))"),
                   color: c.stable ? C.good : C.bad)
            }
        }
    }

    private var navigation: some View {
        let n = s.navigation
        return Card("Navigation") {
            KVList {
                KV(attr: StatAttr.velocity, label: "Max velocity", value: Text("\(n1(n.maxVelocity)) m/s"))
                KV(attr: StatAttr.agility, label: "Align time", value: Text("\(n2(n.alignSec)) s · \(n2(n.agility))x"))
                KV(attr: nil, label: "Warp speed", value: Text("\(n2(n.warpSpeed)) AU/s"))
                KV(attr: StatAttr.signature, label: "Signature radius", value: Text("\(n1(n.signatureRadius)) m"))
                KV(attr: StatAttr.mass, label: "Mass", value: Text("\(n0(n.mass / 1000)) t"))
            }
        }
    }

    private var targeting: some View {
        let t = s.targeting
        let sensor = Self.sensors[t.sensorType]
        return Card("Targeting") {
            KVList {
                KV(attr: StatAttr.targetRange, label: "Targeting range", value: Text(km(t.maxRange)))
                KV(attr: StatAttr.scanRes, label: "Scan resolution", value: Text("\(n1(t.scanResolution)) mm"))
                KV(attr: StatAttr.maxTargets, label: "Max locked targets", value: Text(verbatim: "\(Int(t.maxTargets))"))
                KV(attr: sensor?.attr, label: sensor.map { Text($0.label) } ?? Text("Sensor strength"), value: Text(n2(t.sensorStrength)))
                if s.ship.droneBandwidth.total > 0, let r = t.droneControlRange {
                    KV(attr: nil, label: "Drone control range", value: Text(km(r)))
                }
                KV(attr: StatAttr.cargo, label: "Cargo hold",
                   value: Text(cargoUsed > 0 ? "\(n1(cargoUsed)) / \(n0(s.ship.cargo)) m³" : "\(n0(s.ship.cargo)) m³"))
            }
        }
    }

    // MARK: Data

    /// The engine names the strongest sensor in Russian; the attribute behind it gives the icon.
    private static let sensors: [String: (attr: Int, label: String)] = [
        "Радар": (208, String(localized: "Sensor strength (Radar)")),
        "Ладар": (209, String(localized: "Sensor strength (Ladar)")),
        "Магнитометрия": (210, String(localized: "Sensor strength (Magnetometric)")),
        "Гравиметрия": (211, String(localized: "Sensor strength (Gravimetric)")),
    ]

    /// Weapons of one type with one charge merged into a line, strongest first (the desktop's groupWeapons).
    private var groupedWeapons: [JSFitStats.Weapon] {
        var order: [String] = []
        var merged: [String: (w: JSFitStats.Weapon, count: Double, dps: Double)] = [:]
        for w in s.offense.weapons {
            let key = "\(w.kind)-\(w.typeId)-\(w.chargeTypeId ?? 0)"
            if let m = merged[key] {
                merged[key] = (m.w, m.count + w.count, m.dps + w.dps)
            } else {
                order.append(key)
                merged[key] = (w, w.count, w.dps)
            }
        }
        return order.compactMap { merged[$0] }
            .map { JSFitStats.Weapon(merging: $0.w, count: $0.count, dps: $0.dps) }
            .sorted { $0.dps > $1.dps }
    }

    /// The engine's problems (resources, slots, hardpoints, drones and per-module rules), in the app's language.
    private var problems: [String] { s.problems.map(EngineProblem.localized) }

    private func rangeText(_ w: JSFitStats.Weapon) -> String? {
        if w.kind == "missile" { return "\(km(w.optimal ?? 0)) · \(n0(w.explosionRadius ?? 0)) m" }
        if let o = w.optimal { return "\(km(o)) + \(km(w.falloff ?? 0))" }
        return nil
    }

    private func duration(_ sec: Double) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = sec >= 3600 ? [.hour, .minute] : [.minute, .second]
        f.unitsStyle = .abbreviated
        return f.string(from: sec) ?? "—"
    }
}

extension JSFitStats.Weapon {
    /// A copy with the merged count and DPS of a weapon group.
    init(merging w: JSFitStats.Weapon, count: Double, dps: Double) {
        self = w
        self.count = count
        self.dps = dps
    }
}

// MARK: - Engine problems

/// The desktop engine words its problems in Russian (canopus-desktop src/main/dogma/stats.ts); this maps
/// each known message to the app's language. A module's problem comes as "<type name>: <message>".
enum EngineProblem {
    private static let rules: [(NSRegularExpression, ([String]) -> String)] = patterns.map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    private static let patterns: [(String, ([String]) -> String)] = [
        (#"^Слишком много модулей в слотах «(\w+)»: (\d+) из (\d+)$"#, { m in String(localized: "Too many modules in \(slotName(m[0])) slots: \(m[1]) of \(m[2])") }),
        (#"^Не хватает CPU$"#, { _ in String(localized: "Not enough CPU") }),
        (#"^Не хватает мощности реактора \(PG\)$"#, { _ in String(localized: "Not enough powergrid") }),
        (#"^Не хватает калибровки для ригов$"#, { _ in String(localized: "Not enough calibration for the rigs") }),
        (#"^Не хватает точек монтажа турелей$"#, { _ in String(localized: "Not enough turret hardpoints") }),
        (#"^Не хватает точек монтажа пусковых установок$"#, { _ in String(localized: "Not enough launcher hardpoints") }),
        (#"^Дроны не помещаются в отсек$"#, { _ in String(localized: "The drones don't fit in the drone bay") }),
        (#"^Не хватает пропускной способности для дронов$"#, { _ in String(localized: "Not enough drone bandwidth") }),
        (#"^Можно запустить не больше (\d+) дронов$"#, { m in String(localized: "At most \(m[0]) drones can be launched") }),
        (#"^Нельзя установить на этот корабль$"#, { _ in String(localized: "Can't be fitted to this ship") }),
        (#"^Неподходящий размер рига$"#, { _ in String(localized: "Wrong rig size") }),
        (#"^Можно установить не больше (\d+) модулей этой группы$"#, { m in String(localized: "At most \(m[0]) modules of this group can be fitted") }),
        (#"^Активным может быть не больше (\d+) модулей этой группы$"#, { m in String(localized: "At most \(m[0]) modules of this group can be active") }),
    ]

    /// One engine message in the app's language; a "<module>: <message>" keeps the module name.
    static func localized(_ text: String) -> String {
        if let m = message(text) { return m }
        if let r = text.range(of: ": ", options: .backwards), let m = message(String(text[r.upperBound...])) {
            return text[..<r.lowerBound] + ": " + m
        }
        return text
    }

    /// A known message translated, or nil.
    static func message(_ text: String) -> String? {
        let ns = text as NSString
        for (re, make) in rules {
            if let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                return make((1..<m.numberOfRanges).map { ns.substring(with: m.range(at: $0)) })
            }
        }
        return nil
    }

    private static func slotName(_ slot: String) -> String {
        switch slot {
        case "hi": String(localized: "high")
        case "med": String(localized: "medium")
        case "lo": String(localized: "low")
        case "rig": String(localized: "rig")
        default: String(localized: "subsystem")
        }
    }
}

// MARK: - Number formatting (the desktop's n1 / n2 / km)

private func n0(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0))) }
private func n1(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1))) }
private func n2(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...2))) }
private func km(_ m: Double) -> String {
    m >= 1000 ? String(localized: "\(n1(m / 1000)) km") : String(localized: "\(n0(m)) m")
}

// MARK: - Pieces

/// The desktop `.stat.metric`: label, big number, one line under it.
private struct MetricCard<Value: View, Sub: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder var value: () -> Value
    @ViewBuilder var sub: () -> Sub

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.ui(11, .medium, relativeTo: .caption)).tracking(1.5).textCase(.uppercase)
                .foregroundStyle(C.muted)
            value().monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            sub().font(.ui(12)).foregroundStyle(C.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .canopusSurface(padding: 12)
    }
}

/// CPU / powergrid card: used / total with a bar; amber when nearly full, red when over.
private struct ResourceCard: View {
    let label: LocalizedStringKey
    let use: JSFitStats.Use
    let unit: String

    var body: some View {
        let over = use.used > use.total + 1e-6
        let near = !over && use.total > 0 && use.total - use.used < use.total * 0.03
        let color = over ? C.bad : near ? C.warn : C.accent
        MetricCard(label: label) {
            Text(verbatim: "\(n1(use.used)) / \(n1(use.total)) \(unit)")
                .font(.mono(16, medium: true))
                .foregroundStyle(over ? C.bad : C.text)
        } sub: {
            VStack(alignment: .leading, spacing: 5) {
                ProgressLine(fraction: use.total > 0 ? use.used / use.total : (use.used > 0 ? 1 : 0), color: color)
                if over {
                    Text("short by \(n1(use.used - use.total)) \(unit)").foregroundStyle(C.bad)
                } else if near {
                    Text("\(n1(use.total - use.used)) \(unit) left").foregroundStyle(C.warn)
                } else {
                    Text("\(n1(use.total - use.used)) \(unit) free")
                }
            }
        }
    }
}

/// A labelled used / total bar (the desktop `Bar`).
private struct UsageBar: View {
    let attr: Int
    let label: LocalizedStringKey
    let use: JSFitStats.Use
    let unit: String
    var digits = 1

    var body: some View {
        let over = use.used > use.total + 1e-6
        let f: (Double) -> String = { digits == 0 ? n0($0) : n1($0) }
        VStack(spacing: 5) {
            HStack {
                IconLabel(attr: attr, text: Text(label))
                Spacer(minLength: 8)
                Text(verbatim: "\(f(use.used)) / \(f(use.total))\(unit)")
                    .font(.mono(13))
                    .foregroundStyle(over ? C.bad : C.text2)
            }
            ProgressLine(fraction: use.total > 0 ? use.used / use.total : (use.used > 0 ? 1 : 0), color: over ? C.bad : C.accent)
        }
    }
}

private struct ProgressLine: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(C.panel2)
                Rectangle().fill(color).frame(width: g.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 4)
    }
}

/// Volley split into EM / thermal / kinetic / explosive segments.
private struct DamageBar: View {
    let damage: [Double]

    var body: some View {
        let total = max(damage.reduce(0, +), 1e-9)
        GeometryReader { g in
            HStack(spacing: 1) {
                ForEach(0..<4, id: \.self) { i in
                    if damage[i] > 0 {
                        Rectangle().fill(damageColors[i]).frame(width: max(0, g.size.width * damage[i] / total - 1))
                    }
                }
            }
        }
    }
}

private struct IconLabel: View {
    let attr: Int?
    let text: Text

    var body: some View {
        HStack(spacing: 6) {
            if let attr {
                GameIcon.attribute(attr, size: 20)
            } else {
                Color.clear.frame(width: 20, height: 20)
            }
            text.font(.ui(14)).foregroundStyle(C.text2)
        }
    }
}

/// One defense layer: HP, the four resists with fill bars, EHP.
private struct LayerRow: View {
    let name: LocalizedStringKey
    let attr: Int
    let layer: JSFitStats.Layer

    static let nameWidth: CGFloat = 84
    static let ehpWidth: CGFloat = 50

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 5) {
                GameIcon.attribute(attr, size: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.ui(13)).foregroundStyle(C.text)
                    Text("\(n0(layer.hp)) HP").font(.mono(11)).foregroundStyle(C.muted)
                }
                .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(width: Self.nameWidth, alignment: .leading)
            ForEach(0..<4, id: \.self) { i in
                let r = i < layer.resist.count ? layer.resist[i] : 0
                ZStack(alignment: .leading) {
                    Rectangle().fill(damageColors[i].opacity(0.10))
                    GeometryReader { g in
                        Rectangle().fill(damageColors[i].opacity(0.35)).frame(width: g.size.width * min(1, max(0, r)))
                    }
                    Text(String(format: "%.1f%%", r * 100))
                        .font(.mono(12, medium: true))
                        .foregroundStyle(C.text)
                        .frame(maxWidth: .infinity)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 28)
            }
            Text(n0(layer.ehp))
                .font(.mono(12))
                .foregroundStyle(C.text2)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: Self.ehpWidth, alignment: .trailing)
        }
    }
}

private struct KVList<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 8) { content() }
    }
}

/// One label / value line of a section, with the game's icon (the desktop `KV`).
private struct KV: View {
    let attr: Int?
    let label: Text
    let value: Text
    var color: Color = C.text

    init(attr: Int?, label: Text, value: Text, color: Color = C.text) {
        self.attr = attr
        self.label = label
        self.value = value
        self.color = color
    }

    init(attr: Int?, label: LocalizedStringKey, value: Text, color: Color = C.text) {
        self.init(attr: attr, label: Text(label), value: value, color: color)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            IconLabel(attr: attr, text: label)
            Spacer(minLength: 8)
            value.font(.mono(13, medium: true)).foregroundStyle(color).multilineTextAlignment(.trailing)
        }
    }
}
