// Item info (the desktop's InfoPanel.tsx): a header with the picture, names, category and meta badges, the
// pilot's missing skills, then tabs — description with ship bonuses, attributes by category, what the item
// changes, the requirement tree, the skill, masteries, variations, industry, reprocessing and hub prices.
// Texts follow the app's language (Russian from the SDE when the phone is in Russian).

import SwiftUI
import Domain
import EVEStaticData
import EVEAuth

struct TypeDetailView: View {
    let typeId: Int
    let typeName: String
    @Environment(AppEnvironment.self) private var env
    @State private var info: TypeInfoBundle?
    @State private var error: Error?
    @State private var tab: Tab = {
        #if DEBUG
        if let t = UserDefaults.standard.string(forKey: "typeTab").flatMap(Tab.init(rawValue:)) { return t }
        #endif
        return .desc
    }()
    @State private var pilot: PilotSkills?
    @State private var linked: Int?

    enum Tab: String { case desc, attrs, effects, req, skill, mastery, vars, industry, reprocess, market }

    private static var russian: Bool { Locale.current.language.languageCode?.identifier == "ru" }

    var body: some View {
        ScrollView {
            if let b = info {
                VStack(alignment: .leading, spacing: 12) {
                    header(b)
                    if !b.requirements.isEmpty { MissingSkills(requirements: b.requirements, refs: b.refs, pilot: pilot) }
                    CanopusTabs(tabs: tabs(b), selection: $tab)
                    content(b)
                }
                .padding(16)
                .padding(.bottom, 40)
            } else if let error {
                EmptyState("Item not found", icon: "win_info") { Text(error.localizedDescription) }
            } else {
                ProgressView().tint(C.accent).padding(.top, 60).frame(maxWidth: .infinity)
            }
        }
        .background(C.bg)
        .navigationTitle(info?.name ?? typeName)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "canopus-type", let id = Int(url.host() ?? "") { linked = id; return .handled }
            return .systemAction
        })
        .navigationDestination(item: $linked) { id in TypeDetailView(typeId: id, typeName: "") }
        .task(id: typeId) { await load() }
    }

    private func load() async {
        guard let repo = env.repository else { return }
        do {
            info = try await repo.typeInfo(id: typeId, russian: Self.russian)
        } catch {
            if !error.isCancellation { self.error = error }
        }
        pilot = await PilotSkills.load(env)
    }

    private func tabs(_ b: TypeInfoBundle) -> [(id: Tab, label: String)] {
        var t: [(Tab, String)] = [(.desc, "Description")]
        if !b.attributes.isEmpty { t.append((.attrs, "Attributes")) }
        if !b.modifiers.isEmpty || b.boostsHullBonuses { t.append((.effects, "Effects")) }
        if !b.requirements.isEmpty { t.append((.req, "Requirements")) }
        if b.skill != nil { t.append((.skill, "Skill")) }
        if !b.masteries.isEmpty { t.append((.mastery, "Mastery")) }
        if !b.variations.isEmpty { t.append((.vars, "Variations")) }
        if b.producedBy != nil || b.blueprint != nil || !b.usedIn.isEmpty { t.append((.industry, "Industry")) }
        if !b.reprocess.isEmpty { t.append((.reprocess, "Reprocessing")) }
        if b.marketGroupId != nil { t.append((.market, "Market")) }
        return t.map { (id: $0.0, label: $0.1) }
    }

    // MARK: Header

    private func header(_ b: TypeInfoBundle) -> some View {
        let isShip = b.categoryId == 6
        return HStack(alignment: .top, spacing: 12) {
            if isShip { EVERenderImage(typeId: b.typeId, size: 112).clipShape(EVECut()) } else { EVETypeIcon(typeId: b.typeId, size: 64) }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: b.name).font(.display(20)).foregroundStyle(C.text).fixedSize(horizontal: false, vertical: true)
                if let en = b.englishName { Text(verbatim: en).font(.ui(12)).foregroundStyle(C.muted) }
                Text(verbatim: "\(b.categoryName) › \(b.groupName)").font(.ui(13)).foregroundStyle(C.muted)
                FlowRow(spacing: 5) {
                    if let m = b.metaGroup { Pill(text: m, color: C.accent) }
                    if let ml = b.metaLevel, ml > 0 { Pill(text: String(localized: "Meta \(ml)"), color: C.text2) }
                    if let r = b.race { Pill(text: r, color: C.text2) }
                    if let f = b.faction { Pill(text: f, color: C.text2) }
                    if !b.published { Pill(text: String(localized: "not published"), color: C.muted) }
                }
            }
            Spacer(minLength: 0)
        }
        .canopusSurface(padding: 12)
    }

    @ViewBuilder private func content(_ b: TypeInfoBundle) -> some View {
        let current = tabs(b).contains { $0.id == tab } ? tab : .desc
        switch current {
        case .desc: DescriptionTab(b: b)
        case .attrs: AttributesTab(b: b)
        case .effects: EffectsTab(b: b)
        case .req: Card { RequirementTree(nodes: b.requirements, refs: b.refs, pilot: pilot, depth: 0) }
        case .skill: SkillTab(b: b, pilot: pilot)
        case .mastery: MasteryTab(b: b, pilot: pilot)
        case .vars: VariationsTab(b: b)
        case .industry: IndustryTab(b: b)
        case .reprocess: ReprocessTab(b: b)
        case .market: MarketTab(typeId: b.typeId)
        }
    }
}

