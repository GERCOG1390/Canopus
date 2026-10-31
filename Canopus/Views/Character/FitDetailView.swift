// The fit screen (the desktop's FittingPage): ship card, metrics, the modules / stats / tools tabs.
// The modules tab is in FitDetailView+Modules.swift, stats and tools in FitDetailView+Stats.swift.

import SwiftUI
import EVEAuth
import EVEStaticData
import Domain
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Fit Detail

struct FitDetailView: View {
    let fit: ESIFitting
    let typeNames: [Int: String]
    let characterService: CharacterService
    /// The fittings list that opened this fit (to tell the pilot closing it from SwiftUI rebuilding it).
    var listId: UUID? = nil
    /// Continue from the saved draft of this fit (it was reopened after a rebuild).
    var restoreDraft = false

    @Environment(AppEnvironment.self) var env
    @State var configs: [String: ModuleConfig] = [:]
    @State var stats: ShipStats?
    /// The engine's full result, for the stats tab.
    @State var fitStats: JSFitStats?
    /// The engine's per-module problems (wrong ship, rig size, group limits), by slot flag.
    @State var moduleProblems: [String: [String]] = [:]
    /// The spec the stats were calculated for (the snapshot draws it).
    @State var fitSpec: JSFitSpec?
    @State var fitShot: FitShotData?
    @State var preparingShot = false
    /// Slots whose identical modules are shown one per row (the desktop's expanded groups).
    @State var expandedSlots: Set<String> = []
    /// Drones launched per type when the pilot changed it (otherwise five in all, first stacks first).
    @State var droneActive: [Int: Int] = [:]
    /// A fit opened from the tools (popular fits).
    @State var toolFit: DraftFitRoute?
    @State var moduleTypeProfiles: [Int: TypeProfile] = [:]
    @State var chargeTypeAttrs: [Int: [Int: Double]] = [:]
    @State var chargeNames: [Int: String] = [:]
    @State var sheetFlag: FlagItem? = nil
    @State var activeTab: FitTab = {
        #if DEBUG
        // Debug builds: `-fitTab stats` opens a fit on its stats tab (screenshots, UI checks).
        if let tab = UserDefaults.standard.string(forKey: "fitTab").flatMap({ FitTab(rawValue: $0.uppercased()) }) { return tab }
        #endif
        return .modules
    }()
    @State var characterSkills: [Int: Int] = [:]
    @State var implantIds: [Int] = []
    /// Start state and overload ability per module type (the desktop's rules).
    @State var activation: [Int: ModuleActivation] = [:]
    @State var liveItems: [ESIFittingItem]?
    @State var localTypeNames: [Int: String] = [:]
    @State var localTypes: [Int: ItemType] = [:]
    @State var fittingWarning: String?
    @State var fitSkillRecommendations: [FitSkillRecommendation] = []
    @State var isSendingToEVE = false
    @State var fittingSendStatus: FittingSendStatus?
    // Prevents .onChange from triggering recalcStats before skills are loaded
    @State var skillsReady = false
    @State var editableItems: [ESIFittingItem]?
    @State var modulePickerSlot: SlotSelection?
    @State var exportSheet: FittingTextSheet?
    @State var recalcTask: Task<Void, Never>?
    /// Set once the fit is loaded: from then on every change is kept in the draft.
    @State var draftReady = false

    enum StatIcon {
        static let capacitorCapacity = 1668
        static let capacitorRecharge = 1392
        static let capacitorDrain = 1400
        static let firepower = 1432
        static let targeting = 1391
        static let mobility = 1389
        static let fitting = 1405
        static let powergrid = 1400
        static let cpu = 1405
        static let shield = 1384
        static let armor = 1383
        static let structure = 67
        static let emResistance = 1396
        static let thermalResistance = 1394
        static let kineticResistance = 1393
        static let explosiveResistance = 1395
        static let signature = 1390
        static let scanResolution = 74
        static let locks = 109
        static let radarSensor = 2031
        static let drones = 2987
        static let cargo = 71
    }

    var currentItems: [ESIFittingItem] {
        editableItems ?? liveItems ?? fit.items
    }

    func typeName(_ typeId: Int, fallback: String) -> String {
        localTypes[typeId]?.name ?? localTypeNames[typeId] ?? typeNames[typeId] ?? fallback
    }

    var cargoUsedVolume: Double {
        currentItems
            .filter { slotFor($0.flag) == .cargo }
            .reduce(0) { total, item in
                total + (localTypes[item.typeId]?.volume ?? 0) * Double(item.quantity)
            }
    }

