import SwiftUI
import EVEAuth
import EVEStaticData
import Domain

// MARK: - Module Config (per-slot UI state)

struct ModuleConfig: Equatable {
    var state: ModuleState = .active
    var chargeTypeId: Int? = nil
}

private struct FlagItem: Identifiable { let id: String }

private struct ChargeDamageProfile {
    let em: Double
    let explosive: Double
    let kinetic: Double
    let thermal: Double

    var total: Double { em + explosive + kinetic + thermal }

    init(attrs: [Int: Double]) {
        em = attrs[114] ?? 0
        explosive = attrs[116] ?? 0
        kinetic = attrs[117] ?? 0
        thermal = attrs[118] ?? 0
    }
}

private struct ChargeDamageBreakdown: View {
    let profile: ChargeDamageProfile
    var compact = false

    var body: some View {
        if profile.total > 0 {
            VStack(alignment: .leading, spacing: compact ? 3 : 6) {
                HStack(spacing: 8) {
                    Text(String(format: "VOLLEY %.1f HP", profile.total))
                        .font(.system(size: compact ? 8 : 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.eveText.opacity(0.72))
                    if compact {
                        damageText("EM", profile.em, Color(hue: 0.60, saturation: 0.75, brightness: 0.90))
                        damageText("TH", profile.thermal, .eveRed)
                        damageText("KIN", profile.kinetic, Color(white: 0.66))
                        damageText("EXP", profile.explosive, .eveAmber)
                    }
                }

                if !compact {
                    VStack(spacing: 4) {
                        damageBar("EM", profile.em, Color(hue: 0.60, saturation: 0.75, brightness: 0.90))
                        damageBar("THERM", profile.thermal, .eveRed)
                        damageBar("KIN", profile.kinetic, Color(white: 0.66))
                        damageBar("EXP", profile.explosive, .eveAmber)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func damageText(_ label: String, _ value: Double, _ color: Color) -> some View {
        if value > 0 {
            Text(String(format: "%@ %.1f", label, value))
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    @ViewBuilder
    private func damageBar(_ label: String, _ value: Double, _ color: Color) -> some View {
        if value > 0 {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
                    .frame(width: 40, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(color.opacity(0.13))
                        Rectangle()
                            .fill(color.opacity(0.72))
                            .frame(width: geo.size.width * value / max(profile.total, 1))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                .frame(height: 5)
                Text(String(format: "%.1f HP · %.0f%%", value, value / profile.total * 100))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.eveText.opacity(0.66))
                    .frame(width: 88, alignment: .trailing)
            }
        }
    }
}

// MARK: - FittingsView

struct FittingsView: View {
    let characterService: CharacterService
    @Environment(AppEnvironment.self) private var env

    @State private var fittings: [ESIFitting] = []
    @State private var typeNames: [Int: String] = [:]
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        ZStack {
            Color.eveBackground.ignoresSafeArea()
            ScrollView {
                if fittings.isEmpty && !isLoading {
                    ContentUnavailableView("No Saved Fits",
                        systemImage: "wrench.and.screwdriver",
                        description: Text("Save fits in-game to see them here."))
                    .foregroundStyle(Color.eveText)
                    .padding(.top, 60)
                } else {
                    VStack(spacing: 0) {
                        Text("SAVED FITS · \(fittings.count)").hudLabel()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20).padding(.vertical, 14)
                        Color.eveAmber.opacity(0.14).frame(height: 1)
                        LazyVStack(spacing: 0) {
                            ForEach(fittings) { fit in
                                NavigationLink {
                                    FitDetailView(fit: fit, typeNames: typeNames, characterService: characterService)
                                } label: {
                                    fitRow(fit)
                                }
                                    .buttonStyle(.plain)
                                Color.white.opacity(0.055).frame(height: 1)
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            if isLoading { ProgressView().tint(Color.eveCyan) }
        }
        .navigationTitle("FITTINGS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.eveBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
        .alert("Error", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } })
        ) {
            Button("Retry") { Task { await load() } }
            Button("Dismiss", role: .cancel) {}
        } message: { Text(error?.localizedDescription ?? "") }
    }

    private func fitRow(_ fit: ESIFitting) -> some View {
        HStack(spacing: 13) {
            EVETypeIcon(typeId: fit.shipTypeId, size: 44)
                .clipShape(CutCorner(size: 7))
                .overlay(CutCorner(size: 7).stroke(Color.white.opacity(0.10), lineWidth: 1))
            VStack(alignment: .leading, spacing: 5) {
                Text(fit.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.eveText).lineLimit(1)
                HStack(spacing: 8) {
                    Text(typeNames[fit.shipTypeId] ?? "Ship \(fit.shipTypeId)")
                        .font(.system(size: 11)).foregroundStyle(Color.eveText.opacity(0.48))
                    Text("·").foregroundStyle(Color.eveText.opacity(0.22))
                    Text("\(fit.items.count) modules")
                        .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Color.eveText.opacity(0.38))
                }
            }
            Spacer()
            Text("›").font(.system(size: 16)).foregroundStyle(Color.eveText.opacity(0.28))
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color.eveBackground)
    }

    private func load() async {
        isLoading = true; error = nil; defer { isLoading = false }
        do {
            fittings = try await characterService.fittings()
            await resolveNames()
        } catch { self.error = error }
    }

    private func resolveNames() async {
        guard let repo = env.repository else { return }
        let ids = Set(fittings.flatMap { [$0.shipTypeId] + $0.items.map(\.typeId) })
        for id in ids {
            if let t = try? await repo.type(id: id) { typeNames[id] = t.name }
        }
    }
}

// MARK: - Fit Detail

struct FitDetailView: View {
    let fit: ESIFitting
    let typeNames: [Int: String]
    let characterService: CharacterService

    @Environment(AppEnvironment.self) private var env
    @State private var configs: [String: ModuleConfig] = [:]
    @State private var stats: ShipStats?
    @State private var moduleTypeProfiles: [Int: TypeProfile] = [:]
    @State private var chargeTypeAttrs: [Int: [Int: Double]] = [:]
    @State private var chargeTypeProfiles: [Int: TypeProfile] = [:]
    @State private var chargeNames: [Int: String] = [:]
    @State private var sheetFlag: FlagItem? = nil
    @State private var activeTab: FitTab = .modules
    @State private var characterSkills: [Int: Int] = [:]
    @State private var skillTypeProfiles: [Int: TypeProfile] = [:]
    @State private var implantTypeProfiles: [Int: TypeProfile] = [:]
    @State private var skillEffectModifiers: [Int: [ModifierRow]] = [:]
    @State private var liveItems: [ESIFittingItem]?
    @State private var localTypeNames: [Int: String] = [:]
    @State private var localTypes: [Int: ItemType] = [:]
    @State private var fittingWarning: String?

    private var currentItems: [ESIFittingItem] {
        liveItems ?? fit.items
    }

    private func typeName(_ typeId: Int, fallback: String) -> String {
        localTypes[typeId]?.name ?? localTypeNames[typeId] ?? typeNames[typeId] ?? fallback
    }

    private var cargoUsedVolume: Double {
        currentItems
            .filter { slotFor($0.flag) == .cargo }
            .reduce(0) { total, item in
                total + (localTypes[item.typeId]?.volume ?? 0) * Double(item.quantity)
            }
    }

    private var shipCargoCapacity: Double {
        localTypes[fit.shipTypeId]?.capacity ?? 0
    }

    private var selectedChargeNames: [String] {
        var seen = Set<Int>()
        return currentItems.compactMap { item in
            guard slotFor(item.flag) != .cargo, slotFor(item.flag) != .drone, isFittedType(item) else { return nil }
            let chargeId = configs[item.flag]?.chargeTypeId ?? embeddedCharge(for: item)?.typeId
            guard let chargeId, seen.insert(chargeId).inserted else { return nil }
            return typeName(chargeId, fallback: "Charge \(chargeId)")
        }
    }

    enum FitTab: String, CaseIterable { case modules = "MODULES"; case stats = "STATS" }

    // MARK: - Slot classification

    private enum Slot: String, CaseIterable {
        case high = "HIGH SLOTS", mid = "MID SLOTS", low = "LOW SLOTS"
        case rig = "RIGS", sub = "SUBSYSTEMS", drone = "DRONES", cargo = "CARGO"
    }

    private func slotFor(_ flag: String) -> Slot {
        if flag.hasPrefix("HiSlot")    { return .high }
        if flag.hasPrefix("MedSlot")   { return .mid }
        if flag.hasPrefix("LoSlot")    { return .low }
        if flag.hasPrefix("RigSlot")   { return .rig }
        if flag.hasPrefix("SubSystem") { return .sub }
        if flag == "DroneBay" || flag == "FighterBay" { return .drone }
        return .cargo
    }

    private func isFittedType(_ item: ESIFittingItem) -> Bool {
        guard let profile = moduleTypeProfiles[item.typeId] else {
            let slot = slotFor(item.flag)
            return slot != .cargo && slot != .drone
        }

        return !profile.effectIds.isDisjoint(with: [11, 12, 13, 2663, 3772])
    }

    private func isChargeType(_ item: ESIFittingItem) -> Bool {
        moduleTypeProfiles[item.typeId]?.effectIds.contains(9) == true
    }

    private func moduleItem(for flag: String) -> ESIFittingItem? {
        currentItems.first { $0.flag == flag && isFittedType($0) }
    }

    private func embeddedCharge(for item: ESIFittingItem) -> ESIFittingItem? {
        currentItems.first { $0.flag == item.flag && $0.typeId != item.typeId && isChargeType($0) }
    }

    private func moduleItems(in slot: Slot) -> [ESIFittingItem] {
        let items = currentItems.filter { slotFor($0.flag) == slot }
        guard slot != .cargo && slot != .drone else { return items }
        return items.filter(isFittedType)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            shipHeader
            Color.eveAmber.opacity(0.14).frame(height: 1)
            if stats != nil { resourceBar }
            tabBar
            Color.eveAmber.opacity(0.14).frame(height: 1)
            tabContent
        }
        .background(Color.eveBackground.ignoresSafeArea())
        .navigationTitle(fit.name.uppercased())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.eveBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: $sheetFlag) { flagItem in
            if let item = moduleItem(for: flagItem.id) {
                ModuleSettingSheet(
                    item: item,
                    typeName: typeName(item.typeId, fallback: "Module \(item.typeId)"),
                    moduleAttrs: moduleTypeProfiles[item.typeId]?.attrs ?? [:],
                    config: Binding(
                        get: { configs[flagItem.id] ?? ModuleConfig() },
                        set: { configs[flagItem.id] = $0 }
                    ),
                    chargeNames: $chargeNames,
                    chargeTypeAttrs: $chargeTypeAttrs,
                    onChargeSelected: { charge, attrs in
                        // Apply the selected charge to all weapons of the same type in this fit
                        for sameItem in currentItems where sameItem.typeId == item.typeId {
                            configs[sameItem.flag, default: ModuleConfig()].chargeTypeId = charge.id
                        }
                        localTypes[charge.id] = charge
                        chargeNames[charge.id] = charge.name
                        chargeTypeAttrs[charge.id] = attrs
                    }
                )
            }
        }
        .task { await initialLoad() }
        .onChange(of: configs) { _, _ in Task { await recalcStats() } }
    }

    // MARK: - Ship header

    private var shipHeader: some View {
        HStack(spacing: 14) {
            EVETypeIcon(typeId: fit.shipTypeId, size: 60)
                .clipShape(CutCorner(size: 10))
                .overlay(CutCorner(size: 10).stroke(Color.eveAmber.opacity(0.3), lineWidth: 1))
            VStack(alignment: .leading, spacing: 4) {
                Text(fit.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.eveText)
                Text(typeName(fit.shipTypeId, fallback: "")).font(.system(size: 11)).foregroundStyle(Color.eveText.opacity(0.50))
                HStack(spacing: 6) {
                    Text(liveItems == nil ? "SAVED FIT" : "LIVE SHIP")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(liveItems == nil ? Color.eveText.opacity(0.45) : Color.eveGreen)
                    Text("\(currentItems.count) items")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color.eveText.opacity(0.35))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(Color.eveBackground)
    }

    // MARK: - Resource bar (PG / CPU remaining)

    private var resourceBar: some View {
        HStack(spacing: 0) {
            if let s = stats, s.pgTotal > 0 {
                resourceCell("PG", used: s.pgUsed, total: s.pgTotal, unit: "MW", color: .eveAmber)
                Divider().background(Color.white.opacity(0.08))
                resourceCell("CPU", used: s.cpuUsed, total: s.cpuTotal, unit: "Tf", color: .eveCyan)
            }
        }
        .background(Color.eveCard)
        .frame(height: 36)
    }

    private func resourceCell(_ label: String, used: Double, total: Double, unit: String, color: Color) -> some View {
        let remaining = total - used
        let frac = total > 0 ? min(1, max(0, remaining / total)) : 0
        let over = remaining < 0
        return HStack(spacing: 6) {
            Text(label).hudLabel()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(color.opacity(0.12))
                    Rectangle().fill(over ? Color.eveRed : color.opacity(0.65)).frame(width: geo.size.width * frac)
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .frame(height: 6)
            Text(String(format: "%.1f/%.1f %@", remaining, total, unit))
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle((over ? Color.eveRed : color).opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 92, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(FitTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) { activeTab = tab }
                } label: {
                    VStack(spacing: 0) {
                        Rectangle().fill(activeTab == tab ? Color.eveAmber : Color.clear).frame(height: 2)
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: .semibold)).tracking(1.4)
                            .foregroundStyle(activeTab == tab ? Color.eveAmber : Color.eveText.opacity(0.40))
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.eveCard)
    }

    // MARK: - Tab content

    @ViewBuilder private var tabContent: some View {
        switch activeTab {
        case .modules: modulesTabView
        case .stats:   statsTabView
        }
    }

    // MARK: - Modules tab

    private var modulesTabView: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Slot.allCases, id: \.self) { slot in
                    let items = currentItems.filter { slotFor($0.flag) == slot }
                    let visibleItems = slot == .cargo || slot == .drone ? items : moduleItems(in: slot)
                    if !visibleItems.isEmpty {
                        slotSection(slot, items: items)
                        Color.eveAmber.opacity(0.10).frame(height: 1)
                    }
                }
            }
            .padding(.bottom, 55)
        }
    }

    private func slotSection(_ slot: Slot, items: [ESIFittingItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(slot.rawValue).hudLabel()
                .padding(.horizontal, 20).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.eveCard)
            Color.white.opacity(0.06).frame(height: 1)

            let isGrouped = (slot == .drone || slot == .cargo)
            if isGrouped {
                // Cargo/drones: group by typeId
                let grouped = Dictionary(grouping: items, by: \.typeId)
                ForEach(grouped.keys.sorted(), id: \.self) { typeId in
                    let qty = grouped[typeId]!.reduce(0) { $0 + $1.quantity }
                    groupedRow(typeId: typeId, quantity: qty)
                    Color.white.opacity(0.04).frame(height: 1)
                }
            } else {
                // Module slots: individual rows, each tappable
                ForEach(moduleItems(in: slot).sorted(by: { $0.flag < $1.flag }), id: \.flag) { item in
                    moduleRow(item)
                    Color.white.opacity(0.04).frame(height: 1)
                }
            }
        }
    }

    private func moduleRow(_ item: ESIFittingItem) -> some View {
        let cfg = configs[item.flag] ?? ModuleConfig()
        let isOffline = cfg.state == .offline

        return Button { sheetFlag = FlagItem(id: item.flag) } label: {
            HStack(spacing: 12) {
                EVETypeIcon(typeId: item.typeId, size: 36)
                    .clipShape(CutCorner(size: 5))
                    .overlay(CutCorner(size: 5).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    .opacity(isOffline ? 0.38 : 1.0)

                VStack(alignment: .leading, spacing: 3) {
                    Text(typeName(item.typeId, fallback: "Module \(item.typeId)"))
                        .font(.system(size: 13))
                        .foregroundStyle(isOffline ? Color.eveText.opacity(0.38) : Color.eveText)
                        .lineLimit(1)
                    if let chargeId = cfg.chargeTypeId ?? embeddedCharge(for: item)?.typeId {
                        Text(typeName(chargeId, fallback: "Charge \(chargeId)"))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.eveAmber.opacity(0.65))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // State indicator dot
                Circle()
                    .fill(cfg.state.dotColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: cfg.state.dotColor.opacity(0.8), radius: cfg.state == .offline ? 0 : 4)
            }
            .padding(.horizontal, 20).padding(.vertical, 9)
            .background(Color.eveBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func groupedRow(typeId: Int, quantity: Int) -> some View {
        HStack(spacing: 12) {
            EVETypeIcon(typeId: typeId, size: 32)
                .clipShape(CutCorner(size: 5))
                .overlay(CutCorner(size: 5).stroke(Color.white.opacity(0.08), lineWidth: 1))
            Text(typeName(typeId, fallback: "Item \(typeId)"))
                .font(.system(size: 13)).foregroundStyle(Color.eveText)
            Spacer()
            if quantity > 1 {
                Text("×\(quantity)")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.eveAmber.opacity(0.75))
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 9)
        .background(Color.eveBackground)
    }

    // MARK: - Stats tab

    private var statsTabView: some View {
        ScrollView {
            if let s = stats {
                VStack(spacing: 0) {
                    if let fittingWarning {
                        warningBand(fittingWarning)
                    }
                    fittingSummaryPanel(s)
                    Color.eveAmber.opacity(0.10).frame(height: 1)
                    statsSection("RESISTANCES") { resistanceTable(s) }
                    Color.eveAmber.opacity(0.10).frame(height: 1)
                    statsSection("CAPACITOR") { capSection(s) }
                    Color.eveAmber.opacity(0.10).frame(height: 1)
                    statsSection("FIREPOWER") { firepowerSection(s) }
                    Color.eveAmber.opacity(0.10).frame(height: 1)
                    statsSection("TARGETING") { targetingSection(s) }
                    Color.eveAmber.opacity(0.10).frame(height: 1)
                    statsSection("DRONES") { dronesSection(s) }
                    Color.eveAmber.opacity(0.10).frame(height: 1)
                    statsSection("CARGO") { cargoSection() }
                    Color.eveAmber.opacity(0.10).frame(height: 1)
                    statsSection("MOBILITY") { mobilitySection(s) }
                    Color.eveAmber.opacity(0.10).frame(height: 1)
                    statsSection("FITTING COSTS") { fittingCostsSection(s) }
                }
                .padding(.bottom, 55)
            } else {
                ProgressView().tint(Color.eveCyan).padding(.top, 60)
            }
        }
    }

    private func fittingSummaryPanel(_ s: ShipStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SHIP SYSTEMS").hudLabel()
                Spacer()
                Text(s.capRegenPerSec >= s.capDrainPerSec ? "SYSTEM STABLE" : "SYSTEM UNSTABLE")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(s.capRegenPerSec >= s.capDrainPerSec ? Color.eveGreen : Color.eveRed)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                summaryTile("CAPACITOR", String(format: "%.0f GJ / %.0fs", s.capCapacity, s.capRechargeMs / 1000), Color.eveCyan)
                summaryTile("FIREPOWER", String(format: "%.1f DPS", s.turretDPS + s.missileDPS), Color.eveAmber)
                summaryTile("DEFENSE", String(format: "%@ EHP", hpFmt(s.totalEHP)), Color.eveGreen)
                summaryTile("TARGETING", String(format: "%.1f km · %.0f mm", s.maxTargetRange / 1000, s.scanResolution), Color.eveText)
                summaryTile("MOBILITY", String(format: "%.0f m/s · %.0f m", s.maxVelocity, s.signatureRadius), Color.eveText)
                summaryTile("FITTING", String(format: "CPU %.1f · PG %.1f", s.cpuTotal - s.cpuUsed, s.pgTotal - s.pgUsed), Color.eveCyan)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.eveCard.opacity(0.65))
    }

    private func summaryTile(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).hudLabel()
            Text(value)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func statsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).hudLabel()
                .padding(.horizontal, 20).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.eveCard)
            Color.white.opacity(0.06).frame(height: 1)
            content()
                .padding(.horizontal, 20).padding(.vertical, 12)
        }
    }

    private func warningBand(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.eveAmber)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.eveAmber.opacity(0.10))
    }