// MARK: - The pilot's skills (for requirement checks and training times)

struct PilotSkills {
    let levels: [Int: Int]
    let sp: [Int: Int]
    let attributes: [Int: Double]?

    func level(_ skill: Int) -> Int { levels[skill] ?? 0 }

    /// SP per minute for a skill's attributes.
    func rate(primary: Int, secondary: Int) -> Double {
        guard let a = attributes else { return 0 }
        return (a[primary] ?? 0) + (a[secondary] ?? 0) / 2
    }

    /// Seconds to train a skill to `level` from where the pilot is.
    func seconds(rank: Double, level: Int, skill: Int, primary: Int, secondary: Int) -> Double {
        let r = rate(primary: primary, secondary: secondary)
        guard r > 0 else { return 0 }
        let need = max(0, TrainingAttributes.spForLevel(rank: rank, level: level) - Double(sp[skill] ?? 0))
        return need / r * 60
    }

    @MainActor
    static func load(_ env: AppEnvironment) async -> PilotSkills? {
        guard let svc = env.characterStore.selectedService, let repo = env.repository,
              let skills = try? await svc.skills() else { return nil }
        let attrs = await TrainingAttributes.resolve(
            esi: try? await svc.characterAttributes(), queue: (try? await svc.skillQueue()) ?? [],
            implants: (try? await svc.implants()) ?? [], repo: repo)
        return PilotSkills(
            levels: Dictionary(uniqueKeysWithValues: skills.skills.map { ($0.skillId, $0.activeSkillLevel) }),
            sp: Dictionary(uniqueKeysWithValues: skills.skills.map { ($0.skillId, $0.skillpointsInSkill) }),
            attributes: attrs)
    }
}

private let roman = ["0", "I", "II", "III", "IV", "V"]
private func n(_ v: Double, _ digits: Int = 2) -> String { v.formatted(.number.precision(.fractionLength(0...digits))) }

/// A type name that opens its own info.
private struct TypeLink: View {
    let id: Int
    let name: String
    var icon = true

    var body: some View {
        NavigationLink { TypeDetailView(typeId: id, typeName: name) } label: {
            HStack(spacing: 6) {
                if icon { EVETypeIcon(typeId: id, size: 20) }
                Text(verbatim: name).font(.ui(13)).foregroundStyle(C.accentText).multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.plain)
    }
}

private func refName(_ b: TypeInfoBundle, _ id: Int) -> String { b.refs[id]?.name ?? "#\(id)" }

// MARK: - Missing skills

private struct MissingSkills: View {
    let requirements: [TypeInfoBundle.Requirement]
    let refs: [Int: TypeInfoBundle.Ref]
    let pilot: PilotSkills?

