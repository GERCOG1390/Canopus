import SwiftUI
import Domain
import EVEStaticData
import EVEAuth

struct TypeDetailView: View {
    let typeId: Int
    let typeName: String
    @Environment(AppEnvironment.self) private var env
    @State private var itemType: ItemType?
    @State private var itemGroup: ItemGroup?
    @State private var attributes: [TypeAttributeDetail] = []
    @State private var effects: [TypeEffectDetail] = []
    @State private var skillReqs: [(skillId: Int, skillName: String, level: Int)] = []
    @State private var typeTraits: [TypeTrait] = []
    @State private var traitSkillNames: [Int: String] = [:]
    @State private var marketPath: [MarketGroup] = []
    @State private var variations: [ItemType] = []
    @State private var compatibleChargeGroups: [ItemGroup] = []
    @State private var compatibleChargeGroupIconTypeIds: [Int: Int] = [:]
    @State private var compatibleCharges: [ItemType] = []
    @State private var affectedBy: [TypeInfluence] = []
    @State private var skillAffects: [TypeInfluence] = []
    @State private var ownedAssetQuantity: Int?
    @State private var usedInFitNames: [String] = []
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
            headerSection

            // Base stats
            if let item = itemType {
                let hasStats = (item.mass ?? 0) > 0 || (item.volume ?? 0) > 0 || item.metaGroupId != nil
                if hasStats {
                    detailSection("Base Stats") {
                        if let itemGroup {
                            StatRow(label: "Purpose", value: itemGroup.name)
                        }
                        StatRow(label: "Tier", value: EVETypeMetaPresentation.title(for: item.metaGroupId), iconId: 1446)
                        if let mass = item.mass, mass > 0 {
                            StatRow(label: "Mass", value: formatNumber(mass) + " kg", iconId: 76)
                        }
                        if let vol = item.volume, vol > 0 {
                            StatRow(label: "Volume", value: formatNumber(vol) + " m³", iconId: 71)
                        }
                        if let cap = item.capacity, cap > 0 {
                            StatRow(label: "Capacity", value: formatNumber(cap) + " m³", iconId: 71)
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

            let grouped = groupedAttributes
            ForEach(grouped, id: \.name) { group in
                detailSection(group.name) {
                    ForEach(group.attrs) { attr in
                        StatRow(
                            label: displayLabel(for: attr),
                            value: formatAttributeValue(attr),
                            iconId: attr.attribute?.iconId
                        )
                    }
                }
            }

            // Description
            if let desc = effectiveDescription {
                detailSection("Description") {
                    Text(desc)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(traitSections) { section in
                detailSection(section.title) {
                    ForEach(section.traits) { trait in
                        TypeTraitRow(trait: trait)
                    }
                }
            }

            ForEach(skillAffectSections) { section in
                detailSection("Affects \(section.title)") {
                    ForEach(section.items.prefix(24)) { influence in
                        TypeInfluenceRow(influence: influence, currentTypeId: typeId)
                    }
                }
            }

            // Required Skills
            if !skillReqs.isEmpty {
                detailSection("Required Skills") {
                    ForEach(skillReqs, id: \.skillId) { req in
                        SkillReqRow(skillId: req.skillId, skillName: req.skillName, level: req.level)
                    }
                }
            }

            // Market
            detailSection("Market") {
                Button { marketDestination = true } label: {
                    Label("Market Prices", systemImage: "chart.line.uptrend.xyaxis")
                }
                if !marketPath.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                            .font(.caption)
                            .foregroundStyle(Color.eveAmber)
                        Text(marketPath.map(\.name).joined(separator: " / "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }

            if variations.count > 1 {
                detailSection("Variations") {
                    ForEach(variations.prefix(16)) { variant in
                        TypeLinkRow(type: variant, subtitle: EVETypeMetaPresentation.title(for: variant.metaGroupId), currentTypeId: typeId)
                    }
                }
            }

            if !compatibleChargeGroups.isEmpty || !compatibleCharges.isEmpty {
                detailSection("Compatible Charges") {
                    ForEach(compatibleChargeGroups) { group in
                        ChargeGroupRow(group: group, iconTypeId: compatibleChargeGroupIconTypeIds[group.id])
                    }
                    ForEach(compatibleCharges.prefix(16)) { charge in
                        TypeLinkRow(type: charge, subtitle: EVETypeMetaPresentation.title(for: charge.metaGroupId), currentTypeId: typeId)
                    }
                }
            }

            if ownedAssetQuantity != nil || !usedInFitNames.isEmpty {
                detailSection("Character Usage") {
                    if let ownedAssetQuantity {
                        StatRow(label: "Owned in Assets", value: "x\(ownedAssetQuantity)", iconId: 33)
                    }
                    if !usedInFitNames.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                EVEIconImage(iconId: 1432, size: 16)
                                Text("Used in Fits")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(usedInFitNames.count)")
                                    .font(.system(size: 14))
                                    .monospacedDigit()
                            }
                            Text(usedInFitNames.prefix(6).joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        .padding(.vertical, 1)
                    }
                }
            }

            ForEach(affectedBySections) { section in
                detailSection("Affected by \(section.title)") {
                    ForEach(section.items.prefix(16)) { influence in
                        TypeInfluenceRow(influence: influence, currentTypeId: typeId)
                    }
                }
            }

        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.eveBackground)
        .eveTabBarClearance()
        .navigationTitle(typeName)
        .navigationBarTitleDisplayMode(.inline)
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

    private var headerSection: some View {
        Section {
            HStack(alignment: .top, spacing: 14) {
                EVETypeIcon(typeId: typeId, size: 58)
                    .clipShape(CutCorner(size: 8))
                    .overlay(CutCorner(size: 8).stroke(Color.eveAmber.opacity(0.28), lineWidth: 1))

                VStack(spacing: 8) {
                    Text(typeName)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let itemGroup {
                        Text(itemGroup.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 8) {
                        TypeMetaBadge(metaGroupId: itemType?.metaGroupId)
                        if let marketPathName {
                            TypeInfoChip(title: "Market", value: marketPathName)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)
        }
    }

    private var marketPathName: String? {
        guard let last = marketPath.last else { return nil }
        return last.name
    }

    private var isBlueprintType: Bool {
        typeName.localizedCaseInsensitiveContains("Blueprint")
            || itemGroup?.name.localizedCaseInsensitiveContains("Blueprint") == true
            || marketPath.contains { $0.name.localizedCaseInsensitiveContains("Blueprint") }
    }

    private var blueprintProductName: String {
        let suffix = " Blueprint"
        if typeName.hasSuffix(suffix) {
            return String(typeName.dropLast(suffix.count))
        }
        return typeName
    }

    private var effectiveDescription: String? {
        let rawDescription = itemType?.typeDescription?
            .strippedEVEHTML
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !rawDescription.isEmpty {
            return rawDescription
        }

        guard isBlueprintType else { return nil }
        return "Blueprint for \(blueprintProductName). Use it in industry to manufacture the item or as part of the related production chain."
    }

    @ViewBuilder
    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            content()
        } header: {
            EVESectionHeader(
                title,
                accentColor: Color.eveText.opacity(0.48),
                backgroundColor: Color.eveBackground
            )
            .textCase(nil)
            .listRowInsets(EdgeInsets())
        }
    }

    // MARK: - Attribute grouping

    private struct AttrGroup {
        let name: String
        let attrs: [TypeAttributeDetail]
    }

    private var groupedAttributes: [AttrGroup] {
        guard !publishedAttributes.isEmpty else { return [] }

        var buckets: [String: [TypeAttributeDetail]] = [:]
        for attr in publishedAttributes {
            let key = attributeSection(for: attr)
            buckets[key, default: []].append(attr)
        }
        let order = ["Fitting", "Damage", "Charge & Ammo", "Shield", "Armor", "Structure", "Capacitor",
                     "Targeting", "Mobility", "Drones", "Heat & Overload", "Requirements", "Industry", "Miscellaneous"]
        return order.compactMap { name -> AttrGroup? in
            guard let attrs = buckets[name], !attrs.isEmpty else { return nil }
            return AttrGroup(name: name, attrs: attrs.sorted {
                attributeSortKey($0) < attributeSortKey($1)
            })
        }
    }

    private struct InfluenceSection: Identifiable {
        let title: String
        let items: [TypeInfluence]

        var id: String { title }
    }

    private var affectedBySections: [InfluenceSection] {
        guard !affectedBy.isEmpty else { return [] }
        let grouped = Dictionary(grouping: affectedBy) { influence in
            switch influence.categoryName {
            case "Skill":
                return "Skills"
            case "Implant":
                return "Implants & Boosters"
            case "Ship":
                return "Ships"
            case "Subsystem":
                return "Subsystems"
            case "Module":
                return "Modules"
            default:
                return influence.categoryName
            }
        }

        let order = ["Skills", "Implants & Boosters", "Ships", "Subsystems", "Modules"]
        let orderedKeys = order.filter { grouped[$0] != nil } + grouped.keys.filter { !order.contains($0) }.sorted()
        return orderedKeys.compactMap { key in
            guard let items = grouped[key], !items.isEmpty else { return nil }
            return InfluenceSection(title: key, items: items)
        }
    }

    private var skillAffectSections: [InfluenceSection] {
        guard !skillAffects.isEmpty else { return [] }

        let moduleCategories = Set(["Module", "Subsystem", "Drone", "Structure Module"])
        let ships = skillAffects.filter { $0.categoryName == "Ship" }
        let modules = skillAffects.filter { moduleCategories.contains($0.categoryName) }

        var sections: [InfluenceSection] = []
        if !ships.isEmpty {
            sections.append(InfluenceSection(title: "Ships", items: ships))
        }
        if !modules.isEmpty {
            sections.append(InfluenceSection(title: "Modules", items: modules))
        }
        return sections
    }

    private struct TraitSection: Identifiable {
        let title: String
        let traits: [TypeTrait]

        var id: String { title }
    }

    private var traitSections: [TraitSection] {
        guard !typeTraits.isEmpty else { return [] }

        var sections: [TraitSection] = []
        let roleTraits = typeTraits
            .filter { $0.skillId == nil }
            .sorted { $0.sort < $1.sort }
        if !roleTraits.isEmpty {
            sections.append(TraitSection(title: "Role Bonuses", traits: roleTraits))
        }

        let skillTraits = Dictionary(grouping: typeTraits.filter { $0.skillId != nil }) { $0.skillId ?? 0 }
        for skillId in skillTraits.keys.sorted(by: traitSkillSort) {
            guard let traits = skillTraits[skillId] else { continue }
            let skillName = traitSkillNames[skillId] ?? "Skill \(skillId)"
            sections.append(TraitSection(title: "\(skillName) Bonuses", traits: traits.sorted { $0.sort < $1.sort }))
        }

        return sections
    }

    private func traitSkillSort(_ lhs: Int, _ rhs: Int) -> Bool {
        let lhsName = traitSkillNames[lhs] ?? "Skill \(lhs)"
        let rhsName = traitSkillNames[rhs] ?? "Skill \(rhs)"
        return lhsName.localizedStandardCompare(rhsName) == .orderedAscending
    }

    private func attributeSection(for attr: TypeAttributeDetail) -> String {
        let id = attr.attributeId
        if [11, 12, 13, 14, 15, 30, 48, 49, 50, 128, 1367, 2056].contains(id) { return "Fitting" }
        if [64, 114, 116, 117, 118, 204].contains(id) { return "Damage" }
        if [51, 54, 117, 158, 160, 653, 654, 655].contains(id) { return "Charge & Ammo" }
        if [68, 72, 73, 75, 263, 271, 272, 273, 274, 479, 984, 985, 986, 987].contains(id) { return "Shield" }
        if [265, 267, 268, 269, 270].contains(id) { return "Armor" }
        if [9, 113, 110, 111, 112, 115, 119, 120].contains(id) { return "Structure" }
        if [6, 18, 55, 482, 2045].contains(id) { return "Capacitor" }
        if [76, 192, 208, 209, 210, 211, 564].contains(id) { return "Targeting" }
        if [37, 70, 552, 554, 567, 633].contains(id) { return "Mobility" }
        if [283, 1271, 1272].contains(id) { return "Drones" }
        if [1180, 1208, 1211].contains(id) { return "Heat & Overload" }
        if [182, 183, 184, 277, 278, 279, 1285, 1212].contains(id) { return "Requirements" }
        if [77, 161, 422].contains(id) { return "Industry" }
        return "Miscellaneous"
    }

    private func attributeSortKey(_ attr: TypeAttributeDetail) -> String {
        let rank: [Int: Int] = [
            50: 10, 49: 11, 30: 12, 15: 13, 11: 14, 48: 15,
            114: 20, 116: 21, 117: 22, 118: 23, 64: 24, 204: 25,
            263: 30, 72: 31, 984: 32, 985: 33, 986: 34, 987: 35, 271: 36, 274: 37, 273: 38, 272: 39, 479: 40,
            265: 40, 267: 41, 270: 42, 269: 43, 268: 44,
            9: 50, 113: 51, 110: 52, 111: 53, 112: 54, 115: 55,
            482: 60, 55: 61, 18: 62, 73: 63,
            76: 70, 192: 71, 209: 72, 211: 73, 552: 74,
            37: 80, 70: 81, 554: 82, 567: 83,
            283: 90, 1271: 91, 1272: 92,
            1208: 100, 1211: 101, 1180: 102,
            182: 110, 183: 111, 184: 112, 1285: 113, 1212: 114
        ]
        return String(format: "%04d-%@", rank[attr.attributeId] ?? 999, displayLabel(for: attr))
    }

    // MARK: - Load

    private func load() async {
        guard let repo = env.repository else { return }
        do {
            async let t  = repo.type(id: typeId)
            async let at = repo.attributes(typeId: typeId)
            async let ef = repo.effects(typeId: typeId)
            async let sr = repo.skillRequirements(typeId: typeId)
            async let traits = repo.typeTraits(typeId: typeId)
            async let vars = repo.variations(typeId: typeId)
            async let chargeGroups = repo.compatibleChargeGroups(weaponTypeId: typeId)
            async let charges = repo.compatibleCharges(weaponTypeId: typeId)
            async let groupIconIds = repo.representativeTypeIdsByGroup()
            let (type_, attrs, effectDetails, reqs, traitDetails) = try await (t, at, ef, sr, traits)
            itemType   = type_
            attributes = attrs
            effects = effectDetails
            typeTraits = traitDetails
            variations = try await vars
            compatibleChargeGroups = try await chargeGroups
            compatibleCharges = try await charges
            let representativeIconIds = try await groupIconIds
            compatibleChargeGroupIconTypeIds = compatibleChargeGroups.reduce(into: [:]) { result, group in
                result[group.id] = representativeIconIds[group.id]
            }
            if let type_ {
                itemGroup = try? await repo.group(id: type_.groupId)
                if let marketGroupId = type_.marketGroupId {
                    marketPath = (try? await repo.marketGroupPath(id: marketGroupId)) ?? []
                }
                affectedBy = (try? await repo.affectingTypes(targetGroupId: type_.groupId)) ?? []
                if itemGroup?.categoryId == 16 {
                    skillAffects = (try? await repo.typesAffectedBySkill(skillTypeId: typeId)) ?? []
                } else {
                    skillAffects = []
                }
            }
            await loadCharacterUsage()
            await loadTraitSkillNames(repo: repo)

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

    private func loadCharacterUsage() async {
        guard let service = env.characterStore.selectedService else {
            ownedAssetQuantity = nil
            usedInFitNames = []
            return
        }

        async let assetsTask = service.assets()
        async let fittingsTask = service.fittings()

        do {
            let (assets, fittings) = try await (assetsTask, fittingsTask)
            let quantity = assets
                .filter { $0.typeId == typeId }
                .reduce(0) { total, asset in
                    total + (asset.isSingleton ? 1 : asset.quantity)
                }
            ownedAssetQuantity = quantity > 0 ? quantity : nil

            usedInFitNames = fittings
                .filter { fitting in
                    fitting.shipTypeId == typeId || fitting.items.contains { $0.typeId == typeId }
                }
                .map(\.name)
                .sorted()
        } catch {
            ownedAssetQuantity = nil
            usedInFitNames = []
        }
    }

    private func loadTraitSkillNames(repo: SDERepository) async {
        let skillIds = Set(typeTraits.compactMap(\.skillId))
        guard !skillIds.isEmpty else {
            traitSkillNames = [:]
            return
        }

        do {
            let skills = try await repo.types(ids: skillIds)
            traitSkillNames = skills.mapValues(\.name)
        } catch {
            traitSkillNames = [:]
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
        switch attr.attributeId {
        case 11, 15, 30, 549:
            return oneDecimal(v) + " MW"
        case 48, 49, 50:
            return oneDecimal(v) + " tf"
        case 37:
            return wholeNumber(v) + " m/s"
        case 51, 55, 73, 479:
            return formatDuration(milliseconds: v)
        case 54, 76, 1271:
            return formatDistance(v)
        case 64, 70:
            return twoDecimal(v) + "x"
        case 113, 267, 268, 269, 270, 271, 272, 273, 274:
            return formatResistance(v)
        case 114, 116, 117, 118:
            return oneDecimal(v) + " HP"
        case 128:
            return chargeSizeName(v)
        case 134, 144, 145, 146, 147, 148, 149, 150, 202, 204, 213, 237, 306, 565, 2335, 2336, 2337, 2338:
            return multiplierDeltaPercent(v)
        case 160:
            return String(format: "%.4f rad/s", v)
        case 192:
            return wholeNumber(v) + "x"
        case 263, 265, 9, 68, 72:
            return wholeNumber(v) + " HP"
        case 482, 18:
            return oneDecimal(v) + " GJ"
        case 552, 654:
            return wholeNumber(v) + " m"
        case 554, 20:
            return signedPercent(v)
        case 567:
            return oneDecimal(v / 1_000_000) + " MN"
        case 653:
            return wholeNumber(v) + " m/s"
        case 283:
            return oneDecimal(v) + " m³"
        case 1272:
            return wholeNumber(v) + " Mbit/s"
        case 984, 985, 986, 987, 1208:
            return signedPercent(v)
        case 1211:
            return oneDecimal(v) + " HP"
        default:
            break
        }

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

    private func displayLabel(for attr: TypeAttributeDetail) -> String {
        switch attr.attributeId {
        case 9: return "Structure Hitpoints"
        case 11: return "Powergrid Output"
        case 15: return "Powergrid Usage"
        case 18: return "Capacitor Need"
        case 30: return "Powergrid Usage"
        case 37: return "Maximum Velocity"
        case 48: return "CPU Output"
        case 49, 50: return "CPU Usage"
        case 51: return "Cycle Time"
        case 54: return "Optimal Range"
        case 55: return "Capacitor Recharge Time"
        case 64: return "Damage Modifier"
        case 70: return "Inertia Modifier"
        case 73: return "Activation Time"
        case 76: return "Targeting Range"
        case 113: return "Structure EM Resistance"
        case 114: return "EM Damage"
        case 116: return "Explosive Damage"
        case 117: return "Kinetic Damage"
        case 118: return "Thermal Damage"
        case 128: return "Charge Size"
        case 134: return "Shield Recharge Time Bonus"
        case 144: return "Capacitor Recharge Time Bonus"
        case 145: return "Powergrid Output Bonus"
        case 146: return "Shield Capacity Bonus"
        case 147: return "Capacitor Capacity Bonus"
        case 148: return "Armor Hitpoint Bonus"
        case 149: return "Cargo Capacity Bonus"
        case 150: return "Structure Hitpoint Bonus"
        case 158: return "Falloff"
        case 160: return "Tracking Speed"
        case 192: return "Maximum Locked Targets"
        case 202: return "CPU Output Bonus"
        case 204: return "Rate of Fire Bonus"
        case 213: return "Missile Damage Bonus"
        case 237: return "Targeting Range Bonus"
        case 263: return "Shield Capacity"
        case 265: return "Armor Hitpoints"
        case 267: return "Armor EM Resistance"
        case 268: return "Armor Explosive Resistance"
        case 269: return "Armor Kinetic Resistance"
        case 270: return "Armor Thermal Resistance"
        case 271: return "Shield EM Resistance"
        case 272: return "Shield Explosive Resistance"
        case 273: return "Shield Kinetic Resistance"
        case 274: return "Shield Thermal Resistance"
        case 283: return "Drone Bay"
        case 306: return "Maximum Velocity Modifier"
        case 479: return "Shield Recharge Time"
        case 482: return "Capacitor Capacity"
        case 552: return "Signature Radius"
        case 554: return "Signature Radius Modifier"
        case 565: return "Scan Resolution Bonus"
        case 549: return "Powergrid Bonus"
        case 567: return "Thrust"
        case 653: return "Explosion Velocity"
        case 654: return "Explosion Radius"
        case 984: return "EM Resistance Bonus"
        case 985: return "Explosive Resistance Bonus"
        case 986: return "Kinetic Resistance Bonus"
        case 987: return "Thermal Resistance Bonus"
        case 1180: return "Heat Absorption Modifier"
        case 1208: return "Overload Hardening Bonus"
        case 1211: return "Heat Damage"
        case 1212: return "Required Thermodynamics Level"
        case 1271: return "Drone Control Range"
        case 1272: return "Bandwidth Needed"
        case 2335: return "Fighter Shield Bonus"
        case 2336: return "Fighter Velocity Bonus"
        case 2337: return "Fighter Rate of Fire Bonus"
        case 2338: return "Fighter Shield Recharge Bonus"
        default:
            return attr.attribute?.displayName?.nilIfEmpty ?? attr.attribute?.name ?? "Attribute \(attr.attributeId)"
        }
    }

    private func wholeNumber(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    private func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private func twoDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    private func formatDuration(milliseconds: Double) -> String {
        let seconds = milliseconds / 1000
        if seconds >= 60 {
            let minutes = Int(seconds) / 60
            let remainder = Int(seconds) % 60
            return "\(minutes)m \(remainder)s"
        }
        return oneDecimal(seconds) + " s"
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return oneDecimal(meters / 1000) + " km"
        }
        return wholeNumber(meters) + " m"
    }

    private func formatResistance(_ resonance: Double) -> String {
        let resistance = (1 - resonance) * 100
        return String(format: "%.1f %%", resistance)
    }

    private func signedPercent(_ value: Double) -> String {
        String(format: "%+.1f %%", value)
    }

    private func multiplierDeltaPercent(_ value: Double) -> String {
        String(format: "%+.1f %%", (value - 1) * 100)
    }

    private func chargeSizeName(_ value: Double) -> String {
        switch Int(value) {
        case 1: return "Small"
        case 2: return "Medium"
        case 3: return "Large"
        case 4: return "Extra Large"
        default: return oneDecimal(value)
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
                .font(.system(size: 14, weight: .medium))
            Spacer()
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i <= level ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 9, height: 9)
                }
            }
            Text("L\(level)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Type Links

private struct TypeLinkRow: View {
    let type: ItemType
    let subtitle: String
    let currentTypeId: Int

    var body: some View {
        if type.id == currentTypeId {
            row
        } else {
            NavigationLink {
                TypeDetailView(typeId: type.id, typeName: type.name)
            } label: {
                row
            }
        }
    }

    private var row: some View {
        HStack(spacing: 10) {
            EVETypeIcon(typeId: type.id, size: 32)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 3) {
                Text(type.name)
                    .font(.system(size: 14, weight: type.id == currentTypeId ? .semibold : .regular))
                    .lineLimit(2)
                Text(type.id == currentTypeId ? "\(subtitle) · Current" : subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 1)
    }
}

private struct TypeInfluenceRow: View {
    let influence: TypeInfluence
    let currentTypeId: Int

    var body: some View {
        TypeLinkRow(
            type: influence.type,
            subtitle: subtitle,
            currentTypeId: currentTypeId
        )
    }

    private var subtitle: String {
        let attributes = influence.modifiedAttributes.prefix(3).joined(separator: ", ")
        if attributes.isEmpty {
            return influence.groupName
        }
        return "\(influence.groupName) · \(attributes)"
    }
}

private struct TypeTraitRow: View {
    let trait: TypeTrait

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            EVEIconImage(iconId: 1446, size: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                if let bonus = trait.bonus {
                    Text(formatBonus(bonus, unitId: trait.unitId))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.eveAmber)
                }
                Text(trait.text.strippedEVEHTML)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private func formatBonus(_ value: Double, unitId: Int?) -> String {
        let sign = value > 0 ? "+" : ""
        let number: String
        if value.rounded() == value {
            number = String(format: "%.0f", value)
        } else {
            number = String(format: "%.2f", value)
        }

        switch unitId {
        case 105:
            return "\(sign)\(number)%"
        case 109:
            return "\(sign)\(number)x"
        case 113:
            return "\(sign)\(number) HP"
        case 124:
            return "\(sign)\(number) m"
        case 133:
            return "\(sign)\(number) points"
        default:
            return "\(sign)\(number)"
        }
    }
}

private struct ChargeGroupRow: View {
    let group: ItemGroup
    let iconTypeId: Int?

    var body: some View {
        HStack(spacing: 10) {
            if let iconTypeId {
                EVETypeIcon(typeId: iconTypeId, size: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                EVEIconImage(iconId: 1299, size: 22)
            }
            Text(group.name)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Stat Row

private struct StatRow: View {
    let label: String
    let value: String
    var iconId: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let iconId {
                EVEIconImage(iconId: iconId, size: 16)
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
            }
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Type Presentation

enum EVETypeMetaPresentation {
    static func title(for metaGroupId: Int?) -> String {
        switch metaGroupId {
        case 1: return "Tech I"
        case 2: return "Tech II"
        case 3: return "Storyline"
        case 4: return "Faction"
        case 5: return "Officer"
        case 6: return "Deadspace"
        case 14: return "Strategic Cruiser"
        case 15: return "Tech III"
        case 17: return "Structure Tech I"
        case 19: return "Structure Faction"
        case 52: return "Abyssal"
        case 53: return "Precursor"
        case 54: return "Mutaplasmid"
        case .some(let id): return "Meta Group \(id)"
        case .none: return "Standard"
        }
    }

    static func sectionTitle(for metaGroupId: Int?) -> String {
        switch metaGroupId {
        case 1, .none: return "Tech I / Standard"
        case 2: return "Tech II"
        case 3: return "Storyline"
        case 4: return "Faction"
        case 5: return "Officer"
        case 6: return "Deadspace"
        case 14, 15, 17, 19, 52, 53, 54: return title(for: metaGroupId)
        case .some: return "Other Variants"
        }
    }

    static func rank(for metaGroupId: Int?) -> Int {
        switch metaGroupId {
        case 1, .none: return 10
        case 2: return 20
        case 3: return 30
        case 4: return 40
        case 6: return 50
        case 5: return 60
        case 15: return 70
        case 14: return 71
        case 52: return 80
        case 53: return 81
        case 54: return 82
        case 17: return 90
        case 19: return 91
        case .some(let id): return 1000 + id
        }
    }

    static func metaLevel(for metaGroupId: Int?) -> Int {
        switch metaGroupId {
        case 2: return 5
        case 3: return 6
        case 4: return 8
        case 6: return 10
        case 5: return 12
        case 15: return 5
        default: return metaGroupId ?? 0
        }
    }

    static func color(for metaGroupId: Int?) -> Color {
        switch metaGroupId {
        case 2, 15: return .blue
        case 3: return .purple
        case 4, 19: return .orange
        case 5: return .red
        case 6: return .mint
        case 52, 53, 54: return .indigo
        default: return .secondary
        }
    }
}

struct TypeMetaBadge: View {
    let metaGroupId: Int?

    var body: some View {
        Text(EVETypeMetaPresentation.title(for: metaGroupId))
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(EVETypeMetaPresentation.color(for: metaGroupId))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(EVETypeMetaPresentation.color(for: metaGroupId).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .lineLimit(1)
    }
}

private struct TypeInfoChip: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(.primary)
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .lineLimit(1)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