    // Resistance table identical to reference app
    private func resistanceTable(_ s: ShipStats) -> some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                Color.clear.frame(width: 28)
                damageHeader("EM",    color: Color(hue: 0.60, saturation: 0.75, brightness: 0.90))
                damageHeader("THERM", color: .eveRed)
                damageHeader("KIN",   color: Color(white: 0.55))
                damageHeader("EXP",   color: .eveAmber)
                Text("HP").hudLabel().frame(width: 60, alignment: .trailing)
            }
            Color.white.opacity(0.07).frame(height: 1).padding(.vertical, 4)

            resistRow(label: "SHI", hp: s.shieldHP, ehp: s.shieldEHP,
                      em: s.shieldEMRes, exp: s.shieldExpRes, kin: s.shieldKinRes, therm: s.shieldThermRes,
                      color: .eveCyan)
            Color.white.opacity(0.05).frame(height: 1)
            resistRow(label: "ARM", hp: s.armorHP, ehp: s.armorEHP,
                      em: s.armorEMRes, exp: s.armorExpRes, kin: s.armorKinRes, therm: s.armorThermRes,
                      color: .eveAmber)
            Color.white.opacity(0.05).frame(height: 1)
            resistRow(label: "HUL", hp: s.hullHP, ehp: s.hullHP,
                      em: s.hullEMRes, exp: s.hullExpRes, kin: s.hullKinRes, therm: s.hullThermRes,
                      color: Color(white: 0.5))

            Color.white.opacity(0.07).frame(height: 1).padding(.top, 6)
            HStack {
                Spacer()
                Text("HP: \(hpFmt(s.shieldHP + s.armorHP + s.hullHP))  |  EHP: \(hpFmt(s.totalEHP))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.eveText.opacity(0.55))
            }
            .padding(.top, 6)
        }
    }

    private func damageHeader(_ label: String, color: Color) -> some View {
        Text(label).font(.system(size: 8, weight: .semibold)).foregroundStyle(color.opacity(0.7))
            .frame(maxWidth: .infinity)
    }

    private func resistRow(label: String, hp: Double, ehp: Double,
                            em: Double, exp: Double, kin: Double, therm: Double,
                            color: Color) -> some View {
        HStack(spacing: 0) {
            Text(label).font(.system(size: 9, weight: .semibold)).tracking(0.8)
                .foregroundStyle(color).frame(width: 28, alignment: .leading)
            resCell(pct: em,    barColor: Color(hue: 0.60, saturation: 0.75, brightness: 0.90))
            resCell(pct: therm, barColor: .eveRed)
            resCell(pct: kin,   barColor: Color(white: 0.55))
            resCell(pct: exp,   barColor: .eveAmber)
            Text(hpFmt(hp))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.eveText)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 5)
    }

    private func resCell(pct: Double, barColor: Color) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%.1f%%", pct))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(resColor(pct))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(barColor.opacity(0.12))
                    Rectangle().fill(barColor.opacity(0.65)).frame(width: geo.size.width * pct / 100)
                }
                .clipShape(RoundedRectangle(cornerRadius: 1.5))
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity)
    }

    private func resColor(_ pct: Double) -> Color {
        if pct >= 60 { return .eveGreen }
        if pct >= 30 { return .eveAmber }
        return Color.eveText.opacity(0.45)
    }

    private func capSection(_ s: ShipStats) -> some View {
        VStack(spacing: 8) {
            HStack {
                statItem("CAPACITY", String(format: "%.0f GJ", s.capCapacity))
                statItem("RECHARGE", String(format: "%.0fs", s.capRechargeMs / 1000))
                statItem("REGEN", String(format: "+%.1f GJ/s", s.capRegenPerSec))
            }
            if s.capDrainPerSec > 0 {
                let net = s.capRegenPerSec - s.capDrainPerSec
                let stable = net >= 0
                HStack {
                    statItem("DRAIN", String(format: "-%.1f GJ/s", s.capDrainPerSec))
                    statItem("NET", String(format: "%+.1f GJ/s", net),
                             color: stable ? .eveGreen : .eveRed)
                    statItem("STABLE", stable ? "YES" : "NO",
                             color: stable ? .eveGreen : .eveRed)
                }
            }
        }
    }

    private func firepowerSection(_ s: ShipStats) -> some View {
        let totalDPS = s.turretDPS + s.missileDPS
        let reloadTotalDPS = s.turretDPS + s.missileReloadDPS
        return VStack(spacing: 6) {
            HStack {
                statItem("TURRETS", s.turretDPS > 0 ? String(format: "%.1f DPS", s.turretDPS) : "—")
                statItem("MISSILES", missileDPSLabel(s), color: s.missileDPS > 0 ? .eveText : .eveText.opacity(0.35))
                statItem("TOTAL", totalDPS > 0 ? String(format: "%.1f (%.1f) DPS", totalDPS, reloadTotalDPS) : "—",
                         color: totalDPS > 0 ? .eveAmber : .eveText.opacity(0.35))
            }
            if s.peakShieldRegen > 0 {
                HStack {
                    statItem("SHI REGEN", String(format: "%.0f HP/s", s.peakShieldRegen))
                    Spacer()
                }
            }
            let chargeNames = selectedChargeNames
            if !chargeNames.isEmpty {
                Text("CHARGE  " + chargeNames.joined(separator: " / "))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.eveAmber.opacity(0.72))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !characterSkills.isEmpty {
                let implantCount = implantTypeProfiles.count
                Text(implantCount > 0
                     ? "Includes skills, implants & module bonuses; boosters/environment not included"
                     : "Includes skills & module bonuses; boosters/environment not included")
                    .font(.system(size: 9)).foregroundStyle(Color.eveText.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func missileDPSLabel(_ s: ShipStats) -> String {
        guard s.missileDPS > 0 else { return "—" }
        if abs(s.missileDPS - s.missileReloadDPS) < 0.05 {
            return String(format: "%.1f DPS", s.missileDPS)
        }
        return String(format: "%.1f (%.1f) DPS", s.missileDPS, s.missileReloadDPS)
    }

    private func mobilitySection(_ s: ShipStats) -> some View {
        HStack {
            statItem("MAX SPEED", String(format: "%.0f m/s", s.maxVelocity))
            statItem("SIGNATURE", String(format: "%.0f m", s.signatureRadius))
            Spacer()
        }
    }

    private func targetingSection(_ s: ShipStats) -> some View {
        VStack(spacing: 8) {
            HStack {
                statItem("RANGE", String(format: "%.1f km", s.maxTargetRange / 1000))
                statItem("SCAN RES", String(format: "%.0f mm", s.scanResolution))
                statItem("LOCKS", String(format: "%.0fx", s.maxLockedTargets))
            }
            HStack {
                statItem("SENSOR", String(format: "%.1f pts", s.sensorStrength))
                Spacer()
            }
        }
    }

    private func dronesSection(_ s: ShipStats) -> some View {
        HStack {
            statItem("BANDWIDTH", String(format: "%.0f Mbit/s", s.droneBandwidth))
            statItem("BAY", String(format: "%.0f m³", s.droneCapacity))
            statItem("RANGE", String(format: "%.1f km", s.droneControlRange / 1000))
        }
    }

    private func cargoSection() -> some View {
        let free = max(0, shipCargoCapacity - cargoUsedVolume)
        return VStack(spacing: 8) {
            HStack {
                statItem("USED", String(format: "%.2f m³", cargoUsedVolume), color: .eveAmber)
                statItem("CAPACITY", shipCargoCapacity > 0 ? String(format: "%.0f m³", shipCargoCapacity) : "—")
                statItem("FREE", shipCargoCapacity > 0 ? String(format: "%.2f m³", free) : "—", color: .eveGreen)
            }
            Text("Cargo items are not applied to ship stats unless selected as a loaded charge.")
                .font(.system(size: 9))
                .foregroundStyle(Color.eveText.opacity(0.36))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func fittingCostsSection(_ s: ShipStats) -> some View {
        let topCPU = s.moduleCosts.sorted { $0.cpu > $1.cpu }.prefix(6)
        let topPG = s.moduleCosts.sorted { $0.pg > $1.pg }.prefix(6)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                statItem("CPU USED", String(format: "%.1f Tf", s.cpuUsed), color: .eveCyan)
                statItem("PG USED", String(format: "%.1f MW", s.pgUsed), color: .eveAmber)
            }

            fittingCostList(title: "TOP CPU", costs: Array(topCPU), value: { $0.cpu }, unit: "Tf", color: .eveCyan)
            Color.white.opacity(0.06).frame(height: 1)
            fittingCostList(title: "TOP PG", costs: Array(topPG), value: { $0.pg }, unit: "MW", color: .eveAmber)
        }
    }

    private func fittingCostList(
        title: String,
        costs: [FittedModuleCost],
        value: @escaping (FittedModuleCost) -> Double,
        unit: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).hudLabel()
            ForEach(costs) { cost in
                HStack(spacing: 8) {
                    Text(cost.flag)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color.eveText.opacity(0.38))
                        .frame(width: 72, alignment: .leading)
                    Text(typeName(cost.typeId, fallback: "Module \(cost.typeId)"))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.eveText.opacity(0.72))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(String(format: "%.1f %@", value(cost), unit))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(color)
                }
            }
        }
    }

    private func statItem(_ label: String, _ value: String, color: Color = .eveText) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).hudLabel()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hpFmt(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1_000     { return String(format: "%.1fK", v / 1_000) }
        return String(format: "%.0f", v)
    }

    // MARK: - Data loading

    private func initialLoad() async {
        guard let repo = env.repository else { return }
        await loadLiveItemsIfCurrentShip()

        // Load all module + ship type profiles (attrs + effect IDs + groupId + requiredSkills)
        let allIds = Set([fit.shipTypeId] + currentItems.map(\.typeId))
        do {
            let profiles = try await repo.typeProfiles(typeIds: allIds)
            moduleTypeProfiles = profiles
        } catch {
            fittingWarning = "WARNING: SDE type profiles failed to load; fitting stats unavailable"
            return
        }
        await resolveLocalNames(repo: repo, typeIds: allIds)

        // Build initial configs: active modules start active; passive fitted items stay online.
        var c: [String: ModuleConfig] = [:]
        for item in currentItems {
            let slot = slotFor(item.flag)
            if slot != .cargo, slot != .drone, isFittedType(item) {
                let attrs = moduleTypeProfiles[item.typeId]?.attrs ?? [:]
                let initialState: ModuleState = DogmaEngine.isActiveModule(attrs) ? .active : .online
                let embedded = embeddedCharge(for: item)
                if let embedded {
                    chargeNames[embedded.typeId] = typeName(embedded.typeId, fallback: "Charge \(embedded.typeId)")
                }
                c[item.flag] = ModuleConfig(state: initialState, chargeTypeId: embedded?.typeId)
            }
        }
        configs = c

        // Auto-load ammo from Cargo into matching weapon slots
        let cargoItems = currentItems.filter { slotFor($0.flag) == .cargo }
        if !cargoItems.isEmpty, let repo = env.repository {
            let weaponItems = currentItems.filter { item in
                let s = slotFor(item.flag)
                return (s == .high || s == .mid) && isFittedType(item)
            }
            for weapon in weaponItems {
                guard configs[weapon.flag]?.chargeTypeId == nil else { continue }
                guard embeddedCharge(for: weapon) == nil else { continue }
                if let compatible = try? await repo.compatibleCharges(weaponTypeId: weapon.typeId) {
                    let compatibleIds = Set(compatible.map(\.id))
                    if let cargo = cargoItems.first(where: { compatibleIds.contains($0.typeId) }) {
                        chargeNames[cargo.typeId] = typeName(cargo.typeId, fallback: "Charge \(cargo.typeId)")
                        for sameWeapon in currentItems where sameWeapon.typeId == weapon.typeId {
                            configs[sameWeapon.flag, default: ModuleConfig()].chargeTypeId = cargo.typeId
                        }
                    }
                }
            }
        }

        // Load character skills and compute skill effect modifier chains
        await loadSkillData(repo: repo)

        await recalcStats()
    }

    private func loadLiveItemsIfCurrentShip() async {
        guard let ship = try? await characterService.currentShip(),
              ship.shipTypeId == fit.shipTypeId,
              let assets = try? await characterService.assets() else { return }

        let children = assets.filter {
            $0.locationType == "item" && $0.locationId == ship.shipItemId
        }
        guard !children.isEmpty else { return }

        let mappedItems = children.map {
            ESIFittingItem(typeId: $0.typeId, flag: $0.locationFlag, quantity: $0.quantity)
        }

        guard ship.shipName == fit.name || fittedSlotsMatch(mappedItems, fit.items) else {
            return
        }

        liveItems = mappedItems
    }

    private func fittedSlotsMatch(_ lhs: [ESIFittingItem], _ rhs: [ESIFittingItem]) -> Bool {
        let left = fittedSlotTypeIds(lhs)
        let right = fittedSlotTypeIds(rhs)
        guard !left.isEmpty, left.keys == right.keys else { return false }
        return left.allSatisfy { flag, typeIds in
            guard let otherTypeIds = right[flag] else { return false }
            return !typeIds.isDisjoint(with: otherTypeIds)
        }
    }

    private func fittedSlotTypeIds(_ items: [ESIFittingItem]) -> [String: Set<Int>] {
        var result: [String: Set<Int>] = [:]
        for item in items {
            switch slotFor(item.flag) {
            case .high, .mid, .low, .rig, .sub:
                result[item.flag, default: []].insert(item.typeId)
            case .drone, .cargo:
                continue
            }
        }
        return result
    }

    private func resolveLocalNames(repo: SDERepository, typeIds: Set<Int>) async {
        for id in typeIds where localTypes[id] == nil {
            if let t = try? await repo.type(id: id) {
                localTypes[id] = t
                if typeNames[id] == nil {
                    localTypeNames[id] = t.name
                }
            }
        }
    }

    private func loadSkillData(repo: SDERepository) async {
        do {
            var warnings: [String] = []
            let skillsResponse = try await characterService.skills()
            characterSkills = Dictionary(uniqueKeysWithValues:
                skillsResponse.skills.map { ($0.skillId, $0.activeSkillLevel) }
            )

            let trainedSkillIds = Set(characterSkills.keys)
            skillTypeProfiles = try await repo.typeProfiles(typeIds: trainedSkillIds)

            do {
                let implantIds = try await characterService.implants()
                if !implantIds.isEmpty {
                    implantTypeProfiles = try await repo.typeProfiles(typeIds: Set(implantIds))
                } else {
                    implantTypeProfiles = [:]
                }
            } catch {
                implantTypeProfiles = [:]
                warnings.append("implants failed to load")
            }

            var allEffectIds = Set(moduleTypeProfiles[fit.shipTypeId]?.effectIds ?? [])
            for profile in skillTypeProfiles.values { allEffectIds.formUnion(profile.effectIds) }
            for profile in implantTypeProfiles.values { allEffectIds.formUnion(profile.effectIds) }

            skillEffectModifiers = try await repo.effectModifiers(effectIds: allEffectIds)
            fittingWarning = warnings.isEmpty
                ? nil
                : "WARNING: \(warnings.joined(separator: ", ")); stats may be incomplete"
        } catch {
            fittingWarning = "WARNING: skills or dogma modifiers failed to load; stats may be incomplete"
        }
    }

    private func recalcStats() async {
        guard !moduleTypeProfiles.isEmpty else { return }
        // Ensure charge attrs and profiles are loaded for any newly selected charges
        let neededChargeIds = Set(configs.values.compactMap(\.chargeTypeId))
        let missing = neededChargeIds.subtracting(Set(chargeTypeAttrs.keys))
        if !missing.isEmpty, let repo = env.repository {
            if let newMaps = try? await repo.typeAttributeMaps(typeIds: missing) {
                for (k, v) in newMaps { chargeTypeAttrs[k] = v }
            }
            if let newProfiles = try? await repo.typeProfiles(typeIds: missing) {
                for (k, v) in newProfiles { chargeTypeProfiles[k] = v }
            }
        }

        // Collect all module + charge effect IDs and merge into effectModifiers
        var allModuleEffectIds = Set(moduleTypeProfiles[fit.shipTypeId]?.effectIds ?? [])
        for item in currentItems where slotFor(item.flag) != .cargo && slotFor(item.flag) != .drone && isFittedType(item) {
            allModuleEffectIds.formUnion(moduleTypeProfiles[item.typeId]?.effectIds ?? [])
        }
        for profile in chargeTypeProfiles.values { allModuleEffectIds.formUnion(profile.effectIds) }
        // Remove effect IDs already in skillEffectModifiers to avoid re-fetching
        let missingEffectIds = allModuleEffectIds.subtracting(Set(skillEffectModifiers.keys))
        var combinedModifiers = skillEffectModifiers
        if !missingEffectIds.isEmpty, let repo = env.repository,
           let moduleModifiers = try? await repo.effectModifiers(effectIds: missingEffectIds) {
            for (k, v) in moduleModifiers { combinedModifiers[k] = v }
        }

        // Build module inputs for the engine
        var inputs: [FittedModuleInput] = []
        for item in currentItems {
            let slot = slotFor(item.flag)
            guard slot != .cargo, slot != .drone, isFittedType(item) else { continue }
            let cfg = configs[item.flag] ?? ModuleConfig()
            let embedded = embeddedCharge(for: item)
            let chargeTypeId = cfg.chargeTypeId ?? embedded?.typeId
            let cAttrs = chargeTypeId.flatMap { chargeTypeAttrs[$0] ?? moduleTypeProfiles[$0]?.attrs }
            let cProfile = chargeTypeId.flatMap { chargeTypeProfiles[$0] ?? moduleTypeProfiles[$0] }
            let cSkills = chargeTypeId.flatMap {
                chargeTypeProfiles[$0]?.requiredSkillIds ?? moduleTypeProfiles[$0]?.requiredSkillIds
            } ?? []
            inputs.append(FittedModuleInput(
                flag: item.flag, typeId: item.typeId,
                state: cfg.state, chargeTypeId: chargeTypeId,
                chargeAttrs: cAttrs, chargeProfile: cProfile,
                chargeRequiredSkillIds: cSkills,
                moduleCapacity: localTypes[item.typeId]?.capacity ?? 0,
                chargeVolume: chargeTypeId.flatMap { localTypes[$0]?.volume } ?? 0
            ))
        }

        stats = DogmaEngine.calculate(
            shipProfile: moduleTypeProfiles[fit.shipTypeId] ?? .empty,
            moduleProfiles: moduleTypeProfiles,
            modules: inputs,
            characterSkills: characterSkills,
            skillProfiles: skillTypeProfiles,
            implantProfiles: implantTypeProfiles,
            effectModifiers: combinedModifiers
        )
    }
}