    var body: some View {
        // The deepest requirement on each skill.
        var need: [Int: TypeInfoBundle.Requirement] = [:]
        func walk(_ n: [TypeInfoBundle.Requirement]) { for r in n { if (need[r.skill]?.level ?? 0) < r.level { need[r.skill] = r }; walk(r.children) } }
        walk(requirements)
        return Group {
            if let pilot {
                let missing = need.values.filter { pilot.level($0.skill) < $0.level }.sorted { (refs[$0.skill]?.name ?? "") < (refs[$1.skill]?.name ?? "") }
                if missing.isEmpty {
                    Text("✔ Usage: every skill trained").font(.ui(13)).foregroundStyle(C.good)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        .background(C.good.opacity(0.1), in: EVECut())
                } else {
                    let times = missing.map { r in (r, missingTime(r)) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("✖ Missing skills: \(missing.count) · train in \(Fmt.duration(seconds: times.reduce(0) { $0 + $1.1 }))").font(.ui(13, .medium))
                        ForEach(times, id: \.0.skill) { r, s in
                            Text("\(refs[r.skill]?.name ?? "#\(r.skill)") \(roman[r.level]) (now \(pilot.level(r.skill) > 0 ? roman[pilot.level(r.skill)] : String(localized: "none"))) · \(Fmt.duration(seconds: s))")
                                .font(.ui(12)).foregroundStyle(C.text2)
                        }
                    }
                    .foregroundStyle(C.bad)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    .background(C.badFill.opacity(0.1), in: EVECut())
                }
            } else {
                Text("Sign in with a character to compare with your skills.").font(.ui(12)).foregroundStyle(C.muted)
            }
        }
    }

    /// Every level from the pilot's to the needed one.
    private func missingTime(_ r: TypeInfoBundle.Requirement) -> Double {
        guard let pilot else { return 0 }
        return pilot.seconds(rank: r.rank, level: r.level, skill: r.skill, primary: r.primary, secondary: r.secondary)
    }
}

// MARK: - Description

/// EVE's description markup as text: <a href=showinfo:ID> links open the item, <b>, <i>, <u>, <br>, URLs.
private struct RichText: View {
    let text: String

    var body: some View {
        Text(Self.attributed(text)).font(.ui(14)).foregroundStyle(C.text2).tint(C.accentText)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    static func attributed(_ raw: String) -> AttributedString {
        var out = AttributedString()
        var bold = 0, italic = 0, underline = 0
        var link: URL?
        let re = try! NSRegularExpression(pattern: #"<\s*(/?)\s*([a-zA-Z]+)([^>]*)>|\r?\n"#)
        let ns = raw as NSString
        var last = 0
        func push(_ s: String) {
            guard !s.isEmpty else { return }
            let clean = s.replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            var a = AttributedString(clean)
            var intent: InlinePresentationIntent = []
            if bold > 0 { intent.insert(.stronglyEmphasized) }
            if italic > 0 { intent.insert(.emphasized) }
            if !intent.isEmpty { a.inlinePresentationIntent = intent }
            if underline > 0 { a.underlineStyle = .single }
            if let link { a.link = link }
            out += a
        }
        for m in re.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
            push(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
            if m.range(at: 2).location == NSNotFound { out += AttributedString("\n"); continue }
            let closing = ns.substring(with: m.range(at: 1)) == "/"
            let tag = ns.substring(with: m.range(at: 2)).lowercased()
            let attr = ns.substring(with: m.range(at: 3))
            switch tag {
            case "br": out += AttributedString("\n")
            case "b", "strong": bold += closing ? -1 : 1
            case "i", "em": italic += closing ? -1 : 1
            case "u": underline += closing ? -1 : 1
            case "a", "url":
                if closing { link = nil } else if let r = attr.range(of: #"showinfo:(\d+)"#, options: .regularExpression) {
                    link = URL(string: "canopus-type://\(attr[r].dropFirst("showinfo:".count))")
                } else if let r = attr.range(of: #"https?://[^\s"'>]+"#, options: .regularExpression) {
                    link = URL(string: String(attr[r]))
                }
            default: break
            }
        }
        push(ns.substring(from: last))
        return out
    }
}

private struct DescriptionTab: View {
    let b: TypeInfoBundle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let d = b.description, !d.isEmpty { RichText(text: d) } else { Text("No description.").font(.ui(13)).foregroundStyle(C.muted) }
            if let t = b.traits, !(t.bySkill.isEmpty && t.role.isEmpty) {
                Card("Traits") {
                    ForEach(t.bySkill, id: \.skill) { s in
                        VStack(alignment: .leading, spacing: 4) {
                            (Text("Bonuses per level of ") + Text(verbatim: refName(b, s.skill)).foregroundColor(C.accentText) + Text(verbatim: ":"))
                                .font(.ui(13, .medium)).foregroundStyle(C.text)
                            ForEach(Array(s.bonuses.enumerated()), id: \.offset) { _, x in bonus(x) }
                        }
                    }
                    if !t.role.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Role bonuses:").font(.ui(13, .medium)).foregroundStyle(C.text)
                            ForEach(Array(t.role.enumerated()), id: \.offset) { _, x in bonus(x) }
                        }
                    }
                }
            }
            Card {
                if !b.marketPath.isEmpty { kv("Market", b.marketPath.joined(separator: " › ")) }
                if let v = b.volume {
                    kv("Volume", "\(n(v, 3)) m³" + ((b.packagedVolume.map { $0 != v } ?? false) ? String(localized: " (packaged \(n(b.packagedVolume!, 3)) m³)") : ""))
                }
                if let m = b.mass, m > 0 { kv("Mass", "\(n(m, 0)) kg") }
                if let c = b.capacity, c > 0 { kv("Capacity", "\(n(c, 3)) m³") }
                if let p = b.portionSize, p > 1 { kv("Portion size", "\(p)") }
                if let p = b.basePrice, p > 0 { kv("Base price", Fmt.isk(p, compact: false)) }
                kv("type_id", "\(b.typeId)")
            }
        }
    }

