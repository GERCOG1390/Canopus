// Reprocessing calculator: paste items (ore, ice, moon ore, modules, loot), pick where you reprocess and
// get the minerals with the yield the game gives, valued at Jita against selling the items as they are.
// Ore (EVE University): (50 + rig) × (1 + security, rigged only) × (1 + structure) × (1 + 3 % Reprocessing)
// × (1 + 2 % Reprocessing Efficiency) × (1 + 2 % ore skill) × (1 + implant); in an NPC station the base
// is the station's 30–50 % with no rig, security or structure terms. Scrapmetal (modules, ships, loot):
// base × (1 + 2 % Scrapmetal Processing), nothing else applies.

import SwiftUI
import Domain
import EVEAuth
import EVEStaticData

private let reprocessingSkill = 3385
private let efficiencySkill = 3389
private let scrapmetalSkill = 12196

private enum Facility: String, CaseIterable, Hashable {
    case station, citadel, athanor, tatara

    var label: String {
        switch self {
        case .station: String(localized: "NPC station")
        case .citadel: String(localized: "Citadel / engineering complex")
        case .athanor: "Athanor"
        case .tatara: "Tatara"
        }
    }

    /// Structure modifier (Sm)
    var structureBonus: Double {
        switch self {
        case .athanor: 0.02
        case .tatara: 0.055
        default: 0
        }
    }
}

private enum Space: String, CaseIterable, Hashable {
    case high, low, null

    var label: String {
        switch self {
        case .high: String(localized: "Highsec")
        case .low: String(localized: "Lowsec")
        case .null: String(localized: "Nullsec / W-space")
        }
    }

    var bonus: Double {
        switch self {
        case .high: 0
        case .low: 0.06
        case .null: 0.12
        }
    }
}

struct ReprocessingCalc: View {
    @Environment(AppEnvironment.self) private var env
    @State private var text = ""
    @State private var facility: Facility = .station
    @State private var stationBase = 50.0
    @State private var rig = 0
    @State private var space: Space = .high
    @State private var implant = 0
    @State private var tax = 0.0
    @State private var allFive = false
    @State private var sellBasis = true
    @State private var pilotSkills: [Int: Int] = [:]

    private struct Line: Identifiable {
        let id: Int
        let type: ItemType
        let qty: Int
        let info: ReprocessInfo?
    }