// MARK: - Module Setting Sheet

struct ModuleSettingSheet: View {
    let item: ESIFittingItem
    let typeName: String
    let moduleAttrs: [Int: Double]
    @Binding var config: ModuleConfig
    @Binding var chargeNames: [Int: String]
    @Binding var chargeTypeAttrs: [Int: [Int: Double]]
    /// Called when a charge is selected; allows the caller to broadcast to all identical weapons.
    var onChargeSelected: ((ItemType, [Int: Double]) -> Void)? = nil

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var showChargePicker = false

    private var isWeapon: Bool {
        [604, 605, 606, 609].contains { (moduleAttrs[$0] ?? 0) > 0 }
    }
    private var pgCost: Double  { moduleAttrs[30] ?? 0 }
    private var cpuCost: Double { moduleAttrs[50] ?? 0 }

    private var isActiveMod: Bool {
        DogmaEngine.isActiveModule(moduleAttrs)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.eveBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {

                        // Module info card
                        HStack(spacing: 14) {
                            EVETypeIcon(typeId: item.typeId, size: 52)
                                .clipShape(CutCorner(size: 8))
                                .overlay(CutCorner(size: 8).stroke(Color.eveAmber.opacity(0.25), lineWidth: 1))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(typeName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.eveText)
                                HStack(spacing: 12) {
                                    if pgCost > 0 {
                                        Label(String(format: "%.0f MW", pgCost), systemImage: "bolt.fill")
                                            .font(.system(size: 10)).foregroundStyle(Color.eveAmber.opacity(0.75))
                                    }
                                    if cpuCost > 0 {
                                        Label(String(format: "%.0f Tf", cpuCost), systemImage: "cpu")
                                            .font(.system(size: 10)).foregroundStyle(Color.eveCyan.opacity(0.75))
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding(20)

                        Color.eveAmber.opacity(0.12).frame(height: 1)

                        // State picker
                        VStack(alignment: .leading, spacing: 10) {
                            Text("MODULE STATE").hudLabel()
                            HStack(spacing: 8) {
                                ForEach(ModuleState.allCases, id: \.self) { state in
                                    let enabled = state != .overload || isActiveMod
                                    Button {
                                        guard enabled else { return }
                                        config.state = state
                                    } label: {
                                        Text(state.rawValue)
                                            .font(.system(size: 10, weight: .semibold))
                                            .tracking(0.8)
                                            .foregroundStyle(
                                                !enabled ? Color.eveText.opacity(0.20) :
                                                config.state == state ? Color.eveBackground : Color.eveText.opacity(0.60)
                                            )
                                            .padding(.horizontal, 10).padding(.vertical, 6)
                                            .background(
                                                config.state == state ? state.dotColor : Color.white.opacity(0.06)
                                            )
                                            .clipShape(CutCorner(size: 4))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!enabled)
                                }
                            }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 14)

                        if isWeapon {
                            Color.eveAmber.opacity(0.12).frame(height: 1)

                            // Charge section
                            VStack(alignment: .leading, spacing: 10) {
                                Text("AMMO / CHARGE").hudLabel()

                                NavigationLink {
                                    ChargePickerView(
                                        weaponTypeId: item.typeId,
                                        selectedChargeId: config.chargeTypeId
                                    ) { charge, attrs in
                                        config.chargeTypeId = charge.id
                                        if let broadcast = onChargeSelected {
                                            broadcast(charge, attrs)
                                        } else {
                                            chargeNames[charge.id] = charge.name
                                            chargeTypeAttrs[charge.id] = attrs
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text("Charge")
                                            .font(.system(size: 13)).foregroundStyle(Color.eveText)
                                        Spacer()
                                        if let cid = config.chargeTypeId, let name = chargeNames[cid] {
                                            Text(name)
                                                .font(.system(size: 12)).foregroundStyle(Color.eveAmber)
                                                .lineLimit(1)
                                        } else {
                                            Text("None").font(.system(size: 12)).foregroundStyle(Color.eveText.opacity(0.35))
                                        }
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Color.eveText.opacity(0.30))
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(Color.eveCard)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)

                                if let cid = config.chargeTypeId,
                                   let attrs = chargeTypeAttrs[cid] {
                                    ChargeDamageBreakdown(profile: ChargeDamageProfile(attrs: attrs))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(Color.eveCard.opacity(0.65))
                                        .clipShape(CutCorner(size: 6))
                                }

                                if config.chargeTypeId != nil {
                                    Button {
                                        config.chargeTypeId = nil
                                    } label: {
                                        Text("Clear Charge")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Color.eveRed)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20).padding(.vertical, 14)
                        }
                    }
                }
            }
            .navigationTitle("MODULE SETTING")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.eveBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.eveCyan)
                }
            }
        }
    }
}