    private func bonus(_ x: TypeInfoBundle.Bonus) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(verbatim: "•").foregroundStyle(C.muted)
            if let v = x.value {
                Text(verbatim: n(v) + (x.unit == 105 ? "%" : "")).font(.ui(13, .bold)).foregroundStyle(C.text)
            }
            RichText(text: x.text)
        }
    }

    private func kv(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.ui(13)).foregroundStyle(C.muted)
            Spacer(minLength: 12)
            Text(verbatim: value).font(.mono(12)).foregroundStyle(C.text).multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Attributes

/// The desktop's CATEGORY_RU, as English keys translated in the catalog.
private let attributeCategoryKey: [String: String] = [
    "Fitting": "Fitting capabilities", "Shield": "Shields", "Armor": "Armor", "Structure": "Structure", "Capacitor": "Capacitor",
    "Targeting": "Targeting", "Miscellaneous": "Miscellaneous", "Required Skills": "Required Skills", "Speed and Travel": "Speed and Travel",
    "EW - Resistance": "EW - Resistance", "EW - Target Painting": "EW - Target Painting", "EW - Energy Neutralizing": "EW - Energy Neutralizing",
    "EW - Remote Electronic Counter Measures": "EW - Remote Electronic Counter Measures", "EW - Remote Sensor Dampening": "EW - Remote Sensor Dampening",
    "EW - Tracking Disruption": "EW - Tracking Disruption", "EW - Stasis Webbing": "EW - Stasis Webbing", "EW - Warp Scrambling": "EW - Warp Scrambling",
    "Electronic Resistances": "Electronic Resistances", "Drones": "Drones", "Fighter": "Fighter", "Fighter Abilities": "Fighter Abilities",
    "AI": "AI", "Loot": "Loot", "Graphics": "Graphics", "Other": "Other", "Turret": "Turret", "Missile": "Missile", "NULL": "Other",
    "Bonuses": "Bonuses", "Special Structure Attributes": "Special Structure Attributes",
]

private struct AttributesTab: View {
    let b: TypeInfoBundle

    var body: some View {
        let groups = Dictionary(grouping: b.attributes, by: \.category)
        let order = b.attributes.map(\.category).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        VStack(alignment: .leading, spacing: 12) {
            ForEach(order, id: \.self) { cat in
                Card(String(localized: String.LocalizationValue(attributeCategoryKey[cat] ?? cat))) {
                    ForEach(groups[cat] ?? []) { a in
                        HStack(alignment: .center, spacing: 8) {
                            if let icon = a.iconId { EVEIconImage(iconId: icon, size: 22) } else { Color.clear.frame(width: 22, height: 22) }
                            Text(verbatim: a.name).font(.ui(13)).foregroundStyle(C.text2)
                            Spacer(minLength: 8)
                            value(a)
                        }
                        .help(a.tooltip ?? "")
                    }
                }
            }
        }
    }

    @ViewBuilder private func value(_ a: TypeInfoBundle.Attribute) -> some View {
        let v = Int(a.value)
        switch a.unit {
        case 116: TypeLink(id: v, name: refName(b, v), icon: false)
        case 115: Text(verbatim: b.groupNames[v] ?? "\(v)").font(.mono(12, medium: true)).foregroundStyle(C.text)
        case 119: Text(verbatim: b.attributeNames[v] ?? "\(v)").font(.mono(12, medium: true)).foregroundStyle(C.text)
        default:
            if (a.id == 180 || a.id == 181), let name = characterAttributeName[v] {
                Text(name).font(.mono(12, medium: true)).foregroundStyle(C.text)
            } else {
                Text(verbatim: formatValue(a.value, unit: a.unit, unitName: a.unitName)).font(.mono(12, medium: true)).foregroundStyle(C.text)
            }
        }
    }
}

private let characterAttributeName: [Int: LocalizedStringKey] = [164: "Charisma", 165: "Intelligence", 166: "Memory", 167: "Perception", 168: "Willpower"]