    var shipRigSize: Int? {
        moduleTypeProfiles[fit.shipTypeId]?.attrs[1547].map { Int($0.rounded()) }
    }

    var supportsSubsystemSlots: Bool {
        moduleTypeProfiles[fit.shipTypeId]?.groupId == 963 || !moduleItems(in: .sub).isEmpty
    }

    var displayedSlots: [Slot] {
        Slot.allCases.filter { slot in
            slot != .sub || supportsSubsystemSlots
        }
    }

    enum FitTab: String, CaseIterable { case modules = "MODULES"; case stats = "STATS"; case tools = "TOOLS" }

    // MARK: - Slot classification

    enum Slot: String, CaseIterable {
        case high = "HIGH SLOTS", mid = "MID SLOTS", low = "LOW SLOTS"
        case rig = "RIGS", sub = "SUBSYSTEMS", drone = "DRONES", cargo = "CARGO"

        var shortTitle: String {
            switch self {
            case .high: return "High Slot"
            case .mid: return "Mid Slot"
            case .low: return "Low Slot"
            case .rig: return "Rig"
            case .sub: return "Subsystem"
            case .drone: return "Drone"
            case .cargo: return "Cargo"
            }
        }

        var acceptedEffectIds: Set<Int> {
            switch self {
            case .low: return [11]
            case .high: return [12]
            case .mid: return [13]
            case .rig: return [2663]
            case .sub: return [3772]
            case .drone, .cargo: return []
            }
        }

        var shipSlotAttributeId: Int? {
            switch self {
            case .low: return 12
            case .mid: return 13
            case .high: return 14
            case .rig: return 1137
            case .sub: return 1367
            case .drone, .cargo: return nil
            }
        }

        var flagPrefix: String? {
            switch self {
            case .high: return "HiSlot"
            case .mid: return "MedSlot"
            case .low: return "LoSlot"
            case .rig: return "RigSlot"
            case .sub: return "SubSystemSlot"
            case .drone, .cargo: return nil
            }
        }

        var pickerRootMarketGroupId: Int? {
            switch self {
            case .sub: return 1112
            case .rig: return 1111
            case .high, .mid, .low: return 9
            case .drone, .cargo: return nil
            }
        }
    }

    struct SlotSelection: Identifiable {
        let slot: Slot
        let preferredFlag: String?
        let requiredSubsystemSlotId: Int?

        init(slot: Slot, preferredFlag: String?, requiredSubsystemSlotId: Int? = nil) {
            self.slot = slot
            self.preferredFlag = preferredFlag
            self.requiredSubsystemSlotId = requiredSubsystemSlotId
        }

        var id: String { "\(slot.rawValue)-\(preferredFlag ?? "next")-\(requiredSubsystemSlotId ?? 0)" }
    }

    enum FitSkillPriority: Int {
        case critical = 0
        case performance = 1
    }

    enum WeaponHardpointKind {
        case turret
        case launcher
    }

    enum FitSkillCategory: Int, CaseIterable {
        case critical = 0
        case required = 1
        case ship = 2
        case weapons = 3
        case tank = 4
        case capacitor = 5
        case mobility = 6
        case fitting = 7
        case drones = 8
        case modules = 9

        var title: String {
            switch self {
            case .critical: return "CRITICAL"
            case .required: return "REQUIRED"
            case .ship: return "SHIP"
            case .weapons: return "WEAPONS"
            case .tank: return "TANK"
            case .capacitor: return "CAPACITOR"
            case .mobility: return "MOBILITY"
            case .fitting: return "FITTING"
            case .drones: return "DRONES"
            case .modules: return "MODULES"
            }
        }

        var color: Color {
            switch self {
            case .critical: return .eveRed
            case .required: return .eveAmber
            case .ship: return .eveGreen
            case .weapons: return .eveAmber
            case .tank: return .eveGreen
            case .capacitor: return .eveCyan
            case .mobility: return .eveText
            case .fitting: return .eveCyan
            case .drones: return .eveAmber
            case .modules: return .eveCyan
            }
        }
    }

    struct FitSkillRecommendation: Identifiable {
        var id: String { "\(priority.rawValue)-\(category.rawValue)-\(skillId)" }
        let skillId: Int
        let name: String
        let currentLevel: Int
        let targetLevel: Int
        let priority: FitSkillPriority
        let category: FitSkillCategory
        let reason: String
    }

struct FittingTextSheet: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}

