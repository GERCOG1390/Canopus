import SwiftUI
import Domain
import EVEStaticData
import EVEAuth

struct TypeDetailView: View {
    let typeId: Int
    let typeName: String
    @Environment(AppEnvironment.self) private var env
    @State private var itemType: ItemType?
    @State private var attributes: [TypeAttributeDetail] = []
    @State private var effects: [TypeEffectDetail] = []
    @State private var skillReqs: [(skillId: Int, skillName: String, level: Int)] = []
    @State private var error: Error?
    @State private var marketDestination = false

    private var publishedAttributes: [TypeAttributeDetail] {
        attributes.filter { $0.attribute?.published == true }
    }

    private var rawAttributes: [TypeAttributeDetail] {
        attributes.filter { $0.attribute?.published != true }
    }

    var body: some View {
        List {
            // Render image
            Section {
                EVERenderImage(typeId: typeId, size: 280)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(.init())
                    .listRowBackground(Color.clear)
            }

            // Description
            if let desc = itemType?.typeDescription, !desc.isEmpty {
                Section("Description") {
                    Text(desc.strippedEVEHTML)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            // Market
            Section {
                Button { marketDestination = true } label: {
                    Label("Market Prices", systemImage: "chart.line.uptrend.xyaxis")
                }
            }

            // Base stats
            if let item = itemType {
                let hasStats = (item.mass ?? 0) > 0 || (item.volume ?? 0) > 0
                if hasStats {
                    Section("Base Stats") {
                        if let mass = item.mass, mass > 0 {
                            StatRow(label: "Mass", value: formatNumber(mass) + " kg")
                        }
                        if let vol = item.volume, vol > 0 {
                            StatRow(label: "Volume", value: formatNumber(vol) + " m³")
                        }
                        if let cap = item.capacity, cap > 0 {
                            StatRow(label: "Capacity", value: formatNumber(cap) + " m³")
                        }
                        if let portion = item.portionSize, portion > 1 {
                            StatRow(label: "Portion Size", value: "\(portion)")
                        }
                        if let price = item.basePrice, price > 0 {
                            StatRow(label: "Base Price", value: formatISK(price))
                        }
                    }
                }
            }

            // Required Skills
            if !skillReqs.isEmpty {
                Section("Required Skills") {
                    ForEach(skillReqs, id: \.skillId) { req in
                        SkillReqRow(skillId: req.skillId, skillName: req.skillName, level: req.level)
                    }
                }
            }

            // Dogma Attributes grouped by category
            let grouped = groupedAttributes
            ForEach(grouped, id: \.name) { group in
                Section(group.name) {
                    ForEach(group.attrs) { attr in
                        let label = attr.attribute?.displayName ?? attr.attribute?.name ?? "Attribute \(attr.attributeId)"
                        StatRow(label: label, value: formatAttributeValue(attr))
                    }
                }
            }

            if !rawAttributes.isEmpty {
                Section("Raw Dogma Attributes") {
                    ForEach(rawAttributes) { attr in
                        let label = attr.attribute?.name ?? "Attribute \(attr.attributeId)"
                        StatRow(label: "\(label) [\(attr.attributeId)]", value: formatAttributeValue(attr))
                    }
                }
            }

            if !effects.isEmpty {
                Section("Dogma Effects") {
                    ForEach(effects) { effect in
                        EffectRow(effect: effect)
                    }
                }
            }
        }
        .navigationTitle(typeName)
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(isPresented: $marketDestination) {
            MarketDetailView(typeId: typeId, typeName: typeName)
        }
        .overlay {
            if itemType == nil && error == nil {
                ProgressView()
            }
        }
        .task { await load() }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error?.localizedDescription ?? "") }
    }

    // MARK: - Attribute grouping

    private struct AttrGroup {
        let name: String
        let attrs: [TypeAttributeDetail]
    }