/// A dogma value with its unit, as the desktop's formatValue.
private func formatValue(_ value: Double, unit: Int?, unitName: String?) -> String {
    switch unit {
    case 101: return String(localized: "\(n(value / 1000)) s")
    case 108: return "\(n((1 - value) * 100)) %"
    case 109: return "\(value >= 1 ? "+" : "")\(n((value - 1) * 100)) %"
    case 111: return "\(n((1 - value) * 100)) %"
    case 127: return "\(n(value * 100)) %"
    case 104: return "\(n(value))x"
    case 137: return value != 0 ? String(localized: "Yes") : String(localized: "No")
    case 139: return "\(value > 0 ? "+" : "")\(n(value))"
    case 140: return String(localized: "Level \(n(value))")
    case 117:
        let sizes = [1: String(localized: "Small"), 2: String(localized: "Medium"), 3: String(localized: "Large"), 4: String(localized: "X-Large")]
        return sizes[Int(value)] ?? n(value)
    case 142: return [1: String(localized: "Male"), 2: String(localized: "Any"), 3: String(localized: "Female")][Int(value)] ?? n(value)
    case 1: return value >= 10_000 ? String(localized: "\(n(value / 1000)) km") : String(localized: "\(n(value)) m")
    default: return n(value) + ((unitName?.isEmpty ?? true) ? "" : " \(unitName!)")
    }
}

// MARK: - Effects (what the item changes)

private struct EffectsTab: View {
    let b: TypeInfoBundle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if b.boostsHullBonuses {
                Text("Each level of this skill strengthens the hull bonuses of the ships that need it. The bonuses are in the ships' descriptions, under Traits.")
                    .font(.ui(13)).foregroundStyle(C.text2)
            }
            ForEach(TypeInfoBundle.ModifierState.allCases, id: \.self) { state in
                let list = b.modifiers.filter { $0.state == state }
                if !list.isEmpty {
                    Card(title(state)) {
                        ForEach(Array(list.enumerated()), id: \.offset) { _, m in row(m) }
                    }
                }
            }
            if b.modifiers.isEmpty && !b.boostsHullBonuses {
                Text("This item changes nothing.").font(.ui(13)).foregroundStyle(C.muted)
            }
        }
    }

    private func title(_ s: TypeInfoBundle.ModifierState) -> String {
        switch s {
        case .passive: String(localized: "Always")
        case .online: String(localized: "While the module is online")
        case .active: String(localized: "When activated")
        case .overload: String(localized: "When overheated")
        }
    }

    private func row(_ m: TypeInfoBundle.Modifier) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            target(m).font(.ui(11)).foregroundStyle(C.muted)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let icon = m.attrIconId { EVEIconImage(iconId: icon, size: 20) }
                Text(verbatim: m.attrName).font(.ui(13)).foregroundStyle(C.text2)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(verbatim: change(m)).font(.mono(12, medium: true)).foregroundStyle(color(m))
                    if let note = m.note { Text(LocalizedStringKey(note)).font(.ui(10)).foregroundStyle(C.muted) }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func target(_ m: TypeInfoBundle.Modifier) -> Text {
        switch m.target {
        case .me: Text("This item")
        case .ship: Text("Ship")
        case .char: Text("Pilot")
        case .other: Text(b.categoryId == 8 ? "Weapons with this charge" : "Charge in the module")
        case .location: Text("Every module on the ship")
        case .group: Text("Modules of the group \(b.groupNames[m.group ?? 0] ?? "\(m.group ?? 0)")")
        case .selfSkill: Text("Everything that needs this skill")
        case .skill: m.skill == b.typeId ? Text("Everything that needs this skill") : Text("Everything that needs \(refName(b, m.skill ?? 0))")
        }
    }

    /// "+5%", "×0.89 (−11%)", "+1" … — resonances are shown as resistance gained.
    private func change(_ m: TypeInfoBundle.Modifier) -> String {
        let perLevel = m.perLevel ? String(localized: " per level") : ""
        let unit = (m.unitName != nil && ![115, 116, 119, 137].contains(m.unit ?? 0)) ? m.unitName! : ""
        let withUnit = { (v: String) in !unit.isEmpty && unit != "%" ? "\(v) \(unit)" : v }
        let resonance = m.unit == 108
        switch m.op {
        case 6:
            if resonance { return String(localized: "\(m.value < 0 ? "+" : "−")\(n(abs(m.value)))% resistance") + perLevel }
            return "\(m.value > 0 ? "+" : "")\(n(m.value))%" + perLevel
        case 0, 4:
            if resonance { return String(localized: "\(m.value <= 1 ? "+" : "−")\(n(abs(1 - m.value) * 100))% resistance") }
            let pct = (m.value - 1) * 100
            return "×\(n(m.value))" + (abs(pct) >= 0.01 ? " (\(pct > 0 ? "+" : "−")\(n(abs(pct)))%)" : "") + perLevel
        case 1, 5: return "÷\(n(m.value))"
        case 2: return withUnit("\(m.value < 0 ? "−" : "+")\(n(abs(m.value)))") + perLevel
        case 3: return withUnit("−\(n(m.value))") + perLevel
        default: return withUnit("= \(n(m.value))")
        }
    }

    /// Green for changes that help, red for penalties (MWD signature bloom, reduced speed…).
    private func color(_ m: TypeInfoBundle.Modifier) -> Color {
        let increases: Bool?
        switch m.op {
        case 6: increases = m.value > 0
        case 0, 4: increases = m.value > 1
        case 2: increases = m.value > 0
        case 3: increases = m.value < 0
        default: increases = nil
        }
        guard let increases else { return C.text }
        let lowerIsBetter = m.unit == 108 || [51, 73, 552, 4, 6, 50, 30, 1153, 654, 55, 479, 70].contains(m.attr)
        return increases != lowerIsBetter ? C.good : C.bad
    }
}