    @State private var lines: [Line] = []
    @State private var notFound: [String] = []
    @State private var prices: [Int: HubPrice] = [:]
    @State private var names: [Int: String] = [:]
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card(String(localized: "Reprocessing")) {
                TextEditor(text: $text)
                    .font(.mono(12)).scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .padding(6).background(C.panel2, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Copy from the inventory (Ctrl+A, Ctrl+C) or type one per line: Veldspar 10000 · 5 x Hobgoblin I")
                                .font(.ui(12)).foregroundStyle(C.faint).padding(12).allowsHitTesting(false)
                        }
                    }
                settings
                Button(working ? String(localized: "Calculating…") : String(localized: "Calculate")) { Task { await calculate() } }
                    .buttonStyle(CanopusButtonStyle(kind: .primary)).disabled(working || text.isEmpty)
            }
            if !notFound.isEmpty {
                Text("Not recognised: \(notFound.joined(separator: ", "))").font(.ui(12)).foregroundStyle(C.warn)
            }
            if !lines.isEmpty { result }
        }
        #if DEBUG
        // Debug builds: `-reprocessText "Veldspar 10000|Hobgoblin I 5"` fills the list and calculates,
        // `-reprocessAllV YES` with every skill at V.
        .task(id: env.repositoryVersion) {
            if let t = UserDefaults.standard.string(forKey: "reprocessText"), text.isEmpty, env.repository != nil {
                allFive = UserDefaults.standard.bool(forKey: "reprocessAllV")
                text = t.replacingOccurrences(of: "|", with: "\n")
                await calculate()
            }
        }
        #endif
        .task(id: env.dataKey) {
            if let skills = try? await env.characterStore.selectedService?.skills() {
                pilotSkills = Dictionary(skills.skills.map { ($0.skillId, $0.activeSkillLevel) }, uniquingKeysWith: { a, _ in a })
            }
        }
    }

    // MARK: Settings

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            chips(Facility.allCases.map { ($0, $0.label) }, selection: $facility)
            if facility == .station {
                FlowRow(spacing: 10) {
                    NumberField(label: "Station base yield, %", value: $stationBase)
                    NumberField(label: "Station tax, %", value: $tax)
                }
            } else {
                HStack(spacing: 6) {
                    Text("Rig").font(.ui(11)).foregroundStyle(C.muted)
                    chips([(0, String(localized: "None")), (1, "T1"), (3, "T2")], selection: $rig)
                }
                if rig > 0 { chips(Space.allCases.map { ($0, $0.label) }, selection: $space) }
                NumberField(label: "Structure tax, %", value: $tax)
            }
            HStack(spacing: 6) {
                Text("Implant").font(.ui(11)).foregroundStyle(C.muted)
                chips([(0, String(localized: "None")), (1, "RX-801"), (2, "RX-802"), (4, "RX-804")], selection: $implant)
            }
            HStack(spacing: 6) {
                Button(allFive ? "✓ All skills V" : "All skills V") { allFive.toggle() }
                    .buttonStyle(CanopusButtonStyle(kind: allFive ? .primary : .ghost, small: true))
                if !allFive, env.characterStore.selectedService == nil {
                    Text("No character: skills at 0").font(.ui(11)).foregroundStyle(C.muted)
                }
                Spacer(minLength: 4)
                Text("Prices").font(.ui(11)).foregroundStyle(C.muted)
                chips([(true, "Jita sell"), (false, "Jita buy")], selection: $sellBasis)
            }
        }
    }

    private func chips<ID: Hashable>(_ options: [(ID, String)], selection: Binding<ID>) -> some View {
        FlowRow(spacing: 6) {
            ForEach(options, id: \.0) { id, label in
                Button(label) { selection.wrappedValue = id }
                    .buttonStyle(CanopusButtonStyle(kind: selection.wrappedValue == id ? .primary : .ghost, small: true))
            }
        }
    }

    // MARK: Yield

    private func level(_ skill: Int?) -> Double {
        guard let skill else { return 0 }
        return Double(allFive ? 5 : pilotSkills[skill] ?? 0)
    }

    /// The fraction of each material the facility gives back for this item.
    private func yield(_ info: ReprocessInfo) -> Double {
        let base = facility == .station ? stationBase : 50
        guard let ore = info.oreSkill else {
            return base / 100 * (1 + 0.02 * level(scrapmetalSkill))
        }
        var y = facility == .station
            ? base
            : (50 + Double(rig)) * (1 + (rig > 0 ? space.bonus : 0)) * (1 + facility.structureBonus)
        y *= (1 + 0.03 * level(reprocessingSkill)) * (1 + 0.02 * level(efficiencySkill)) * (1 + 0.02 * level(ore))
        y *= 1 + Double(implant) / 100
        return y / 100
    }

    private func price(_ id: Int) -> Double { (sellBasis ? prices[id]?.sell : prices[id]?.buy) ?? 0 }

    /// Materials one line gives (whole batches; the rest stays as it is).
    private func output(_ l: Line) -> [Int: Int] {
        guard let info = l.info else { return [:] }
        let batches = l.qty / info.portionSize
        let y = yield(info)
        var out: [Int: Int] = [:]
        for m in info.materials { out[m.typeId, default: 0] += Int((Double(m.quantity * batches) * y).rounded(.down)) }
        return out
    }

    // MARK: Result

    @ViewBuilder private var result: some View {
        let outputs = lines.map { output($0) }
        let totals = outputs.reduce(into: [Int: Int]()) { $0.merge($1, uniquingKeysWith: +) }
        // The comparison only counts items that have a market price (ice, say, sells compressed).
        let priced = lines.indices.filter { price(lines[$0].type.id) > 0 }
        let itemsValue = priced.reduce(0) { $0 + Double(lines[$1].qty) * price(lines[$1].type.id) }
        let worth = { (out: [Int: Int]) in out.reduce(0) { $0 + Double($1.value) * price($1.key) } }
        let gross = priced.reduce(0) { $0 + worth(outputs[$1]) }
        let taxISK = gross * tax / 100
        let net = gross - taxISK
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            StatTile(label: "Items as they are", value: Fmt.isk(itemsValue))
            StatTile(label: "Minerals after tax", value: Fmt.isk(net),
                     sub: priced.count < lines.count ? String(localized: "items without a price not compared") : tax > 0 ? String(localized: "tax \(Fmt.isk(taxISK))") : nil,
                     valueColor: net >= itemsValue ? C.good : C.text)
            StatTile(label: "Better", value: net > itemsValue ? String(localized: "Reprocess") : String(localized: "Sell as is"),
                     sub: itemsValue > 0 ? String(format: "%+.1f%%", (net - itemsValue) / itemsValue * 100) : nil,
                     valueColor: net > itemsValue ? C.good : C.warn)
        }
        Card(String(localized: "What goes in")) {
            ForEach(Array(lines.enumerated()), id: \.element.id) { i, l in
                let out = outputs[i]
                let worth = out.reduce(0) { $0 + Double($1.value) * price($1.key) } * (1 - tax / 100)
                let asIs = Double(l.qty) * price(l.type.id)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        EVETypeIcon(typeId: l.type.id, size: 24)
                        Text(verbatim: l.type.name).font(.ui(13)).foregroundStyle(C.text).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(verbatim: "×\(l.qty.formatted())").font(.mono(11)).foregroundStyle(C.muted)
                    }
                    if let info = l.info {
                        let left = l.qty % info.portionSize
                        HStack(spacing: 8) {
                            Text(verbatim: String(format: "%.1f%%", yield(info) * 100))
                            Text(verbatim: "\(asIs > 0 ? Fmt.isk(asIs) : String(localized: "no price")) → \(Fmt.isk(worth))")
                                .foregroundStyle(asIs > 0 && worth > asIs ? C.good : C.muted)
                            if left > 0 { Text("\(left) left over (batch \(info.portionSize))").foregroundStyle(C.warn) }
                        }
                        .font(.mono(10)).foregroundStyle(C.muted)
                    } else {
                        Text("Can't be reprocessed").font(.ui(11)).foregroundStyle(C.muted)
                    }
                }
                .padding(.vertical, 3)
            }
        }
        Card(String(localized: "Minerals")) {
            ForEach(totals.sorted { Double($0.value) * price($0.key) > Double($1.value) * price($1.key) }, id: \.key) { id, qty in
                HStack(spacing: 6) {
                    EVETypeIcon(typeId: id, size: 22)
                    Text(verbatim: names[id] ?? "#\(id)").font(.ui(13)).foregroundStyle(C.text).lineLimit(1)
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(verbatim: qty.formatted()).font(.mono(12, medium: true)).foregroundStyle(C.text)
                        Text(verbatim: Fmt.isk(Double(qty) * price(id))).font(.mono(10)).foregroundStyle(C.muted)
                    }
                }
            }
            Text("Yield per EVE University's formulas; ore skills come from the SDE. Leftovers smaller than a batch stay unprocessed.")
                .font(.ui(11)).foregroundStyle(C.faint)
        }
    }

    // MARK: Loading

    private func calculate() async {
        guard let repo = env.repository else { return }
        working = true
        defer { working = false }
        var found: [Line] = []
        var missing: [String] = []
        for (name, qty) in parseItemList(text) {
            if let t = try? await repo.type(named: name) { found.append(Line(id: t.id, type: t, qty: qty, info: nil)) } else { missing.append(name) }
        }
        let infos = (try? await repo.reprocessInfo(typeIds: Set(found.map(\.type.id)))) ?? [:]
        var merged: [Int: Line] = [:]
        for l in found {
            let q = (merged[l.id]?.qty ?? 0) + l.qty
            merged[l.id] = Line(id: l.id, type: l.type, qty: q, info: infos[l.id])
        }
        let ordered = found.map(\.id).reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }.compactMap { merged[$0] }
        let materialIds = Set(infos.values.flatMap { $0.materials.map(\.typeId) })
        names = ((try? await repo.types(ids: materialIds)) ?? [:]).mapValues(\.name)
        prices = (try? await HubPrices.hub(station: HubPrices.jitaStation, typeIds: materialIds.union(ordered.map(\.id)))) ?? [:]
        notFound = missing
        lines = ordered
    }
}