    private var groupedAttributes: [AttrGroup] {
        guard !publishedAttributes.isEmpty else { return [] }
        // Group by known attribute category keywords in the attribute name
        let fittingIds:  Set<Int> = [11, 12, 13, 14, 15, 48, 49, 50, 1367, 2056]  // PG, CPU, slots
        let shieldIds:   Set<Int> = [68, 72, 73, 74, 75, 271, 272, 273, 274]
        let armorIds:    Set<Int> = [265, 267, 268, 269, 270]
        let structureIds: Set<Int> = [9, 110, 113, 116, 117, 118, 119, 120]
        let capIds:      Set<Int> = [18, 48, 49, 482, 483]
        let targetingIds: Set<Int> = [37, 192, 209, 211, 552, 564]
        let droneIds:    Set<Int> = [283, 1271, 1272]

        func bucket(_ id: Int) -> String {
            if fittingIds.contains(id)   { return "Fitting" }
            if shieldIds.contains(id)    { return "Shield" }
            if armorIds.contains(id)     { return "Armor" }
            if structureIds.contains(id) { return "Structure" }
            if capIds.contains(id)       { return "Capacitor" }
            if targetingIds.contains(id) { return "Targeting" }
            if droneIds.contains(id)     { return "Drones" }
            return "Miscellaneous"
        }

        var buckets: [String: [TypeAttributeDetail]] = [:]
        for attr in publishedAttributes {
            let key = bucket(attr.attributeId)
            buckets[key, default: []].append(attr)
        }
        let order = ["Fitting", "Shield", "Armor", "Structure", "Capacitor",
                     "Targeting", "Drones", "Miscellaneous"]
        return order.compactMap { name -> AttrGroup? in
            guard let attrs = buckets[name], !attrs.isEmpty else { return nil }
            return AttrGroup(name: name, attrs: attrs.sorted {
                let a = $0.attribute?.displayName ?? $0.attribute?.name ?? ""
                let b = $1.attribute?.displayName ?? $1.attribute?.name ?? ""
                return a < b
            })
        }
    }

    // MARK: - Load

    private func load() async {
        guard let repo = env.repository else { return }
        do {
            async let t  = repo.type(id: typeId)
            async let at = repo.attributes(typeId: typeId)
            async let ef = repo.effects(typeId: typeId)
            async let sr = repo.skillRequirements(typeId: typeId)
            let (type_, attrs, effectDetails, reqs) = try await (t, at, ef, sr)
            itemType   = type_
            attributes = attrs
            effects = effectDetails

            // Resolve skill names
            skillReqs = await withTaskGroup(of: (Int, String, Int).self) { group in
                for req in reqs {
                    group.addTask {
                        let name = (try? await repo.type(id: req.skillId))?.name ?? "Skill \(req.skillId)"
                        return (req.skillId, name, req.level)
                    }
                }
                var result: [(Int, String, Int)] = []
                for await item in group { result.append(item) }
                return result.sorted { $0.2 < $1.2 }
            }
        } catch {
            self.error = error
        }
    }

    // MARK: - Formatting

    private func formatNumber(_ v: Double) -> String {
        if v >= 1_000_000_000 { return String(format: "%.2fG", v / 1_000_000_000) }
        if v >= 1_000_000     { return String(format: "%.2fM", v / 1_000_000) }
        if v >= 1_000         { return String(format: "%.2fK", v / 1_000) }
        let frac = v.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return v.formatted(.number.precision(.fractionLength(frac)))
    }

    private func formatISK(_ v: Double) -> String {
        if v >= 1_000_000_000 { return String(format: "%.2fB ISK", v / 1_000_000_000) }
        if v >= 1_000_000     { return String(format: "%.2fM ISK", v / 1_000_000) }
        return String(format: "%.2f ISK", v)
    }