// MARK: - Requirements

private struct RequirementTree: View {
    let nodes: [TypeInfoBundle.Requirement]
    let refs: [Int: TypeInfoBundle.Ref]
    let pilot: PilotSkills?
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(nodes) { r in
                let have = pilot?.level(r.skill) ?? 0
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if pilot != nil {
                            Text(verbatim: have >= r.level ? "✔" : "✖").font(.ui(12, .bold)).foregroundStyle(have >= r.level ? C.good : C.bad)
                        }
                        TypeLink(id: r.skill, name: refs[r.skill]?.name ?? "#\(r.skill)", icon: false)
                        Text(verbatim: roman[min(5, r.level)]).font(.ui(12, .bold)).foregroundStyle(C.text)
                        if let pilot {
                            LevelPips(level: have)
                            if have < r.level {
                                Text(Fmt.duration(seconds: pilot.seconds(rank: r.rank, level: r.level, skill: r.skill, primary: r.primary, secondary: r.secondary)))
                                    .font(.ui(11)).foregroundStyle(C.muted)
                            }
                        }
                    }
                    if !r.children.isEmpty {
                        RequirementTree(nodes: r.children, refs: refs, pilot: pilot, depth: depth + 1)
                            .padding(.leading, 16)
                            .overlay(alignment: .leading) { Rectangle().fill(C.border).frame(width: 1).padding(.leading, 5) }
                    }
                }
            }
        }
    }
}

// MARK: - Skill

private struct SkillTab: View {
    let b: TypeInfoBundle
    let pilot: PilotSkills?

    var body: some View {
        let s = b.skill!
        let have = pilot?.level(b.typeId) ?? 0
        let rate = pilot?.rate(primary: s.primary, secondary: s.secondary) ?? 0
        VStack(alignment: .leading, spacing: 12) {
            Card {
                kv("Rank (multiplier)", Text(verbatim: "\(n(s.rank))x"))
                kv("Primary attribute", characterAttributeName[s.primary].map { Text($0) } ?? Text(verbatim: "—"))
                kv("Secondary attribute", characterAttributeName[s.secondary].map { Text($0) } ?? Text(verbatim: "—"))
                if rate > 0 { kv("Your speed", Text("\(n(rate * 60, 0)) SP/hour")) }
                if let pilot { kv("Your level", Text(verbatim: "\(roman[have]) · \((pilot.sp[b.typeId] ?? 0).formatted()) SP")) }
            }
            Card("Levels") {
                ForEach(1...5, id: \.self) { l in
                    HStack {
                        Text(verbatim: roman[l] + (have >= l ? " ✔" : "")).font(.ui(13)).foregroundStyle(have >= l ? C.good : C.text)
                        Spacer()
                        Text(verbatim: Int(TrainingAttributes.spForLevel(rank: s.rank, level: l)).formatted()).font(.mono(12)).foregroundStyle(C.text2)
                        if rate > 0 {
                            Text(have >= l ? "—" : Fmt.duration(seconds: pilot!.seconds(rank: s.rank, level: l, skill: b.typeId, primary: s.primary, secondary: s.secondary)))
                                .font(.mono(12)).foregroundStyle(C.muted).frame(width: 90, alignment: .trailing)
                        }
                    }
                }
            }
            if !b.requiredFor.isEmpty {
                Card("Unlocks") {
                    ForEach(b.requiredFor, id: \.level) { g in
                        DisclosureGroup {
                            ForEach(g.types.sorted { refName(b, $0) < refName(b, $1) }, id: \.self) { TypeLink(id: $0, name: refName(b, $0)) }
                        } label: {
                            Text("Level \(roman[g.level]) (\(g.types.count))").font(.ui(13, .medium)).foregroundStyle(C.text)
                        }
                        .tint(C.muted)
                    }
                }
            }
        }
    }