struct FittingSendStatus: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct SubsystemSlotDefinition: Identifiable {
    let dogmaSlotId: Int
    let flagIndex: Int
    let title: String

    var id: Int { dogmaSlotId }
    var flag: String { "SubSystemSlot\(flagIndex)" }
}

    func slotFor(_ flag: String) -> Slot {
        if flag.hasPrefix("HiSlot")    { return .high }
        if flag.hasPrefix("MedSlot")   { return .mid }
        if flag.hasPrefix("LoSlot")    { return .low }
        if flag.hasPrefix("RigSlot")   { return .rig }
        if flag.hasPrefix("SubSystem") { return .sub }
        if flag == "DroneBay" || flag == "FighterBay" { return .drone }
        return .cargo
    }

    func isFittedType(_ item: ESIFittingItem) -> Bool {
        guard let profile = moduleTypeProfiles[item.typeId] else {
            let slot = slotFor(item.flag)
            return slot != .cargo && slot != .drone
        }

        return !profile.effectIds.isDisjoint(with: [11, 12, 13, 2663, 3772])
    }

    func isChargeType(_ item: ESIFittingItem) -> Bool {
        moduleTypeProfiles[item.typeId]?.effectIds.contains(9) == true
    }

    func moduleItem(for flag: String) -> ESIFittingItem? {
        currentItems.first { $0.flag == flag && isFittedType($0) }
    }

    func embeddedCharge(for item: ESIFittingItem) -> ESIFittingItem? {
        currentItems.first { $0.flag == item.flag && $0.typeId != item.typeId && isChargeType($0) }
    }

    func moduleItems(in slot: Slot) -> [ESIFittingItem] {
        let items = currentItems.filter { slotFor($0.flag) == slot }
        guard slot != .cargo && slot != .drone else { return items }
        return items.filter(isFittedType)
    }

    var subsystemSlotDefinitions: [SubsystemSlotDefinition] {
        [
            SubsystemSlotDefinition(dogmaSlotId: 125, flagIndex: 0, title: "Core"),
            SubsystemSlotDefinition(dogmaSlotId: 126, flagIndex: 1, title: "Defensive"),
            SubsystemSlotDefinition(dogmaSlotId: 127, flagIndex: 2, title: "Offensive"),
            SubsystemSlotDefinition(dogmaSlotId: 128, flagIndex: 3, title: "Propulsion")
        ]
    }

    func subsystemDogmaSlotId(for item: ESIFittingItem) -> Int? {
        moduleTypeProfiles[item.typeId]?.attrs[1366].map { Int($0.rounded()) }
    }

    func slotCapacity(_ slot: Slot) -> Int? {
        if slot == .sub {
            return supportsSubsystemSlots ? subsystemSlotDefinitions.count : nil
        }

        if let stats {
            let value: Double?
            switch slot {
            case .high: value = stats.highSlots
            case .mid: value = stats.mediumSlots
            case .low: value = stats.lowSlots
            case .rig: value = stats.rigSlots
            case .sub, .drone, .cargo: value = nil
            }
            if let value {
                return max(0, Int(value.rounded()))
            }
        }

        guard let attrId = slot.shipSlotAttributeId,
              let value = moduleTypeProfiles[fit.shipTypeId]?.attrs[attrId] else {
            return nil
        }
        return max(0, Int(value.rounded()))
    }

    func emptySlotFlags(for slot: Slot) -> [String] {
        if slot == .sub {
            guard supportsSubsystemSlots else { return [] }
            let usedDogmaSlots = Set(moduleItems(in: .sub).compactMap(subsystemDogmaSlotId))
            return subsystemSlotDefinitions
                .filter { !usedDogmaSlots.contains($0.dogmaSlotId) }
                .map(\.flag)
        }

        guard let capacity = slotCapacity(slot),
              let prefix = slot.flagPrefix else {
            return []
        }

        let usedIndexes = Set(moduleItems(in: slot).compactMap { item in
            Int(item.flag.replacingOccurrences(of: prefix, with: ""))
        })

        return (0..<capacity)
            .filter { !usedIndexes.contains($0) }
            .map { "\(prefix)\($0)" }
    }

    func hardpointCapacity(_ kind: WeaponHardpointKind) -> Int {
        let attrId: Int
        switch kind {
        case .launcher: attrId = 101
        case .turret: attrId = 102
        }
        // T3 cruisers get their hardpoints from subsystems (hardPointModifierEffect: launchers +attr 1369,
        // turrets +attr 1368), as the engine counts them.
        let subsystemAttr = kind == .launcher ? 1369 : 1368
        let fromSubsystems = currentItems
            .filter { slotFor($0.flag) == .sub }
            .reduce(0.0) { $0 + (moduleTypeProfiles[$1.typeId]?.attrs[subsystemAttr] ?? 0) }
        return Int(((moduleTypeProfiles[fit.shipTypeId]?.attrs[attrId] ?? 0) + fromSubsystems).rounded())
    }

    /// The hardpoint a module takes, by the effects the game uses: turretFitted (42) / launcherFitted (40).
    /// Probe launchers, cynos and the like have neither and fit in any high slot.
    func weaponHardpointKind(for typeId: Int) -> WeaponHardpointKind? {
        guard let effects = moduleTypeProfiles[typeId]?.effectIds else { return nil }
        if effects.contains(42) { return .turret }
        if effects.contains(40) { return .launcher }
        return nil
    }

    func fittedHardpointCount(_ kind: WeaponHardpointKind, excluding flag: String? = nil) -> Int {
        moduleItems(in: .high)
            .filter { $0.flag != flag }
            .filter { weaponHardpointKind(for: $0.typeId) == kind }
            .count
    }

    func hardpointValidationMessage(for typeId: Int, replacing flag: String? = nil) -> String? {
        guard let kind = weaponHardpointKind(for: typeId) else { return nil }
        let capacity = hardpointCapacity(kind)
        guard capacity > 0 else {
            switch kind {
            case .turret: return String(localized: "\(typeName(fit.shipTypeId, fallback: "Ship")) has no turret hardpoints.")
            case .launcher: return String(localized: "\(typeName(fit.shipTypeId, fallback: "Ship")) has no launcher hardpoints.")
            }
        }

        let used = fittedHardpointCount(kind, excluding: flag)
        guard used < capacity else {
            switch kind {
            case .turret: return String(localized: "Turret hardpoints full: \(used)/\(capacity).")
            case .launcher: return String(localized: "Launcher hardpoints full: \(used)/\(capacity).")
            }
        }
        return nil
    }

    func subsystemDefinition(for flag: String) -> SubsystemSlotDefinition? {
        subsystemSlotDefinitions.first { $0.flag == flag }
    }

    func subsystemDefinition(dogmaSlotId: Int) -> SubsystemSlotDefinition? {
        subsystemSlotDefinitions.first { $0.dogmaSlotId == dogmaSlotId }
    }

    func occupiedSubsystemDogmaSlotIds(excluding allowedSlotId: Int?) -> Set<Int> {
        Set(moduleItems(in: .sub).compactMap { item in
            let slotId = subsystemDogmaSlotId(for: item)
            return slotId == allowedSlotId ? nil : slotId
        })
    }

    func firstOpenSubsystemDefinition() -> SubsystemSlotDefinition? {
        let usedDogmaSlots = occupiedSubsystemDogmaSlotIds(excluding: nil)
        return subsystemSlotDefinitions.first { !usedDogmaSlots.contains($0.dogmaSlotId) }
    }

    func openPicker(for slot: Slot, preferredFlag: String? = nil, requiredSubsystemSlotId: Int? = nil) {
        if slot == .sub {
            let definition = requiredSubsystemSlotId
                .flatMap(subsystemDefinition(dogmaSlotId:))
                ?? preferredFlag.flatMap(subsystemDefinition(for:))
                ?? firstOpenSubsystemDefinition()
            guard let definition else { return }
            modulePickerSlot = SlotSelection(
                slot: .sub,
                preferredFlag: preferredFlag ?? definition.flag,
                requiredSubsystemSlotId: definition.dogmaSlotId
            )
            return
        }

        modulePickerSlot = SlotSelection(slot: slot, preferredFlag: preferredFlag)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            shipHeader
            if let s = fitStats { metricsStrip(s) }
            tabBar
            EVESeparator(kind: .section)
            tabContent
        }
        .background(Color.eveBackground.ignoresSafeArea())
        .navigationTitle(fit.name.uppercased())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.eveBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task {
                            // EFT is read by the game and other tools: English names whatever the app shows.
                            let ids = Set([fit.shipTypeId] + currentItems.map(\.typeId) + configs.values.compactMap(\.chargeTypeId))
                            let english = (try? await env.repository?.englishNames(ids: ids)) ?? [:]
                            exportSheet = FittingTextSheet(title: "EXPORT FIT", text: exportEFT(english: english))
                        }
                    } label: {
                        Text("Export EFT")
                    }

                    Button {
                        Task { await sendFittingToEVE() }
                    } label: {
                        Text("Send to EVE")
                    }
                    .disabled(isSendingToEVE)

                    Button {
                        Task { await openFitShot() }
                    } label: {
                        Text("Fit snapshot")
                    }
                    .disabled(fitStats == nil || preparingShot)
                } label: {
                    if isSendingToEVE || preparingShot {
                        ProgressView()
                            .tint(Color.eveCyan)
                    } else {
                        Text("Export").font(.ui(14, .medium))
                    }
                }
                .foregroundStyle(Color.eveCyan)

                Menu {
                    ForEach(displayedSlots, id: \.self) { slot in
                        Button("Add \(slot.shortTitle)") {
                            openPicker(for: slot)
                        }
                    }
                } label: {
                    Text("+").font(.ui(22, .medium))
                }
                .foregroundStyle(Color.eveAmber)
            }
        }
        .sheet(item: $toolFit) { route in
            NavigationStack {
                FitDetailView(fit: route.fit, typeNames: route.typeNames, characterService: characterService)
            }
            .presentationSizing(.page)
        }
        .sheet(item: $fitShot) { shot in
            NavigationStack { FitShotSheet(data: shot) }
                .presentationSizing(.page)
        }
        .sheet(item: $sheetFlag) { flagItem in
            if let item = moduleItem(for: flagItem.id) {
                ModuleSettingSheet(
                    item: item,
                    typeName: typeName(item.typeId, fallback: "Module \(item.typeId)"),
                    moduleAttrs: moduleTypeProfiles[item.typeId]?.attrs ?? [:],
                    moduleEffectIds: moduleTypeProfiles[item.typeId]?.effectIds ?? [],
                    config: Binding(
                        get: { configs[flagItem.id] ?? ModuleConfig() },
                        set: { new in for f in flagItem.group.isEmpty ? [flagItem.id] : flagItem.group { configs[f] = new } }
                    ),
                    chargeNames: $chargeNames,
                    chargeTypeAttrs: $chargeTypeAttrs,
                    onRemove: {
                        removeItem(flag: item.flag, typeId: item.typeId)
                    },
                    onChargeSelected: { charge, attrs in
                        // Apply the selected charge to all weapons of the same type in this fit
                        for sameItem in currentItems where sameItem.typeId == item.typeId {
                            configs[sameItem.flag, default: ModuleConfig()].chargeTypeId = charge.id
                        }
                        localTypes[charge.id] = charge
                        chargeNames[charge.id] = charge.name
                        chargeTypeAttrs[charge.id] = attrs
                    },
                    canOverload: activation[item.typeId]?.overloadable ?? false
                )
            }
        }
        .sheet(item: $modulePickerSlot) { selection in
            NavigationStack {
                ModulePickerView(
                    slotTitle: selection.slot.shortTitle,
                    acceptedEffectIds: selection.slot.acceptedEffectIds,
                    rootMarketGroupId: selection.slot.pickerRootMarketGroupId,
                    compatibleShipTypeId: selection.slot == .sub ? fit.shipTypeId : nil,
                    requiredRigSize: selection.slot == .rig ? shipRigSize : nil,
                    requiredSubsystemSlotId: selection.requiredSubsystemSlotId,
                    occupiedSubsystemSlotIds: selection.slot == .sub ? occupiedSubsystemDogmaSlotIds(excluding: selection.requiredSubsystemSlotId) : []
                ) { type in
                    addType(type, to: selection.slot, preferredFlag: selection.preferredFlag)
                    modulePickerSlot = nil
                }
            }
        }
        .sheet(item: $exportSheet) { sheet in
            NavigationStack {
                FitTextSheet(title: sheet.title, text: sheet.text)
            }
        }
        .alert(item: $fittingSendStatus) { status in
            Alert(
                title: Text(status.title),
                message: Text(status.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .task(id: env.repositoryVersion) { await initialLoad() }
        .onChange(of: configs) { _, _ in
            saveDraft()
            guard skillsReady else { return }
            scheduleFitRefresh()
        }
        .onChange(of: draftSnapshot) { _, _ in saveDraft() }
        .onChange(of: droneActive) { _, _ in saveDraft() }
        .onAppear { if let listId { FitDraftStore.shared.setOpen(listId) } }
        .onDisappear {
            recalcTask?.cancel()
            recalcTask = nil
            // Closed by the pilot when the list that opened it is still there; otherwise SwiftUI rebuilt
            // the screen and the new list reopens the fit.
            if let listId {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    if FitListToken.live.contains(listId), FitDraftStore.shared.openFrom == listId { FitDraftStore.shared.setOpen(nil) }
                }
            }
        }
    }

    // MARK: - Draft (kept outside the screen, as the desktop's FittingProvider)

    var draftSnapshot: [FitDraft.Item] {
        currentItems.map { FitDraft.Item(typeId: $0.typeId, flag: $0.flag, quantity: $0.quantity) }
    }

    func saveDraft() {
        guard draftReady else { return }
        var names = typeNames
        for (id, t) in localTypes { names[id] = t.name }
        names.merge(localTypeNames) { a, _ in a }
        let items = draftSnapshot
        let used = Set(items.map(\.typeId)).union([fit.shipTypeId])
        FitDraftStore.shared.save(FitDraft(
            fittingId: fit.fittingId, name: fit.name, description: fit.description, shipTypeId: fit.shipTypeId,
            items: items,
            configs: configs.mapValues { FitDraft.Config(state: $0.state.rawValue, chargeTypeId: $0.chargeTypeId) },
            droneActive: droneActive,
            typeNames: names.filter { used.contains($0.key) }
        ))
    }

    // MARK: - Ship header (the desktop's fit-ship card)

    var shipHeader: some View {
        HStack(spacing: 12) {
            NavigationLink { TypeDetailView(typeId: fit.shipTypeId, typeName: typeName(fit.shipTypeId, fallback: "")) } label: {
                EVERenderImage(typeId: fit.shipTypeId, size: 72).clipShape(EVECut())
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: fit.name).font(.display(18)).foregroundStyle(C.text).lineLimit(2)
                Text(verbatim: typeName(fit.shipTypeId, fallback: "")).font(.ui(13)).foregroundStyle(C.accentText)
                HStack(spacing: 6) {
                    Pill(text: liveItems == nil ? String(localized: "Saved fit") : String(localized: "Live ship"), color: liveItems == nil ? C.muted : C.good)
                    Text(characterSkills.isEmpty ? "Skills: all V" : "Skills: \(characterService.tokens.characterName)")
                        .font(.ui(11)).foregroundStyle(C.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(C.panel)
    }

    // MARK: - Metrics (the desktop's FitMetrics: the numbers a pilot checks first)

    func metricsStrip(_ s: JSFitStats) -> some View {
        HStack(spacing: 6) {
            metric("DPS", Text(verbatim: s.offense.totalDps.formatted(.number.precision(.fractionLength(0...1)))), color: C.accentText)
            metric("EHP", Text(verbatim: s.defense.ehp.formatted(.number.precision(.fractionLength(0)))), color: C.text)
            resource("CPU", s.ship.cpu)
            resource("PG", s.ship.power)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(C.nav)
    }

    func metric(_ label: LocalizedStringKey, _ value: Text, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.ui(10, .medium)).tracking(1.2).textCase(.uppercase).foregroundStyle(C.muted)
            value.font(.display(17)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(C.card, in: EVECut())
    }

    /// Used / total with a bar; amber when nearly full, red when over (the desktop's ResourceCard).
    func resource(_ label: LocalizedStringKey, _ u: JSFitStats.Use) -> some View {
        let over = u.used > u.total + 1e-6
        let near = !over && u.total > 0 && u.total - u.used < u.total * 0.03
        let color = over ? C.bad : near ? C.warn : C.accent
        return VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.ui(10, .medium)).tracking(1.2).textCase(.uppercase).foregroundStyle(C.muted)
            Text(verbatim: "\(u.used.formatted(.number.precision(.fractionLength(0...1)))) / \(u.total.formatted(.number.precision(.fractionLength(0...1))))")
                .font(.mono(12, medium: true)).foregroundStyle(over ? C.bad : C.text).lineLimit(1).minimumScaleFactor(0.6)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(C.panel2)
                    Rectangle().fill(color).frame(width: g.size.width * min(1, u.total > 0 ? u.used / u.total : 0))
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(C.card, in: EVECut())
    }

    // MARK: - Tab bar

    var tabBar: some View {
        CanopusTabs(tabs: [(id: FitTab.modules, label: "Modules"), (id: FitTab.stats, label: "Stats"), (id: FitTab.tools, label: "Tools")], selection: $activeTab)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(C.nav)
    }

    // MARK: - Tab content

    @ViewBuilder private var tabContent: some View {
        switch activeTab {
        case .modules: modulesTabView
        case .stats:   statsTabView
        case .tools:   toolsTabView
        }
    }

    // MARK: - Data loading

    func initialLoad() async {
        guard let repo = env.repository else { return }
        let saved = restoreDraft ? FitDraftStore.shared.draft(for: fit.fittingId) : nil
        if let saved, editableItems == nil {
            editableItems = saved.fitting.items
            droneActive = saved.droneActive
        } else {
            await loadLiveItemsIfCurrentShip()
        }
        if editableItems == nil {
            editableItems = liveItems ?? fit.items
        }

        // Load all module + ship type profiles (attrs + effect IDs + groupId + requiredSkills)
        let allIds = Set([fit.shipTypeId] + currentItems.map(\.typeId))
        do {
            let profiles = try await repo.typeProfiles(typeIds: allIds)
            moduleTypeProfiles = profiles
        } catch {
            fittingWarning = "WARNING: SDE type profiles failed to load; fitting stats unavailable"
            return
        }
        sanitizeDuplicateSubsystems()
        sanitizeHardpointOverflow()
        await resolveLocalNames(repo: repo, typeIds: allIds)
        activation = (try? await repo.moduleActivation(typeIds: allIds)) ?? [:]

        // Build initial configs: active modules start active; passive fitted items stay online.
        var c: [String: ModuleConfig] = [:]
        for item in currentItems {
            let slot = slotFor(item.flag)
            if slot != .cargo, slot != .drone, isFittedType(item) {
                let initialState = activation[item.typeId]?.defaultState ?? .online
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
                    // The most plentiful compatible charge in the hold, as the desktop picks it.
                    let stock = cargoItems
                        .filter { compatibleIds.contains($0.typeId) }
                        .reduce(into: [Int: Int]()) { $0[$1.typeId, default: 0] += $1.quantity }
                    if let cargo = stock.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }).map({ ESIFittingItem(typeId: $0.key, flag: "Cargo", quantity: $0.value) }) {
                        chargeNames[cargo.typeId] = typeName(cargo.typeId, fallback: "Charge \(cargo.typeId)")
                        for sameWeapon in currentItems where sameWeapon.typeId == weapon.typeId {
                            configs[sameWeapon.flag, default: ModuleConfig()].chargeTypeId = cargo.typeId
                        }
                    }
                }
            }
        }

        if let saved { configs.merge(saved.moduleConfigs) { _, kept in kept } }
        draftReady = true
        saveDraft()

        // Load the character's skills and implants (the engine fits with them)
        await loadSkillData(repo: repo)
        skillsReady = true

        await refreshFitSkillRecommendations(repo: repo)
        await recalcStats()
    }

    func loadLiveItemsIfCurrentShip() async {
        guard let ship = try? await characterService.currentShip(),
              ship.shipTypeId == fit.shipTypeId else { return }
        guard let assets = try? await characterService.assets() else {
            if fit.items.isEmpty {
                fittingWarning = "WARNING: active ship assets failed to load; showing hull-only stats"
            }
            return
        }

        let children = assets.filter {
            $0.locationType == "item" && $0.locationId == ship.shipItemId
        }
        guard !children.isEmpty else {
            if fit.items.isEmpty {
                fittingWarning = "WARNING: active ship has no visible fitted assets; showing hull-only stats"
            }
            return
        }

        let mappedItems = children.map {
            ESIFittingItem(typeId: $0.typeId, flag: $0.locationFlag, quantity: $0.quantity)
        }

        guard ship.shipName == fit.name || fit.items.isEmpty || fittedSlotsMatch(mappedItems, fit.items) else {
            return
        }

        liveItems = mappedItems
    }

    func fittedSlotsMatch(_ lhs: [ESIFittingItem], _ rhs: [ESIFittingItem]) -> Bool {
        let left = fittedSlotTypeIds(lhs)
        let right = fittedSlotTypeIds(rhs)
        guard !left.isEmpty, left.keys == right.keys else { return false }
        return left.allSatisfy { flag, typeIds in
            guard let otherTypeIds = right[flag] else { return false }
            return !typeIds.isDisjoint(with: otherTypeIds)
        }
    }

    func fittedSlotTypeIds(_ items: [ESIFittingItem]) -> [String: Set<Int>] {
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

    func resolveLocalNames(repo: SDERepository, typeIds: Set<Int>) async {
        let missing = typeIds.filter { localTypes[$0] == nil }
        guard !missing.isEmpty else { return }
        guard let map = try? await repo.types(ids: Set(missing)) else { return }
        for (id, t) in map {
            localTypes[id] = t
            if typeNames[id] == nil { localTypeNames[id] = t.name }
        }
    }

    func loadSkillData(repo: SDERepository) async {
        do {
            let skillsResponse = try await characterService.skills()
            characterSkills = Dictionary(uniqueKeysWithValues:
                skillsResponse.skills.map { ($0.skillId, $0.activeSkillLevel) }
            )
            do {
                implantIds = try await characterService.implants()
                fittingWarning = nil
                // Their names for the implants list on the modules tab.
                if let repo = env.repository { await resolveLocalNames(repo: repo, typeIds: Set(implantIds)) }
            } catch {
                implantIds = []
                fittingWarning = String(localized: "WARNING: implants failed to load; stats may be incomplete")
            }
        } catch {
            fittingWarning = String(localized: "WARNING: skills failed to load; stats use all skills at V")
        }
    }

    /// Fit stats from the desktop's dogma engine (the same code and numbers as the desktop, checked
    /// against Pyfa).
    func recalcStats() async {
        guard !moduleTypeProfiles.isEmpty else { return }
        // Charge attributes for the charge pickers.
        let neededChargeIds = Set(configs.values.compactMap(\.chargeTypeId))
        let missing = neededChargeIds.subtracting(Set(chargeTypeAttrs.keys))
        if !missing.isEmpty, let repo = env.repository,
           let newMaps = try? await repo.typeAttributeMaps(typeIds: missing) {
            for (k, v) in newMaps { chargeTypeAttrs[k] = v }
        }

        var modules: [JSFitModule] = []
        var flags: [(flag: String, typeId: Int)] = []
        for item in currentItems {
            let slot = slotFor(item.flag)
            guard slot != .cargo, slot != .drone, isFittedType(item) else { continue }
            let cfg = configs[item.flag] ?? ModuleConfig()
            let slotName: String
            switch slot {
            case .high: slotName = "hi"
            case .mid: slotName = "med"
            case .low: slotName = "lo"
            case .rig: slotName = "rig"
            default: slotName = "sub"
            }
            modules.append(JSFitModule(
                typeId: item.typeId, slot: slotName, state: cfg.state.rawValue.lowercased(),
                chargeTypeId: cfg.chargeTypeId ?? embeddedCharge(for: item)?.typeId
            ))
            flags.append((item.flag, item.typeId))
        }
        // Drone stacks in bay order; five drones launched in all, first stacks first (the desktop's rule).
        var drones: [JSFitDrone] = []
        for item in currentItems where slotFor(item.flag) == .drone {
            if let i = drones.firstIndex(where: { $0.typeId == item.typeId }) {
                drones[i].count += max(1, item.quantity)
            } else {
                drones.append(JSFitDrone(typeId: item.typeId, count: max(1, item.quantity), active: 0))
            }
        }
        var toLaunch = 5
        for i in drones.indices {
            if let chosen = droneActive[drones[i].typeId] {
                drones[i].active = min(drones[i].count, chosen)
            } else {
                drones[i].active = min(drones[i].count, toLaunch)
                toLaunch -= drones[i].active
            }
        }
        let spec = JSFitSpec(
            shipTypeId: fit.shipTypeId,
            name: fit.name,
            modules: modules,
            drones: drones,
            implants: implantIds
        )
        let skills: JSSkills = characterSkills.isEmpty ? .all5 : .character(characterSkills)
        guard let dogma = env.dogma else { return }
        do {
            let js = try await dogma.calculate(spec, skills: skills)
            guard !Task.isCancelled else { return }
            stats = ShipStats(js: js, flags: flags)
            fitStats = js
            fitSpec = spec
            #if DEBUG
            // Debug builds: `-openFitShot YES` opens the snapshot once the stats are in (screenshots).
            if UserDefaults.standard.bool(forKey: "openFitShot"), fitShot == nil, !preparingShot {
                UserDefaults.standard.removeObject(forKey: "openFitShot")
                Task { await openFitShot() }
            }
            #endif
            moduleProblems = js.modules.reduce(into: [:]) { out, m in
                guard !m.problems.isEmpty, m.index < flags.count else { return }
                out[flags[m.index].flag] = m.problems.map { EngineProblem.message($0) ?? $0 }
            }
        } catch {
            if !error.isCancellation { fittingWarning = error.localizedDescription }
        }
    }
}