    private func formatAttributeValue(_ attr: TypeAttributeDetail) -> String {
        let v = attr.value
        // Unit-based formatting
        switch attr.attribute?.unitId {
        case 1:  return formatNumber(v) + " m"
        case 2:  return formatNumber(v) + " AU"
        case 3:  return formatNumber(v) + " s"
        case 4:  return formatNumber(v) + " MW"
        case 5:  return formatNumber(v) + " tf"
        case 6:  return formatNumber(v) + " m³"
        case 9:  return String(format: "%.0f %%", v * 100)
        case 10: return String(format: "%.1f %%", v)
        case 11: return formatNumber(v) + " HP"
        case 14: return String(format: "%.0f m/s", v)
        case 15: return String(format: "%.0f mm", v)
        case 20: return String(format: "%.0f rad/s", v)
        case 24: return String(format: "%.0f km", v)
        case 109: return String(format: "%.0f Mbit/s", v)
        case 111: return String(format: "%.0f m³", v)
        case 112: return String(format: "%.0f MW", v)
        case 113: return String(format: "%.0f tf", v)
        case 114: return String(format: "%.0f GJ", v)
        case 115: return String(format: "%.0f GJ/s", v)
        case 116: return String(format: "%.0f points", v)
        case 117: return String(format: "%.2f x", v)
        case 118: return String(format: "%.0f %%", v)
        case 119: return String(format: "%.0f", v)
        case 120: return "Level \(Int(v))"
        case 121: return String(format: "%.0f ISK", v)
        case 122: return String(format: "%.0f", v)
        case 128: return String(format: "%.2f", v)
        case 136: return String(format: "%.0f hardpoints", v)
        case 137: return String(format: "%.0f points", v)
        case 138: return String(format: "%.0f points", v)
        default:
            let frac = v.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
            return v.formatted(.number.precision(.fractionLength(frac)))
        }
    }
}


// MARK: - Effect Row

private struct EffectRow: View {
    let effect: TypeEffectDetail

    var body: some View {
        DisclosureGroup {
            if effect.modifiers.isEmpty {
                Text("No modifier rows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(effect.modifiers) { modifier in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("\(modifier.domain) · \(modifier.function)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(operationName(modifier.operation))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Text(modifierText(modifier))
                            .font(.caption.monospaced())
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                        if let skillName = modifier.skillName {
                            Text("Requires \(skillName)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(effect.displayName ?? effect.name)
                    .font(.body)
                Text("#\(effect.effectId) · \(categoryName(effect.effectCategory))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func modifierText(_ modifier: DogmaModifierDetail) -> String {
        let modified = modifier.modifiedAttrName ?? "attr\(modifier.modifiedAttrId)"
        let modifying = modifier.modifyingAttrName ?? "attr\(modifier.modifyingAttrId)"
        var parts = ["\(modified) [\(modifier.modifiedAttrId)] <- \(modifying) [\(modifier.modifyingAttrId)]"]
        if let groupId = modifier.groupId {
            parts.append("group \(groupId)")
        }
        return parts.joined(separator: " · ")
    }

    private func operationName(_ operation: Int) -> String {
        switch operation {
        case -1: return "PreAssign"
        case 0: return "PreMul"
        case 2: return "Add"
        case 3: return "Sub"
        case 4: return "PostMul"
        case 5: return "PostDiv"
        case 6: return "Percent"
        case 7: return "Assign"
        default: return "Op \(operation)"
        }
    }

    private func categoryName(_ category: Int) -> String {
        switch category {
        case 0: return "Passive"
        case 1: return "Active"
        case 2: return "Target"
        case 4: return "Online"
        case 5: return "Overload"
        default: return "Category \(category)"
        }
    }
}


// MARK: - Skill Requirement Row

private struct SkillReqRow: View {
    let skillId: Int
    let skillName: String
    let level: Int

    var body: some View {
        HStack {
            Text(skillName)
                .font(.body)
            Spacer()
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i <= level ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 10, height: 10)
                }
            }
            Text("L\(level)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Stat Row

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}