    private func kv(_ label: LocalizedStringKey, _ value: Text) -> some View {
        HStack {
            Text(label).font(.ui(13)).foregroundStyle(C.muted)
            Spacer()
            value.font(.ui(13, .medium)).foregroundStyle(C.text)
        }
    }
}

// MARK: - Mastery

private struct MasteryTab: View {
    let b: TypeInfoBundle
    let pilot: PilotSkills?

    var body: some View {
        let met = { (skills: [(skill: Int, level: Int)]) in skills.allSatisfy { (pilot?.level($0.skill) ?? 0) >= $0.level } }
        let achieved = pilot.map { _ in b.masteries.filter { $0.certificates.allSatisfy { met($0.skills) } }.count }
        VStack(alignment: .leading, spacing: 10) {
            if let achieved {
                Text("Your mastery level: \(achieved > 0 ? roman[achieved] : String(localized: "none"))").font(.ui(14, .medium)).foregroundStyle(C.text)
            }
            ForEach(b.masteries, id: \.level) { level in
                let done = pilot != nil && level.certificates.allSatisfy { met($0.skills) }
                DisclosureGroup {
                    ForEach(level.certificates) { c in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                if pilot != nil { Text(verbatim: met(c.skills) ? "✔" : "✖").foregroundStyle(met(c.skills) ? C.good : C.bad) }
                                Text(verbatim: c.name).font(.ui(13, .medium)).foregroundStyle(C.text)
                            }
                            ForEach(c.skills, id: \.skill) { s in
                                HStack(spacing: 5) {
                                    if let pilot { Text(verbatim: pilot.level(s.skill) >= s.level ? "✔" : "✖").font(.ui(11)).foregroundStyle(pilot.level(s.skill) >= s.level ? C.good : C.bad) }
                                    TypeLink(id: s.skill, name: refName(b, s.skill), icon: false)
                                    Text(verbatim: roman[s.level]).font(.ui(12, .bold)).foregroundStyle(C.text)
                                }
                                .padding(.leading, 14)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } label: {
                    HStack(spacing: 6) {
                        if pilot != nil { Text(verbatim: done ? "✔" : "✖").foregroundStyle(done ? C.good : C.bad) }
                        Text("Mastery \(roman[level.level])").font(.ui(14, .medium)).foregroundStyle(C.text)
                    }
                }
                .tint(C.muted)
                .canopusSurface(padding: 10)
            }
        }
    }
}

// MARK: - Variations, industry, reprocessing, market

private struct VariationsTab: View {
    let b: TypeInfoBundle

    var body: some View {
        Card {
            ForEach(b.variations, id: \.self) { id in
                HStack {
                    if id == b.typeId {
                        HStack(spacing: 6) { EVETypeIcon(typeId: id, size: 20); Text(verbatim: refName(b, id)).font(.ui(13, .semibold)).foregroundStyle(C.text) }
                    } else {
                        TypeLink(id: id, name: refName(b, id))
                    }
                    Spacer()
                    Text(verbatim: EVETypeMetaPresentation.title(for: b.refs[id]?.metaGroupId)).font(.ui(11)).foregroundStyle(C.muted)
                }
            }
        }
    }
}

private func activityName(_ a: String) -> String {
    switch a {
    case "manufacturing": String(localized: "Manufacturing")
    case "reaction": String(localized: "Reaction")
    case "invention": String(localized: "Invention")
    case "copying": String(localized: "Copying")
    case "research_material": String(localized: "ME research")
    case "research_time": String(localized: "TE research")
    default: a
    }
}

private struct ActivityBlock: View {
    let b: TypeInfoBundle
    let a: TypeInfoBundle.Activity
    var maxRuns: Int?