// MARK: - Charge Picker

struct ChargePickerView: View {
    let weaponTypeId: Int
    let selectedChargeId: Int?
    let onSelect: (ItemType, [Int: Double]) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var charges: [ItemType] = []
    @State private var chargeAttrMaps: [Int: [Int: Double]] = [:]
    @State private var isLoading = true
    @State private var search = ""

    private var filtered: [ItemType] {
        if search.isEmpty { return charges }
        return charges.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ZStack {
            Color.eveBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.eveText.opacity(0.40))
                    TextField("Search", text: $search)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.eveText)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color.eveCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16).padding(.vertical, 10)

                Color.eveAmber.opacity(0.12).frame(height: 1)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if filtered.isEmpty && !isLoading {
                            ContentUnavailableView("No Compatible Charges",
                                systemImage: "xmark.circle",
                                description: Text("No ammunition found for this weapon."))
                            .foregroundStyle(Color.eveText)
                            .padding(.top, 40)
                        }
                        ForEach(filtered, id: \.id) { charge in
                            chargeRow(charge)
                            Color.white.opacity(0.04).frame(height: 1)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            if isLoading { ProgressView().tint(Color.eveCyan) }
        }
        .navigationTitle("SELECT CHARGE")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.eveBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await loadCharges() }
    }

    private func chargeRow(_ charge: ItemType) -> some View {
        let isSelected = charge.id == selectedChargeId
        let attrs = chargeAttrMaps[charge.id] ?? [:]
        let damage = ChargeDamageProfile(attrs: attrs)

        return Button {
            onSelect(charge, attrs)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                EVETypeIcon(typeId: charge.id, size: 36)
                    .clipShape(CutCorner(size: 5))
                    .overlay(CutCorner(size: 5).stroke(
                        isSelected ? Color.eveAmber.opacity(0.5) : Color.white.opacity(0.07),
                        lineWidth: 1))

                VStack(alignment: .leading, spacing: 3) {
                    Text(charge.name)
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? Color.eveAmber : Color.eveText)
                        .lineLimit(1)
                    ChargeDamageBreakdown(profile: damage, compact: true)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.eveAmber)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 9)
            .background(Color.eveBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadCharges() async {
        isLoading = true; defer { isLoading = false }
        guard let repo = env.repository else { return }
        charges = (try? await repo.compatibleCharges(weaponTypeId: weaponTypeId)) ?? []
        let ids = Set(charges.map(\.id))
        if let maps = try? await repo.typeAttributeMaps(typeIds: ids) {
            chargeAttrMaps = maps
        }
    }
}

// MARK: - ModuleState dot color

extension ModuleState {
    var dotColor: Color {
        switch self {
        case .offline:  return Color(white: 0.28)
        case .online:   return Color(white: 0.55)
        case .active:   return .eveCyan
        case .overload: return .eveAmber
        }
    }
}