    var body: some View {
        Card(activityName(a.name) + " · " + Fmt.duration(seconds: Double(a.time)) + (maxRuns.map { String(localized: " · max runs \($0)") } ?? "")) {
            if !a.products.isEmpty {
                Text("Result").font(.ui(11, .medium)).textCase(.uppercase).foregroundStyle(C.muted)
                ForEach(a.products, id: \.type) { p in
                    HStack {
                        TypeLink(id: p.type, name: refName(b, p.type))
                        Spacer()
                        Text(verbatim: "×\(p.qty)" + (p.probability.map { " (\(Int(($0 * 100).rounded()))%)" } ?? "")).font(.mono(12)).foregroundStyle(C.text2)
                    }
                }
            }
            if !a.materials.isEmpty {
                Text("Materials").font(.ui(11, .medium)).textCase(.uppercase).foregroundStyle(C.muted)
                ForEach(a.materials, id: \.type) { m in
                    HStack { TypeLink(id: m.type, name: refName(b, m.type)); Spacer(); Text(verbatim: m.qty.formatted()).font(.mono(12)).foregroundStyle(C.text2) }
                }
            }
            if !a.skills.isEmpty {
                Text("Skills").font(.ui(11, .medium)).textCase(.uppercase).foregroundStyle(C.muted)
                ForEach(a.skills, id: \.skill) { s in
                    HStack { TypeLink(id: s.skill, name: refName(b, s.skill), icon: false); Text(verbatim: roman[min(5, s.level)]).font(.ui(12, .bold)) }
                }
            }
        }
    }
}

private struct IndustryTab: View {
    let b: TypeInfoBundle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let p = b.producedBy {
                HStack(spacing: 4) {
                    Text("Made from the blueprint").font(.ui(13)).foregroundStyle(C.text2)
                    TypeLink(id: p.blueprint, name: refName(b, p.blueprint), icon: false)
                }
                ActivityBlock(b: b, a: p.activity, maxRuns: p.maxRuns)
            }
            if let bp = b.blueprint {
                ForEach(Array(bp.activities.enumerated()), id: \.offset) { _, a in
                    ActivityBlock(b: b, a: a, maxRuns: a.name == "manufacturing" ? bp.maxRuns : nil)
                }
            }
            if !b.usedIn.isEmpty {
                Card(String(localized: "Used in production (\(b.usedIn.count))")) {
                    ForEach(Array(b.usedIn.enumerated()), id: \.offset) { _, u in
                        HStack {
                            TypeLink(id: u.product, name: refName(b, u.product))
                            Spacer()
                            Text(verbatim: activityName(u.activity)).font(.ui(11)).foregroundStyle(C.muted)
                            Text(verbatim: "×\(u.qty.formatted())").font(.mono(12)).foregroundStyle(C.text2)
                        }
                    }
                }
            }
        }
    }
}

private struct ReprocessTab: View {
    let b: TypeInfoBundle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text((b.portionSize ?? 1) > 1 ? String(localized: "Yield at 100% reprocessing efficiency from \(b.portionSize!) units.") : String(localized: "Yield at 100% reprocessing efficiency."))
                .font(.ui(12)).foregroundStyle(C.muted)
            Card {
                ForEach(b.reprocess, id: \.type) { r in
                    HStack { TypeLink(id: r.type, name: refName(b, r.type)); Spacer(); Text(verbatim: r.qty.formatted()).font(.mono(12)).foregroundStyle(C.text2) }
                }
            }
        }
    }
}

private struct MarketTab: View {
    let typeId: Int
    @State private var rows: [(hub: String, sell: Double?, buy: Double?)]?

    private static let hubs: [(String, Int)] = [("Jita", 60003760), ("Amarr", 60008494), ("Dodixie", 60011866), ("Rens", 60004588), ("Hek", 60005686)]

    var body: some View {
        Card {
            HStack {
                Text("Hub").frame(maxWidth: .infinity, alignment: .leading)
                Text("Sell").frame(width: 110, alignment: .trailing)
                Text("Buy").frame(width: 110, alignment: .trailing)
            }
            .font(.ui(11, .medium)).foregroundStyle(C.muted)
            if let rows {
                ForEach(rows, id: \.hub) { r in
                    HStack {
                        Text(verbatim: r.hub).font(.ui(13)).foregroundStyle(C.text).frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: r.sell.map { Fmt.isk($0) } ?? "—").frame(width: 110, alignment: .trailing)
                        Text(verbatim: r.buy.map { Fmt.isk($0) } ?? "—").frame(width: 110, alignment: .trailing)
                    }
                    .font(.mono(12)).foregroundStyle(C.text2)
                }
            } else {
                ProgressView().tint(C.accent)
            }
        }
        .task {
            var out: [(String, Double?, Double?)] = []
            for (hub, station) in Self.hubs {
                let p = try? await HubPrices.prices(station: station, typeIds: [typeId])[typeId]
                out.append((hub, p?.sell, p?.buy))
            }
            rows = out.map { (hub: $0.0, sell: $0.1, buy: $0.2) }
        }
    }
}

/// Lays its children out in rows, wrapping like text.
private struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(width, maxX), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
