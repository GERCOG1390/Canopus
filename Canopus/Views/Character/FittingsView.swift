import SwiftUI
import EVEAuth
import EVEStaticData
import Domain
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Module Config (per-slot UI state)

struct ModuleConfig: Equatable {
    var state: ModuleState = .active
    var chargeTypeId: Int? = nil
}

private struct FlagItem: Identifiable { let id: String }

private struct FittingShipEntry: Identifiable {
    let id: Int         // shipTypeId
    let shipName: String
    let fits: [ESIFitting]
}

private struct FittingClassEntry: Identifiable {
    let id: String      // class name (e.g. "Cruiser")
    let ships: [FittingShipEntry]
}

private struct DraftFitRoute: Identifiable {
    let fit: ESIFitting
    let typeNames: [Int: String]

    var id: Int { fit.fittingId }
}

private struct ImportFitError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

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
                .font(.ui(11, .semibold)).monospacedDigit()
                .foregroundStyle(color)
        }
    }

    @ViewBuilder
    private func damageBar(_ label: String, _ value: Double, _ color: Color) -> some View {
        if value > 0 {
            HStack(spacing: 8) {
                Text(LocalizedStringKey(label))
                    .font(.ui(11, .semibold)).monospacedDigit()
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
                    .font(.ui(11)).monospacedDigit()
                    .foregroundStyle(Color.eveText.opacity(0.66))
                    .frame(width: 88, alignment: .trailing)
            }
        }
    }
}

private struct EVEModuleStateBadge: View {
    let state: ModuleState
    var isSelected = true
    var isEnabled = true

    var body: some View {
        Text(state.shortLabel)
            .font(.ui(11, .bold)).monospacedDigit()
            .tracking(0.6)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .clipShape(CutCorner(size: 3))
            .overlay(
                CutCorner(size: 3)
                    .stroke(borderColor, lineWidth: 1)
            )
    }

    private var foregroundColor: Color {
        guard isEnabled else { return Color.eveText.opacity(0.20) }
        return isSelected ? Color.eveBackground : state.dotColor.opacity(0.82)
    }

    private var backgroundColor: Color {
        guard isEnabled else { return Color.white.opacity(0.03) }
        return isSelected ? state.dotColor : state.dotColor.opacity(0.10)
    }

    private var borderColor: Color {
        guard isEnabled else { return Color.white.opacity(0.04) }
        return state.dotColor.opacity(isSelected ? 0.55 : 0.18)
    }
}

// MARK: - FittingsView

struct FittingsView: View {
    let characterService: CharacterService
    @Environment(AppEnvironment.self) private var env

    @State private var fittings: [ESIFitting] = []
    @State private var currentShip: ESICurrentShip?
    @State private var typeNames: [Int: String] = [:]
    @State private var shipGroupNames: [Int: String] = [:]
    @State private var isLoading = true
    @State private var error: Error?
    @State private var showNewFitPicker = false
    @State private var showImportSheet = false
    @State private var draftRoute: DraftFitRoute?

    private var activeShipFit: ESIFitting? {
        guard let currentShip else { return nil }
        return ESIFitting(
            fittingId: -currentShip.shipItemId,
            name: currentShip.shipName,
            description: "Current active ship",
            shipTypeId: currentShip.shipTypeId,
            items: []
        )
    }

    private var groupedFittings: [FittingClassEntry] {
        var classToShipFits: [String: [Int: [ESIFitting]]] = [:]
        for fit in fittings {
            let className = shipGroupNames[fit.shipTypeId] ?? "Unknown"
            classToShipFits[className, default: [:]][fit.shipTypeId, default: []].append(fit)
        }
        return classToShipFits.keys.sorted().map { className in
            let ships = classToShipFits[className]!
                .sorted { (typeNames[$0.key] ?? "") < (typeNames[$1.key] ?? "") }
                .map { (typeId, fits) in
                    FittingShipEntry(
                        id: typeId,
                        shipName: typeNames[typeId] ?? "Ship \(typeId)",
                        fits: fits.sorted { $0.name < $1.name }
                    )
                }
            return FittingClassEntry(id: className, ships: ships)
        }
    }

    var body: some View {
        ZStack {
            Color.eveBackground.ignoresSafeArea()
            ScrollView {
                if fittings.isEmpty && currentShip == nil && !isLoading {
                    EmptyState("No Saved Fits", icon: "win_fittingmanagement") { Text("Save fits in-game to see them here.") }
                    .foregroundStyle(Color.eveText)
                    .padding(.top, 60)
                } else {
                    VStack(spacing: 0) {
                        Text("FITTINGS · \(fittings.count)").hudLabel()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20).padding(.vertical, 14)
                        EVESeparator(kind: .section)
                        LazyVStack(spacing: 0) {
                            if let activeShipFit {
                                classSectionHeader("ACTIVE SHIP")
                                NavigationLink {
                                    FitDetailView(fit: activeShipFit, typeNames: typeNames, characterService: characterService)
                                } label: {
                                    activeShipRow(activeShipFit)
                                }
                                .buttonStyle(.plain)
                                EVESeparator()
                            }

                            ForEach(groupedFittings) { classEntry in
                                classSectionHeader(classEntry.id)
                                ForEach(classEntry.ships) { shipEntry in
                                    shipSectionHeader(shipEntry.shipName, typeId: shipEntry.id, count: shipEntry.fits.count)
                                    ForEach(shipEntry.fits) { fit in
                                        NavigationLink {
                                            FitDetailView(fit: fit, typeNames: typeNames, characterService: characterService)
                                        } label: {
                                            fitRowGrouped(fit)
                                        }
                                        .buttonStyle(.plain)
                                        EVESeparator()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, EVELayout.scrollBottomClearance)
                }
            }
            if isLoading { ProgressView().tint(Color.eveCyan) }
        }
        .navigationTitle("FITTINGS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.eveBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showImportSheet = true
                } label: {
                    Text("Import EFT").font(.ui(14))
                }
                .foregroundStyle(Color.eveCyan)

                Button {
                    showNewFitPicker = true
                } label: {
                    Text("+").font(.ui(22, .medium))
                }
                .foregroundStyle(Color.eveAmber)
            }
        }
        .sheet(isPresented: $showNewFitPicker) {
            NavigationStack {
                ShipPickerView { ship in
                    let fit = ESIFitting(
                        fittingId: -Int(Date().timeIntervalSince1970),
                        name: "\(ship.name) Fit",
                        description: "Local draft fit",
                        shipTypeId: ship.id,
                        items: []
                    )
                    var names = typeNames
                    names[ship.id] = ship.name
                    let route = DraftFitRoute(fit: fit, typeNames: names)
                    showNewFitPicker = false
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        draftRoute = route
                    }
                }
            }
        }
        .sheet(isPresented: $showImportSheet) {
            NavigationStack {
                FitImportSheet { fit, names in
                    let mergedNames = typeNames.merging(names) { _, new in new }
                    typeNames = mergedNames
                    let route = DraftFitRoute(fit: fit, typeNames: mergedNames)
                    showImportSheet = false
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        draftRoute = route
                    }
                }
            }
        }
        .sheet(item: $draftRoute) { route in
            NavigationStack {
                FitDetailView(fit: route.fit, typeNames: route.typeNames, characterService: characterService)
            }
            // A page-sized sheet on iPad; the fitting screen is too dense for the default form sheet.
            .presentationSizing(.page)
        }
        .task(id: env.dataKey) { await load() }
        .alert("Error", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } })
        ) {
            Button("Retry") { Task { await load() } }
            Button("Dismiss", role: .cancel) {}
        } message: { Text(error?.localizedDescription ?? "") }
    }

    private func fitRow(_ fit: ESIFitting) -> some View {
        HStack(spacing: 13) {
            EVERenderImage(typeId: fit.shipTypeId, size: 44)
                .clipShape(CutCorner(size: 7))
                .overlay(CutCorner(size: 7).stroke(Color.white.opacity(0.10), lineWidth: 1))
            VStack(alignment: .leading, spacing: 5) {
                Text(fit.name)
                    .font(.ui(15, .semibold))
                    .foregroundStyle(Color.eveText).lineLimit(1)
                HStack(spacing: 8) {
                    Text(typeNames[fit.shipTypeId] ?? "Ship \(fit.shipTypeId)")
                        .font(.ui(12)).foregroundStyle(Color.eveText.opacity(0.48))
                    Text("·").foregroundStyle(Color.eveText.opacity(0.22))
                    Text("\(fit.items.count) modules")
                        .font(.ui(11.5)).monospacedDigit().foregroundStyle(Color.eveText.opacity(0.38))
                }
            }
            Spacer()
            EVEActionIndicator(kind: .navigate)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color.eveBackground)
    }

    private func classSectionHeader(_ name: String) -> some View {
        EVESectionHeader(
            name,
            accentColor: Color.eveAmber,
            backgroundColor: Color.eveAmber.opacity(0.10)
        )
    }

    private func shipSectionHeader(_ shipName: String, typeId: Int, count: Int) -> some View {
        HStack(spacing: 12) {
            EVERenderImage(typeId: typeId, size: 38)
                .clipShape(CutCorner(size: 5))
                .overlay(CutCorner(size: 5).stroke(Color.white.opacity(0.10), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(shipName)
                    .font(.ui(14, .semibold))
                    .foregroundStyle(Color.eveText)
                Text("\(count) \(count == 1 ? "FIT" : "FITS")")
                    .font(.ui(11, .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Color.eveText.opacity(0.35))
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(Color.eveCard)
    }

    private func fitRowGrouped(_ fit: ESIFitting) -> some View {
        HStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 4) {
                Text(fit.name)
                    .font(.ui(14, .semibold))
                    .foregroundStyle(Color.eveText).lineLimit(1)
                Text("\(fit.items.count) modules")
                    .font(.ui(11.5)).monospacedDigit()
                    .foregroundStyle(Color.eveText.opacity(0.38))
            }
            Spacer()
            EVEActionIndicator(kind: .navigate)
        }
        .padding(.leading, 32).padding(.trailing, 20).padding(.vertical, 11)
        .background(Color.eveBackground)
    }

    private func activeShipRow(_ fit: ESIFitting) -> some View {
        HStack(spacing: 13) {
            EVERenderImage(typeId: fit.shipTypeId, size: 42)
                .clipShape(CutCorner(size: 6))
                .overlay(CutCorner(size: 6).stroke(Color.eveGreen.opacity(0.35), lineWidth: 1))
            VStack(alignment: .leading, spacing: 4) {
                Text(fit.name)
                    .font(.ui(15, .semibold))
                    .foregroundStyle(Color.eveText)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(typeNames[fit.shipTypeId] ?? "Ship \(fit.shipTypeId)")
                        .font(.ui(12))
                        .foregroundStyle(Color.eveText.opacity(0.48))
                    Text("LIVE FIT")
                        .font(.ui(11, .bold)).monospacedDigit()
                        .foregroundStyle(Color.eveGreen)
                }
            }
            Spacer()
            EVEActionIndicator(kind: .navigate)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.eveBackground)
    }

    private func load() async {
        isLoading = true; error = nil; defer { isLoading = false }
        do {
            fittings = try await characterService.fittings()
        } catch { if !error.isCancellation { self.error = error } }

        currentShip = try? await characterService.currentShip()
        await resolveNames()
        #if DEBUG
        // Debug builds: `-openFirstFit YES` opens the first saved fit (screenshots, UI checks).
        if UserDefaults.standard.bool(forKey: "openFirstFit"), draftRoute == nil, let first = fittings.first {
            draftRoute = DraftFitRoute(fit: first, typeNames: typeNames)
        }
        #endif
    }

    private func resolveNames() async {
        guard let repo = env.repository else { return }
        var allTypeIds = Set(fittings.flatMap { [$0.shipTypeId] + $0.items.map(\.typeId) })
        if let currentShip {
            allTypeIds.insert(currentShip.shipTypeId)
        }
        guard let map = try? await repo.types(ids: allTypeIds) else { return }
        for (id, t) in map { typeNames[id] = t.name }

        // Map each ship typeId → class name (e.g. "Cruiser", "Strategic Cruiser")
        // Ships are category 6 in EVE SDE; group name is the ship class.
        var shipTypeIds = Set(fittings.map(\.shipTypeId))
        if let currentShip {
            shipTypeIds.insert(currentShip.shipTypeId)
        }
        if let allShipGroups = try? await repo.groups(categoryId: 6) {
            let groupNameById = Dictionary(uniqueKeysWithValues: allShipGroups.map { ($0.id, $0.name) })
            for typeId in shipTypeIds {
                if let gid = map[typeId]?.groupId {
                    shipGroupNames[typeId] = groupNameById[gid]
                }
            }
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
    /// The engine's full result, for the stats tab.
    @State private var fitStats: JSFitStats?
    /// The engine's per-module problems (wrong ship, rig size, group limits), by slot flag.
    @State private var moduleProblems: [String: [String]] = [:]
    /// The spec the stats were calculated for (the snapshot draws it).
    @State private var fitSpec: JSFitSpec?
    @State private var fitShot: FitShotData?
    @State private var preparingShot = false
    @State private var moduleTypeProfiles: [Int: TypeProfile] = [:]
    @State private var chargeTypeAttrs: [Int: [Int: Double]] = [:]
    @State private var chargeNames: [Int: String] = [:]
    @State private var sheetFlag: FlagItem? = nil
    @State private var activeTab: FitTab = {
        #if DEBUG
        // Debug builds: `-fitTab stats` opens a fit on its stats tab (screenshots, UI checks).
        if let tab = UserDefaults.standard.string(forKey: "fitTab").flatMap({ FitTab(rawValue: $0.uppercased()) }) { return tab }
        #endif
        return .modules
    }()
    @State private var characterSkills: [Int: Int] = [:]
    @State private var implantIds: [Int] = []
    /// Start state and overload ability per module type (the desktop's rules).
    @State private var activation: [Int: ModuleActivation] = [:]
    @State private var liveItems: [ESIFittingItem]?
    @State private var localTypeNames: [Int: String] = [:]
    @State private var localTypes: [Int: ItemType] = [:]
    @State private var fittingWarning: String?
    @State private var fitSkillRecommendations: [FitSkillRecommendation] = []
    @State private var isSendingToEVE = false
    @State private var fittingSendStatus: FittingSendStatus?
    // Prevents .onChange from triggering recalcStats before skills are loaded
    @State private var skillsReady = false
    @State private var editableItems: [ESIFittingItem]?
    @State private var modulePickerSlot: SlotSelection?
    @State private var exportSheet: FittingTextSheet?
    @State private var recalcTask: Task<Void, Never>?

    private enum StatIcon {
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

    private var currentItems: [ESIFittingItem] {
        editableItems ?? liveItems ?? fit.items
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

    private var shipRigSize: Int? {
        moduleTypeProfiles[fit.shipTypeId]?.attrs[1547].map { Int($0.rounded()) }
    }

    private var supportsSubsystemSlots: Bool {
        moduleTypeProfiles[fit.shipTypeId]?.groupId == 963 || !moduleItems(in: .sub).isEmpty
    }

    private var displayedSlots: [Slot] {
        Slot.allCases.filter { slot in
            slot != .sub || supportsSubsystemSlots
        }
    }

    enum FitTab: String, CaseIterable { case modules = "MODULES"; case stats = "STATS"; case tools = "TOOLS" }

    // MARK: - Slot classification

    private enum Slot: String, CaseIterable {
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

    private struct SlotSelection: Identifiable {
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

    private enum FitSkillPriority: Int {
        case critical = 0
        case performance = 1
    }

    private enum WeaponHardpointKind {
        case turret
        case launcher
    }

    private enum FitSkillCategory: Int, CaseIterable {
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

    private struct FitSkillRecommendation: Identifiable {
        var id: String { "\(priority.rawValue)-\(category.rawValue)-\(skillId)" }
        let skillId: Int
        let name: String
        let currentLevel: Int
        let targetLevel: Int
        let priority: FitSkillPriority
        let category: FitSkillCategory
        let reason: String
    }

private struct FittingTextSheet: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}

private struct FittingSendStatus: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct SubsystemSlotDefinition: Identifiable {
    let dogmaSlotId: Int
    let flagIndex: Int
    let title: String

    var id: Int { dogmaSlotId }
    var flag: String { "SubSystemSlot\(flagIndex)" }
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

    private func moduleCostKey(flag: String, typeId: Int) -> String {
        "\(flag)#\(typeId)"
    }

    private func moduleCostMap(_ costs: [FittedModuleCost]) -> [String: FittedModuleCost] {
        costs.reduce(into: [:]) { result, cost in
            result[moduleCostKey(flag: cost.flag, typeId: cost.typeId)] = cost
        }
    }

    private var subsystemSlotDefinitions: [SubsystemSlotDefinition] {
        [
            SubsystemSlotDefinition(dogmaSlotId: 125, flagIndex: 0, title: "Core"),
            SubsystemSlotDefinition(dogmaSlotId: 126, flagIndex: 1, title: "Defensive"),
            SubsystemSlotDefinition(dogmaSlotId: 127, flagIndex: 2, title: "Offensive"),
            SubsystemSlotDefinition(dogmaSlotId: 128, flagIndex: 3, title: "Propulsion")
        ]
    }

    private func subsystemDogmaSlotId(for item: ESIFittingItem) -> Int? {
        moduleTypeProfiles[item.typeId]?.attrs[1366].map { Int($0.rounded()) }
    }

    private func slotCapacity(_ slot: Slot) -> Int? {
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

    private func emptySlotFlags(for slot: Slot) -> [String] {
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

    private func slotUsageText(_ slot: Slot) -> String? {
        guard let capacity = slotCapacity(slot) else { return nil }
        return "\(moduleItems(in: slot).count)/\(capacity)"
    }

    private func hardpointCapacity(_ kind: WeaponHardpointKind) -> Int {
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
    private func weaponHardpointKind(for typeId: Int) -> WeaponHardpointKind? {
        guard let effects = moduleTypeProfiles[typeId]?.effectIds else { return nil }
        if effects.contains(42) { return .turret }
        if effects.contains(40) { return .launcher }
        return nil
    }

    private func fittedHardpointCount(_ kind: WeaponHardpointKind, excluding flag: String? = nil) -> Int {
        moduleItems(in: .high)
            .filter { $0.flag != flag }
            .filter { weaponHardpointKind(for: $0.typeId) == kind }
            .count
    }

    private func hardpointValidationMessage(for typeId: Int, replacing flag: String? = nil) -> String? {
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

    private func subsystemDefinition(for flag: String) -> SubsystemSlotDefinition? {
        subsystemSlotDefinitions.first { $0.flag == flag }
    }

    private func subsystemDefinition(dogmaSlotId: Int) -> SubsystemSlotDefinition? {
        subsystemSlotDefinitions.first { $0.dogmaSlotId == dogmaSlotId }
    }

    private func occupiedSubsystemDogmaSlotIds(excluding allowedSlotId: Int?) -> Set<Int> {
        Set(moduleItems(in: .sub).compactMap { item in
            let slotId = subsystemDogmaSlotId(for: item)
            return slotId == allowedSlotId ? nil : slotId
        })
    }

    private func firstOpenSubsystemDefinition() -> SubsystemSlotDefinition? {
        let usedDogmaSlots = occupiedSubsystemDogmaSlotIds(excluding: nil)
        return subsystemSlotDefinitions.first { !usedDogmaSlots.contains($0.dogmaSlotId) }
    }

    private func openPicker(for slot: Slot, preferredFlag: String? = nil, requiredSubsystemSlotId: Int? = nil) {
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
            EVESeparator(kind: .section)
            if stats != nil { resourceBar }
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
                        exportSheet = FittingTextSheet(
                            title: "EXPORT FIT",
                            text: exportEFT()
                        )
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
                        set: { configs[flagItem.id] = $0 }
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
            guard skillsReady else { return }
            scheduleFitRefresh()
        }
        .onDisappear {
            recalcTask?.cancel()
            recalcTask = nil
        }
    }

    // MARK: - Ship header

    private var shipHeader: some View {
        HStack(spacing: 14) {
            EVERenderImage(typeId: fit.shipTypeId, size: 60)
                .clipShape(CutCorner(size: 10))
                .overlay(CutCorner(size: 10).stroke(Color.eveAmber.opacity(0.3), lineWidth: 1))
            VStack(alignment: .leading, spacing: 4) {
                Text(fit.name).font(.ui(18, .semibold)).foregroundStyle(Color.eveText)
                Text(typeName(fit.shipTypeId, fallback: "")).font(.ui(12)).foregroundStyle(Color.eveText.opacity(0.50))
                HStack(spacing: 6) {
                    Text(liveItems == nil ? "SAVED FIT" : "LIVE SHIP")
                        .font(.ui(11, .semibold)).monospacedDigit()
                        .foregroundStyle(liveItems == nil ? Color.eveText.opacity(0.45) : Color.eveGreen)
                    Text("\(currentItems.count) items")
                        .font(.ui(11)).monospacedDigit()
                        .foregroundStyle(Color.eveText.opacity(0.35))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(Color.eveBackground)
    }

    // MARK: - Resource bar (PG / CPU used of total)

    private var resourceBar: some View {
        HStack(spacing: 0) {
            if let s = stats, s.pgTotal > 0 {
                resourceCell("PG", used: s.pgUsed, total: s.pgTotal, unit: "MW", color: .eveAmber)
                EVEVerticalSeparator()
                resourceCell("CPU", used: s.cpuUsed, total: s.cpuTotal, unit: "Tf", color: .eveCyan)
            }
        }
        .background(Color.eveCard)
        .frame(height: 36)
    }

    private func resourceCell(_ label: String, used: Double, total: Double, unit: String, color: Color) -> some View {
        // Used / total, as on the desktop; red when the fit doesn't fit.
        let frac = total > 0 ? min(1, max(0, used / total)) : 0
        let over = used > total + 1e-6
        return HStack(spacing: 6) {
            Text(LocalizedStringKey(label)).hudLabel()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(color.opacity(0.12))
                    Rectangle().fill(over ? Color.eveRed : color.opacity(0.65)).frame(width: geo.size.width * frac)
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .frame(height: 6)
            Text(String(format: "%.1f / %.1f %@", used, total, unit))
                .font(.ui(11)).monospacedDigit()
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

    // MARK: - Modules tab

    private var modulesTabView: some View {
        let costsByModule = moduleCostMap(stats?.moduleCosts ?? [])

        return ScrollView {
            VStack(spacing: 0) {
                ForEach(displayedSlots, id: \.self) { slot in
                    let items = currentItems.filter { slotFor($0.flag) == slot }
                    let visibleItems = slot == .cargo || slot == .drone ? items : moduleItems(in: slot)
                    if !visibleItems.isEmpty || editableItems != nil || fit.items.isEmpty {
                        slotSection(slot, items: items, visibleItems: visibleItems, costsByModule: costsByModule)
                        EVESeparator(kind: .section)
                    }
                }
            }
            .padding(.bottom, EVELayout.scrollBottomClearance)
        }
    }

    private func slotSection(
        _ slot: Slot,
        items: [ESIFittingItem],
        visibleItems: [ESIFittingItem],
        costsByModule: [String: FittedModuleCost]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            EVESectionHeader(slot.rawValue) {
                if let usage = slotUsageText(slot) {
                    Text(usage)
                        .font(.ui(11, .semibold)).monospacedDigit()
                        .foregroundStyle(Color.eveText.opacity(0.45))
                }
            }
            EVESeparator()

            let isGrouped = (slot == .drone || slot == .cargo)
            if isGrouped {
                // Cargo/drones: group by typeId
                let grouped = Dictionary(grouping: items, by: \.typeId)
                ForEach(grouped.keys.sorted(), id: \.self) { typeId in
                    let qty = grouped[typeId]!.reduce(0) { $0 + $1.quantity }
                    groupedRow(typeId: typeId, quantity: qty)
                    EVESeparator()
                }
            } else {
                // Module slots: individual rows, each tappable
                ForEach(visibleItems.sorted(by: { $0.flag < $1.flag }), id: \.flag) { item in
                    moduleRow(item, fittingCost: costsByModule[moduleCostKey(flag: item.flag, typeId: item.typeId)])
                        .contextMenu {
                            Button(role: .destructive) {
                                removeItem(flag: item.flag, typeId: item.typeId)
                            } label: {
                                Text("Remove")
                            }
                        }
                    EVESeparator()
                }

                ForEach(emptySlotFlags(for: slot), id: \.self) { flag in
                    emptySlotRow(slot: slot, flag: flag)
                    EVESeparator()
                }
            }

            if isGrouped || slotCapacity(slot) == nil {
                Button {
                    openPicker(for: slot)
                } label: {
                    HStack(spacing: 10) {
                        EVEActionIndicator(kind: .add)
                        Text("ADD \(slot.shortTitle.uppercased())")
                            .font(.ui(11, .semibold)).monospacedDigit()
                            .tracking(1.0)
                            .foregroundStyle(Color.eveAmber.opacity(0.82))
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(Color.eveBackground)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func moduleRow(_ item: ESIFittingItem, fittingCost: FittedModuleCost?) -> some View {
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
                        .font(.ui(14))
                        .foregroundStyle(isOffline ? Color.eveText.opacity(0.38) : Color.eveText)
                        .lineLimit(1)
                    if let chargeId = cfg.chargeTypeId ?? embeddedCharge(for: item)?.typeId {
                        Text(typeName(chargeId, fallback: "Charge \(chargeId)"))
                            .font(.ui(11))
                            .foregroundStyle(Color.eveAmber.opacity(0.65))
                            .lineLimit(1)
                    }
                    ForEach(moduleProblems[item.flag] ?? [], id: \.self) { problem in
                        Text("⚠ " + problem)
                            .font(.ui(11))
                            .foregroundStyle(C.bad)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let fittingCost {
                        Text(String(format: "CPU %.1f Tf  PG %.1f MW", fittingCost.cpu, fittingCost.pg))
                            .font(.ui(11)).monospacedDigit()
                            .foregroundStyle(Color.eveText.opacity(0.42))
                            .lineLimit(1)
                    } else if stats != nil {
                        Text("NOT COUNTED IN FITTING STATS")
                            .font(.ui(11, .semibold)).monospacedDigit()
                            .foregroundStyle(Color.eveRed.opacity(0.78))
                            .lineLimit(1)
                    }
                }

                Spacer()

                HStack(spacing: 9) {
                    EVEModuleStateBadge(state: cfg.state)
                    EVEActionIndicator(kind: .navigate)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 9)
            .background(Color.eveBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func emptySlotRow(slot: Slot, flag: String) -> some View {
        let subsystemDefinition = subsystemDefinition(for: flag)

        return Button {
            openPicker(for: slot, preferredFlag: flag, requiredSubsystemSlotId: subsystemDefinition?.dogmaSlotId)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    CutCorner(size: 5)
                        .stroke(Color.eveAmber.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(width: 36, height: 36)
                    Text("+")
                        .font(.ui(18, .medium))
                        .foregroundStyle(Color.eveAmber.opacity(0.82))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(subsystemDefinition.map { "Empty \($0.title) Subsystem" } ?? "Empty \(slot.shortTitle)")
                        .font(.ui(14))
                        .foregroundStyle(Color.eveText.opacity(0.62))
                    Text(flag)
                        .font(.ui(11)).monospacedDigit()
                        .foregroundStyle(Color.eveText.opacity(0.32))
                }

                Spacer()
                EVEActionIndicator(kind: .navigate)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
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
                .font(.ui(14)).foregroundStyle(Color.eveText)
            Spacer()
            if quantity > 1 {
                Text("×\(quantity)")
                    .font(.ui(12)).monospacedDigit().foregroundStyle(Color.eveAmber.opacity(0.75))
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 9)
        .background(Color.eveBackground)
    }

    private func addType(_ type: ItemType, to slot: Slot, preferredFlag: String? = nil) {
        Task {
            // The module's effects decide whether it takes a turret / launcher hardpoint, so they are
            // loaded before the check (the desktop checks its catalog the same way before adding).
            if moduleTypeProfiles[type.id] == nil {
                await loadProfilesAndNames(for: Set([type.id]))
            }
            if slot == .high, let message = hardpointValidationMessage(for: type.id, replacing: preferredFlag) {
                fittingSendStatus = FittingSendStatus(
                    title: String(localized: "Cannot Add Module"),
                    message: message
                )
                return
            }

            var items = currentItems
            let flag = preferredFlag ?? nextFlag(for: slot, in: items)
            items.removeAll { $0.flag == flag }
            items.append(ESIFittingItem(typeId: type.id, flag: flag, quantity: 1))
            editableItems = items
            localTypes[type.id] = type
            localTypeNames[type.id] = type.name
            await loadProfilesAndNames(for: Set([type.id]))
            if slot == .sub, let subsystemSlotId = moduleTypeProfiles[type.id]?.attrs[1366].map({ Int($0.rounded()) }) {
                let sanitized = currentItems.filter { item in
                    guard slotFor(item.flag) == .sub, item.flag != flag else { return true }
                    return subsystemDogmaSlotId(for: item) != subsystemSlotId
                }
                if sanitized.count != currentItems.count {
                    editableItems = sanitized
                }
            }
            if slot != .cargo && slot != .drone {
                if activation[type.id] == nil, let repo = env.repository,
                   let a = try? await repo.moduleActivation(typeIds: [type.id]) {
                    activation.merge(a) { _, new in new }
                }
                configs[flag] = ModuleConfig(state: activation[type.id]?.defaultState ?? .online, chargeTypeId: nil)
            }
            scheduleFitRefresh(debounceNanoseconds: 0)
        }
    }

    private func removeItem(flag: String, typeId: Int) {
        editableItems = currentItems.filter { $0.flag != flag }
        configs[flag] = nil
        scheduleFitRefresh(debounceNanoseconds: 0)
    }

    @MainActor
    private func scheduleFitRefresh(debounceNanoseconds: UInt64 = 150_000_000) {
        recalcTask?.cancel()
        recalcTask = Task {
            if debounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            }
            guard !Task.isCancelled else { return }

            if let repo = env.repository {
                await refreshFitSkillRecommendations(repo: repo)
            }
            guard !Task.isCancelled else { return }
            await recalcStats()
        }
    }

    private func nextFlag(for slot: Slot, in items: [ESIFittingItem]) -> String {
        switch slot {
        case .high: return nextIndexedFlag(prefix: "HiSlot", slot: slot, items: items)
        case .mid: return nextIndexedFlag(prefix: "MedSlot", slot: slot, items: items)
        case .low: return nextIndexedFlag(prefix: "LoSlot", slot: slot, items: items)
        case .rig: return nextIndexedFlag(prefix: "RigSlot", slot: slot, items: items)
        case .sub: return nextIndexedFlag(prefix: "SubSystemSlot", slot: slot, items: items)
        case .drone: return "DroneBay"
        case .cargo: return "Cargo"
        }
    }

    private func nextIndexedFlag(prefix: String, slot: Slot, items: [ESIFittingItem]) -> String {
        let used = Set(items.filter { slotFor($0.flag) == slot }.compactMap { item in
            Int(item.flag.replacingOccurrences(of: prefix, with: ""))
        })
        var index = 0
        while used.contains(index) { index += 1 }
        return "\(prefix)\(index)"
    }

    private func sanitizeDuplicateSubsystems() {
        var seen = Set<Int>()
        var removedFlags = Set<String>()
        let sanitized = currentItems.filter { item in
            guard slotFor(item.flag) == .sub, let slotId = subsystemDogmaSlotId(for: item) else {
                return true
            }
            if seen.insert(slotId).inserted {
                return true
            }
            removedFlags.insert(item.flag)
            return false
        }

        guard sanitized.count != currentItems.count else { return }
        editableItems = sanitized
        for flag in removedFlags {
            configs[flag] = nil
        }
    }

    private func sanitizeHardpointOverflow() {
        let turretCapacity = hardpointCapacity(.turret)
        let launcherCapacity = hardpointCapacity(.launcher)
        var turretCount = 0
        var launcherCount = 0
        var removedFlags = Set<String>()

        let sanitized = currentItems.filter { item in
            guard slotFor(item.flag) == .high,
                  let kind = weaponHardpointKind(for: item.typeId) else {
                return true
            }

            switch kind {
            case .turret:
                turretCount += 1
                if turretCapacity > 0 && turretCount <= turretCapacity { return true }
            case .launcher:
                launcherCount += 1
                if launcherCapacity > 0 && launcherCount <= launcherCapacity { return true }
            }

            removedFlags.insert(item.flag)
            return false
        }

        guard sanitized.count != currentItems.count else { return }
        editableItems = sanitized
        for flag in removedFlags {
            configs[flag] = nil
        }

        let removedCount = currentItems.count - sanitized.count
        fittingWarning = "WARNING: removed \(removedCount) high-slot weapon\(removedCount == 1 ? "" : "s") over ship hardpoint limits"
    }

    private func loadProfilesAndNames(for typeIds: Set<Int>) async {
        guard let repo = env.repository, !typeIds.isEmpty else { return }
        if let profiles = try? await repo.typeProfiles(typeIds: typeIds) {
            for (id, profile) in profiles {
                moduleTypeProfiles[id] = profile
            }
        }
        await resolveLocalNames(repo: repo, typeIds: typeIds)
    }

    private func refreshFitSkillRecommendations(repo: SDERepository) async {
        let relevantTypeIds = fitRecommendationTypeIds()
        guard !relevantTypeIds.isEmpty else {
            fitSkillRecommendations = []
            return
        }

        await loadProfilesAndNames(for: relevantTypeIds)

        let requirements = await requiredSkillTargets(repo: repo, typeIds: relevantTypeIds)
        let targetedInfluences = (try? await repo.skillsModifyingFittedTypes(
            sourceTypeIds: relevantTypeIds,
            targetTypeIds: relevantTypeIds
        )) ?? []

        let influenceBySkill = mergedInfluences(targetedInfluences)
        let allSkillIds = Set(requirements.keys).union(influenceBySkill.keys)
        let skillTypes = (try? await repo.types(ids: allSkillIds)) ?? [:]

        var recommendations: [FitSkillRecommendation] = []
        for skillId in allSkillIds {
            let currentLevel = characterSkills[skillId] ?? 0
            let required = requirements[skillId]
            let influence = influenceBySkill[skillId]

            if let required, currentLevel < required.level {
                recommendations.append(FitSkillRecommendation(
                    skillId: skillId,
                    name: skillTypes[skillId]?.name ?? influence?.skill.name ?? "Skill \(skillId)",
                    currentLevel: currentLevel,
                    targetLevel: required.level,
                    priority: .critical,
                    category: .critical,
                    reason: requiredReason(required.sources)
                ))
                continue
            }

            if let influence {
                let name = skillTypes[skillId]?.name ?? influence.skill.name
                recommendations.append(FitSkillRecommendation(
                    skillId: skillId,
                    name: name,
                    currentLevel: currentLevel,
                    targetLevel: 5,
                    priority: .performance,
                    category: fitSkillCategory(name: name, reason: influenceReason(influence)),
                    reason: influenceReason(influence)
                ))
            } else if let required {
                let name = skillTypes[skillId]?.name ?? "Skill \(skillId)"
                recommendations.append(FitSkillRecommendation(
                    skillId: skillId,
                    name: name,
                    currentLevel: currentLevel,
                    targetLevel: 5,
                    priority: .performance,
                    category: fitSkillCategory(name: name, reason: requiredReason(required.sources)),
                    reason: requiredReason(required.sources)
                ))
            }
        }

        fitSkillRecommendations = recommendations.sorted {
            if $0.priority != $1.priority { return $0.priority.rawValue < $1.priority.rawValue }
            if $0.category != $1.category { return $0.category.rawValue < $1.category.rawValue }
            if $0.targetLevel != $1.targetLevel { return $0.targetLevel > $1.targetLevel }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func fitSkillCategory(name: String, reason: String) -> FitSkillCategory {
        let text = "\(name) \(reason)".lowercased()

        if text.contains("required by") {
            if text.contains(typeName(fit.shipTypeId, fallback: "").lowercased()) {
                return .ship
            }
            return .required
        }
        if text.contains("drone") || text.contains("fighter") { return .drones }
        if text.contains("missile")
            || text.contains("launcher")
            || text.contains("gunnery")
            || text.contains("turret")
            || text.contains("weapon")
            || text.contains("warhead")
            || text.contains("ballistic")
            || text.contains("trajectory") {
            return .weapons
        }
        if text.contains("shield")
            || text.contains("armor")
            || text.contains("armour")
            || text.contains("hull")
            || text.contains("mechanic")
            || text.contains("repair")
            || text.contains("resistance")
            || text.contains("compensation") {
            return .tank
        }
        if text.contains("capacitor")
            || text.contains("cap battery")
            || text.contains("energy systems")
            || text.contains("energy management")
            || text.contains("controlled bursts") {
            return .capacitor
        }
        if text.contains("navigation")
            || text.contains("afterburner")
            || text.contains("high speed")
            || text.contains("evasive")
            || text.contains("acceleration")
            || text.contains("warp drive")
            || text.contains("maximum velocity")
            || text.contains("signature radius") {
            return .mobility
        }
        if text.contains("cpu")
            || text.contains("power grid")
            || text.contains("powergrid")
            || text.contains("weapon upgrades")
            || text.contains("electronics upgrades")
            || text.contains("energy grid")
            || text.contains("rigging") {
            return .fitting
        }
        if text.contains(typeName(fit.shipTypeId, fallback: "").lowercased()) {
            return .ship
        }

        return .modules
    }

    private func mergedInfluences(_ influences: [SkillInfluence]) -> [Int: SkillInfluence] {
        var grouped: [Int: (skill: ItemType, groups: Set<String>, attrs: Set<String>)] = [:]
        for influence in influences {
            if var existing = grouped[influence.skill.id] {
                existing.groups.formUnion(influence.affectedGroups)
                existing.attrs.formUnion(influence.modifiedAttributes)
                grouped[influence.skill.id] = existing
            } else {
                grouped[influence.skill.id] = (
                    influence.skill,
                    Set(influence.affectedGroups),
                    Set(influence.modifiedAttributes)
                )
            }
        }

        return grouped.mapValues {
            SkillInfluence(
                skill: $0.skill,
                affectedGroups: $0.groups.sorted(),
                modifiedAttributes: $0.attrs.sorted()
            )
        }
    }

    private func fitRecommendationTypeIds() -> Set<Int> {
        var typeIds = Set<Int>()
        typeIds.insert(fit.shipTypeId)

        for item in currentItems {
            let slot = slotFor(item.flag)
            if slot != .cargo {
                typeIds.insert(item.typeId)
            }
            if slot != .cargo, slot != .drone, isFittedType(item) {
                if let chargeId = configs[item.flag]?.chargeTypeId ?? embeddedCharge(for: item)?.typeId {
                    typeIds.insert(chargeId)
                }
            }
        }

        return typeIds
    }

    private func requiredSkillTargets(repo: SDERepository, typeIds: Set<Int>) async -> [Int: (level: Int, sources: Set<String>)] {
        var result: [Int: (level: Int, sources: Set<String>)] = [:]
        let requirementsByType = (try? await repo.skillRequirements(typeIds: typeIds)) ?? [:]

        for typeId in typeIds {
            let requirements = requirementsByType[typeId] ?? []
            let sourceName = typeName(typeId, fallback: "Type \(typeId)")
            for requirement in requirements {
                if var existing = result[requirement.skillId] {
                    existing.level = max(existing.level, requirement.level)
                    existing.sources.insert(sourceName)
                    result[requirement.skillId] = existing
                } else {
                    result[requirement.skillId] = (requirement.level, [sourceName])
                }
            }
        }

        return result
    }

    private func requiredReason(_ sources: Set<String>) -> String {
        let names = sources.sorted().prefix(3).joined(separator: ", ")
        let extra = sources.count > 3 ? " +\(sources.count - 3)" : ""
        return "Required by \(names)\(extra)"
    }

    private func influenceReason(_ influence: SkillInfluence) -> String {
        let groups = influence.affectedGroups.prefix(2).joined(separator: ", ")
        let attrs = influence.modifiedAttributes.prefix(2).joined(separator: ", ")
        if attrs.isEmpty {
            return "Affects \(groups)"
        }
        return "Affects \(groups) · \(attrs)"
    }

    private func exportEFT() -> String {
        var lines: [String] = []
        lines.append("[\(typeName(fit.shipTypeId, fallback: "Ship \(fit.shipTypeId)")), \(fit.name)]")

        let moduleOrder: [Slot] = [.low, .mid, .high, .rig, .sub]
        for slot in moduleOrder {
            let modules = moduleItems(in: slot).sorted { $0.flag < $1.flag }
            if !modules.isEmpty {
                lines.append("")
                for item in modules {
                    lines.append(typeName(item.typeId, fallback: "Type \(item.typeId)"))
                }
            }
        }

        var cargo: [Int: Int] = [:]
        for item in currentItems where slotFor(item.flag) == .cargo || slotFor(item.flag) == .drone {
            cargo[item.typeId, default: 0] += item.quantity
        }
        for item in currentItems where slotFor(item.flag) != .cargo && slotFor(item.flag) != .drone {
            if let chargeId = configs[item.flag]?.chargeTypeId ?? embeddedCharge(for: item)?.typeId {
                cargo[chargeId, default: 0] += 1
            }
        }
        if !cargo.isEmpty {
            lines.append("")
            for typeId in cargo.keys.sorted(by: { typeName($0, fallback: "") < typeName($1, fallback: "") }) {
                let quantity = cargo[typeId] ?? 1
                let name = typeName(typeId, fallback: "Type \(typeId)")
                lines.append(quantity > 1 ? "\(name) x\(quantity)" : name)
            }
        }

        return lines.joined(separator: "\n")
    }

    private func esiFittingItems() -> [ESICreateFittingItem] {
        var items: [ESICreateFittingItem] = currentItems
            .filter { $0.quantity > 0 }
            .map { ESICreateFittingItem(typeId: $0.typeId, flag: $0.flag, quantity: $0.quantity) }

        var existingKeys = Set(currentItems.map { "\($0.typeId)-\($0.flag)" })
        for item in currentItems where slotFor(item.flag) != .cargo && slotFor(item.flag) != .drone && isFittedType(item) {
            guard let chargeId = configs[item.flag]?.chargeTypeId ?? embeddedCharge(for: item)?.typeId else {
                continue
            }

            let key = "\(chargeId)-\(item.flag)"
            guard !existingKeys.contains(key) else { continue }
            items.append(ESICreateFittingItem(typeId: chargeId, flag: item.flag, quantity: 1))
            existingKeys.insert(key)
        }

        return items
    }

    private func sendFittingToEVE() async {
        let writeScope = "esi-fittings.write_fittings.v1"
        guard characterService.tokens.hasScope(writeScope) else {
            fittingSendStatus = FittingSendStatus(
                title: "Re-login Required",
                message: "This character token does not have \(writeScope). Log out and add the character again, then try sending the fit."
            )
            return
        }

        guard !isSendingToEVE else { return }
        isSendingToEVE = true
        defer { isSendingToEVE = false }

        let fittingName = sanitizedFittingName()
        guard !fittingName.isEmpty else {
            fittingSendStatus = FittingSendStatus(
                title: "Cannot Send Fit",
                message: "The fitting needs a name before it can be saved in EVE."
            )
            return
        }

        let fitting = ESICreateFitting(
            name: fittingName,
            description: sanitizedFittingDescription(),
            shipTypeId: fit.shipTypeId,
            items: esiFittingItems()
        )

        do {
            let response = try await characterService.createFitting(fitting)
            fittingSendStatus = FittingSendStatus(
                title: "Fit Sent",
                message: "\(fittingName) was saved to EVE fittings. ID: \(response.fittingId)."
            )
        } catch {
            fittingSendStatus = FittingSendStatus(
                title: "Send Failed",
                message: fittingSendErrorMessage(error)
            )
        }
    }

    private func sanitizedFittingName() -> String {
        let trimmed = fit.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(50))
    }

    private func sanitizedFittingDescription() -> String {
        let trimmed = fit.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = trimmed.isEmpty ? "Created by Canopus" : trimmed
        return String(description.prefix(500))
    }

    private func fittingSendErrorMessage(_ error: Error) -> String {
        guard let authError = error as? AuthError else {
            return error.localizedDescription
        }

        switch authError {
        case .httpError(403, _):
            return "EVE rejected the request. Most often this means the character must be added again with esi-fittings.write_fittings.v1."
        case .httpError(422, let message):
            return "EVE rejected this fit payload. Check module flags, duplicate slots, charges, and quantities.\(message.map { "\n\n\($0)" } ?? "")"
        default:
            return authError.localizedDescription
        }
    }

    // MARK: - Stats tab

    private var statsTabView: some View {
        ScrollViewReader { proxy in
        ScrollView {
            if let s = fitStats {
                VStack(alignment: .leading, spacing: 12) {
                    if let fittingWarning {
                        warningBand(fittingWarning)
                    }
                    FitStatsPanel(
                        stats: s,
                        typeName: { id in chargeNames[id] ?? typeName(id, fallback: "#\(id)") },
                        cargoUsed: cargoUsedVolume
                    )
                    Card("Fit skills") { fitSkillsSection() }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, EVELayout.scrollBottomClearance)
            } else {
                ProgressView().tint(C.accent).padding(.top, 60)
            }
        }
        #if DEBUG
        // Debug builds: `-fitStatsAnchor defense` scrolls the stats tab to a section (screenshots).
        .task(id: fitStats == nil) {
            guard fitStats != nil, let anchor = UserDefaults.standard.string(forKey: "fitStatsAnchor") else { return }
            try? await Task.sleep(for: .milliseconds(300))
            proxy.scrollTo(anchor, anchor: .top)
        }
        #endif
        }
    }

    private func fitSkillsSection() -> some View {
        let critical = fitSkillRecommendations.filter { $0.priority == .critical }
        let performance = fitSkillRecommendations.filter { $0.priority == .performance }
        let categories = FitSkillCategory.allCases.compactMap { category -> (FitSkillCategory, [FitSkillRecommendation])? in
            let skills = fitSkillRecommendations.filter { $0.category == category }
            return skills.isEmpty ? nil : (category, skills)
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                statItem("CRITICAL", "\(critical.count)x", color: critical.isEmpty ? .eveText.opacity(0.45) : .eveRed, iconId: StatIcon.fitting)
                statItem("PERFORMANCE", "\(performance.count)x", color: performance.isEmpty ? .eveText.opacity(0.45) : .eveCyan, iconId: StatIcon.fitting)
                Spacer()
            }

            ForEach(categories, id: \.0.rawValue) { category, skills in
                fitSkillBucket(category.title, skills: skills, color: category.color)
            }

            if critical.isEmpty && performance.isEmpty {
                Text(characterSkills.isEmpty
                     ? "Skill data is not loaded for this character yet."
                     : "No fit-related skills found for this fit.")
                    .font(.ui(11, .medium)).monospacedDigit()
                    .foregroundStyle(Color.eveText.opacity(0.42))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func fitSkillBucket(_ title: String, skills: [FitSkillRecommendation], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(LocalizedStringKey(title)).hudLabel()
                Spacer()
                Text("\(skills.count)x")
                    .font(.ui(11, .bold)).monospacedDigit()
                    .foregroundStyle(color.opacity(0.78))
            }
            ForEach(skills) { skill in
                NavigationLink {
                    TypeDetailView(typeId: skill.skillId, typeName: skill.name)
                } label: {
                    fitSkillRow(skill, color: color)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func fitSkillRow(_ skill: FitSkillRecommendation, color: Color) -> some View {
        HStack(spacing: 10) {
            EVETypeIcon(typeId: skill.skillId, size: 30)
                .clipShape(CutCorner(size: 5))
                .overlay(CutCorner(size: 5).stroke(Color.white.opacity(0.08), lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(skill.name)
                        .font(.ui(13, .semibold))
                        .foregroundStyle(Color.eveText)
                        .lineLimit(1)
                    Text("L\(skill.currentLevel) → L\(skill.targetLevel)")
                        .font(.ui(11, .bold)).monospacedDigit()
                        .foregroundStyle(color)
                }
                Text(skill.reason)
                    .font(.ui(11)).monospacedDigit()
                    .foregroundStyle(Color.eveText.opacity(0.42))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)
            EVEActionIndicator(kind: .navigate)
        }
        .padding(.vertical, 4)
    }

    private func warningBand(_ text: String) -> some View {
        Text(text)
            .font(.ui(11, .medium)).monospacedDigit()
            .foregroundStyle(Color.eveAmber)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.eveAmber.opacity(0.10))
    }

    private func statItem(_ label: String, _ value: String, color: Color = .eveText, iconId: Int? = nil) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if let iconId {
                EVEIconImage(iconId: iconId, size: 14)
                    .opacity(0.72)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(label)).hudLabel()
                Text(value)
                    .font(.ui(13, .semibold)).monospacedDigit()
                    .foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Tools

    private var toolsTabView: some View {
        ScrollView {
            if let spec = fitSpec {
                FitToolsView(context: FitToolContext(
                    spec: spec,
                    skills: characterSkills.isEmpty ? .all5 : .character(characterSkills),
                    levels: characterSkills.isEmpty ? nil : characterSkills,
                    typeName: { id in chargeNames[id] ?? typeName(id, fallback: "#\(id)") },
                    apply: applySwaps
                ))
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, EVELayout.scrollBottomClearance)
            } else {
                ProgressView().tint(C.accent).padding(.top, 60)
            }
        }
    }

    /// The optimizer's swaps: every fitted module (or the drone stack) of `from` becomes `to`, keeping its
    /// slot, state and charge, as the desktop's swap does.
    private func applySwaps(_ swaps: [(from: Int, to: Int, isDrone: Bool)]) {
        var items = currentItems
        for swap in swaps {
            items = items.map { item in
                let slot = slotFor(item.flag)
                let matches = item.typeId == swap.from && (swap.isDrone ? slot == .drone : (slot != .drone && slot != .cargo && isFittedType(item)))
                return matches ? ESIFittingItem(typeId: swap.to, flag: item.flag, quantity: item.quantity) : item
            }
        }
        editableItems = items
        Task {
            let ids = Set(swaps.map(\.to))
            await loadProfilesAndNames(for: ids)
            if let repo = env.repository, let a = try? await repo.moduleActivation(typeIds: ids) {
                activation.merge(a) { _, new in new }
            }
            scheduleFitRefresh(debounceNanoseconds: 0)
        }
    }

    // MARK: - Fit snapshot

    /// Resolves names and pictures for the current fit and opens the snapshot.
    private func openFitShot() async {
        guard let spec = fitSpec, let stats = fitStats else { return }
        preparingShot = true
        defer { preparingShot = false }
        let ids = [spec.shipTypeId] + spec.modules.flatMap { [$0.typeId, $0.chargeTypeId].compactMap { $0 } }
            + spec.drones.map(\.typeId) + spec.implants
        var names: [Int: String] = [:]
        for id in ids { names[id] = chargeNames[id] ?? typeName(id, fallback: "#\(id)") }
        let missing = Set(ids.filter { names[$0]?.hasPrefix("#") ?? true })
        if !missing.isEmpty, let repo = env.repository, let types = try? await repo.types(ids: missing) {
            for (id, t) in types { names[id] = t.name }
        }
        var data = FitShotData(
            spec: spec, stats: stats, names: names,
            pilot: characterSkills.isEmpty ? nil : characterService.tokens.characterName
        )
        await data.loadImages()
        fitShot = data
    }

    // MARK: - Data loading

    private func initialLoad() async {
        guard let repo = env.repository else { return }
        await loadLiveItemsIfCurrentShip()
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

        // Load the character's skills and implants (the engine fits with them)
        await loadSkillData(repo: repo)
        skillsReady = true

        await refreshFitSkillRecommendations(repo: repo)
        await recalcStats()
    }

    private func loadLiveItemsIfCurrentShip() async {
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
        let missing = typeIds.filter { localTypes[$0] == nil }
        guard !missing.isEmpty else { return }
        guard let map = try? await repo.types(ids: Set(missing)) else { return }
        for (id, t) in map {
            localTypes[id] = t
            if typeNames[id] == nil { localTypeNames[id] = t.name }
        }
    }

    private func loadSkillData(repo: SDERepository) async {
        do {
            let skillsResponse = try await characterService.skills()
            characterSkills = Dictionary(uniqueKeysWithValues:
                skillsResponse.skills.map { ($0.skillId, $0.activeSkillLevel) }
            )
            do {
                implantIds = try await characterService.implants()
                fittingWarning = nil
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
    private func recalcStats() async {
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
            drones[i].active = min(drones[i].count, toLaunch)
            toLaunch -= drones[i].active
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

// MARK: - Module Setting Sheet

struct ModuleSettingSheet: View {
    let item: ESIFittingItem
    let typeName: String
    let moduleAttrs: [Int: Double]
    let moduleEffectIds: Set<Int>
    @Binding var config: ModuleConfig
    @Binding var chargeNames: [Int: String]
    @Binding var chargeTypeAttrs: [Int: [Int: Double]]
    var onRemove: (() -> Void)? = nil
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

    /// The module has an overload effect (from the parent's ModuleActivation).
    var canOverload = false
    private var isActiveMod: Bool { canOverload }

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
                                    .font(.ui(16, .semibold))
                                    .foregroundStyle(Color.eveText)
                                HStack(spacing: 12) {
                                    if pgCost > 0 {
                                        Label { Text(String(format: "%.0f MW", pgCost)) } icon: { GameIcon.attribute(30, size: 14) }
                                            .font(.ui(11)).foregroundStyle(Color.eveAmber.opacity(0.75))
                                    }
                                    if cpuCost > 0 {
                                        Label { Text(String(format: "%.0f Tf", cpuCost)) } icon: { GameIcon.attribute(50, size: 14) }
                                            .font(.ui(11)).foregroundStyle(Color.eveCyan.opacity(0.75))
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
                                        EVEModuleStateBadge(
                                            state: state,
                                            isSelected: config.state == state,
                                            isEnabled: enabled
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!enabled)
                                }
                            }
                            Text(config.state.rawValue)
                                .font(.ui(11, .medium)).monospacedDigit()
                                .foregroundStyle(config.state.dotColor.opacity(0.72))
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
                                            .font(.ui(14)).foregroundStyle(Color.eveText)
                                        Spacer()
                                        if let cid = config.chargeTypeId, let name = chargeNames[cid] {
                                            Text(name)
                                                .font(.ui(13)).foregroundStyle(Color.eveAmber)
                                                .lineLimit(1)
                                        } else {
                                            Text("None").font(.ui(13)).foregroundStyle(Color.eveText.opacity(0.35))
                                        }
                                        EVEActionIndicator(kind: .navigate)
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
                                            .font(.ui(13, .medium))
                                            .foregroundStyle(Color.eveRed)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20).padding(.vertical, 14)
                        }

                        if let onRemove {
                            Color.eveAmber.opacity(0.12).frame(height: 1)

                            Button(role: .destructive) {
                                onRemove()
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Text("✕")
                                        .font(.ui(13, .semibold))
                                    Text("REMOVE MODULE")
                                        .font(.ui(11, .semibold)).monospacedDigit()
                                        .tracking(1.0)
                                    Spacer()
                                }
                                .foregroundStyle(Color.eveRed)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                                .background(Color.eveBackground)
                            }
                            .buttonStyle(.plain)
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
                    Glyph(name: .search, size: 16)
                        .foregroundStyle(Color.eveText.opacity(0.40))
                    TextField("Search", text: $search)
                        .font(.ui(14))
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
                            EmptyState("No Compatible Charges", icon: "win_warning") { Text("No ammunition found for this weapon.") }
                            .foregroundStyle(Color.eveText)
                            .padding(.top, 40)
                        }
                        ForEach(filtered, id: \.id) { charge in
                            chargeRow(charge)
                            EVESeparator()
                        }
                    }
                    .padding(.bottom, EVELayout.scrollBottomClearance)
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
                        .font(.ui(14))
                        .foregroundStyle(isSelected ? Color.eveAmber : Color.eveText)
                        .lineLimit(1)
                    ChargeDamageBreakdown(profile: damage, compact: true)
                }

                Spacer()

                if isSelected {
                    Text("✓")
                        .font(.ui(12, .semibold))
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

// MARK: - Fit Builder Pickers

private struct ShipPickerView: View {
    let onSelect: (ItemType) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [ItemType] = []
    @State private var catalogSections: [ShipCatalogSection] = []
    @State private var expandedSectionIds: Set<Int> = []
    @State private var shipGroupIds: Set<Int> = []
    @State private var isLoading = false

    private struct ShipCatalogSection: Identifiable {
        let id: Int
        let title: String
        let ships: [ItemType]
    }

    private var isSearching: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    var body: some View {
        ZStack {
            Color.eveBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                searchField(placeholder: "Search ship", text: $query)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if isSearching {
                            ForEach(results, id: \.id) { ship in
                                shipButton(ship)
                                EVESeparator()
                            }
                        } else {
                            ForEach(catalogSections) { section in
                                shipCatalogSection(section)
                            }
                        }
                    }
                    .padding(.bottom, EVELayout.scrollBottomClearance)
                }
            }

            if isLoading {
                ProgressView().tint(Color.eveCyan)
            }
        }
        .navigationTitle("NEW FIT")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.eveBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
                    .foregroundStyle(Color.eveCyan)
            }
        }
        .task { await loadShipGroups() }
        .onChange(of: query) { _, newValue in
            Task { await search(newValue) }
        }
    }

    @ViewBuilder
    private func shipCatalogSection(_ section: ShipCatalogSection) -> some View {
        let expanded = expandedSectionIds.contains(section.id)

        VStack(spacing: 0) {
            EVEDisclosureSectionHeader(
                title: section.title,
                count: section.ships.count,
                isExpanded: expanded
            ) {
                if expanded {
                    expandedSectionIds.remove(section.id)
                } else {
                    expandedSectionIds.insert(section.id)
                }
            }

            if expanded {
                ForEach(section.ships, id: \.id) { ship in
                    shipButton(ship)
                    EVESeparator()
                }
            }
        }
    }

    private func shipButton(_ ship: ItemType) -> some View {
        Button {
            onSelect(ship)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                EVETypeIcon(typeId: ship.id, size: 38)
                    .clipShape(CutCorner(size: 6))
                Text(ship.name)
                    .font(.ui(15, .medium))
                    .foregroundStyle(Color.eveText)
                Spacer()
                EVEActionIndicator(kind: .navigate)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(Color.eveBackground)
        }
        .buttonStyle(.plain)
    }

    private func loadShipGroups() async {
        guard let repo = env.repository else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let groups = try await repo.groups(categoryId: 6)
            shipGroupIds = Set(groups.map(\.id))

            catalogSections = await withTaskGroup(of: ShipCatalogSection?.self) { taskGroup in
                for group in groups {
                    taskGroup.addTask {
                        let ships = (try? await repo.types(groupId: group.id)) ?? []
                        let sortedShips = ships.sorted {
                            $0.name.localizedStandardCompare($1.name) == .orderedAscending
                        }
                        guard !sortedShips.isEmpty else { return nil }
                        return ShipCatalogSection(id: group.id, title: group.name, ships: sortedShips)
                    }
                }

                var sections: [ShipCatalogSection] = []
                for await section in taskGroup {
                    if let section {
                        sections.append(section)
                    }
                }
                return sections.sorted {
                    $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
            }
        } catch {
            shipGroupIds = []
            catalogSections = []
        }
    }

    private func search(_ text: String) async {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2,
              let repo = env.repository else {
            results = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        let found = (try? await repo.search(text)) ?? []
        results = found
            .filter { shipGroupIds.contains($0.groupId) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func searchField(placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Glyph(name: .search, size: 16)
                .foregroundStyle(Color.eveText.opacity(0.40))
            TextField(placeholder, text: text)
                .font(.ui(14))
                .foregroundStyle(Color.eveText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.eveCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ModulePickerView: View {
    let slotTitle: String
    let acceptedEffectIds: Set<Int>
    let rootMarketGroupId: Int?
    let compatibleShipTypeId: Int?
    let requiredRigSize: Int?
    let requiredSubsystemSlotId: Int?
    let occupiedSubsystemSlotIds: Set<Int>
    let onSelect: (ItemType) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var searchResults: [ItemType] = []
    @State private var catalogSections: [CatalogSection] = []
    @State private var expandedSectionIds: Set<String> = []
    @State private var expandedLeafGroupIds: Set<String> = []
    @State private var profiles: [Int: TypeProfile] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?

    private struct CatalogEntry: Identifiable {
        var id: Int { type.id }
        let type: ItemType
        let groupPath: [MarketGroup]

        var marketPathNames: [String] {
            Array(groupPath.dropFirst().map(\.name))
        }

        var leafGroupName: String {
            marketPathNames.last ?? ""
        }

        var sectionTitle: String {
            let names = marketPathNames
            guard !names.isEmpty else { return "" }
            if names.count == 1 { return names[0] }
            return names.prefix(2).joined(separator: " / ")
        }

        var detailPath: String {
            let names = marketPathNames
            guard names.count > 2 else { return leafGroupName }
            return names.dropFirst(2).joined(separator: " / ")
        }
    }

    private struct CatalogSection: Identifiable {
        let id: String
        let title: String
        let entries: [CatalogEntry]
    }

    private struct CatalogLeafGroup: Identifiable {
        let id: String
        let title: String
        let entries: [CatalogEntry]
    }

    var body: some View {
        ZStack {
            Color.eveBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Glyph(name: .search, size: 16)
                        .foregroundStyle(Color.eveText.opacity(0.40))
                    TextField("Search \(slotTitle.lowercased())", text: $query)
                        .font(.ui(14))
                        .foregroundStyle(Color.eveText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.eveCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if acceptedEffectIds.isEmpty {
                            ForEach(filteredSearchResults, id: \.id) { item in
                                moduleButton(item)
                                EVESeparator()
                            }
                        } else {
                            ForEach(filteredCatalogSections) { section in
                                catalogSectionView(section)
                            }
                        }
                    }
                    .padding(.bottom, EVELayout.scrollBottomClearance)
                }
            }

            if isLoading {
                ProgressView().tint(Color.eveCyan)
            } else if let errorMessage {
                EmptyState("Cannot load modules", icon: "win_warning") { Text(errorMessage) }
                    .foregroundStyle(Color.eveText)
            } else if acceptedEffectIds.isEmpty && query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                EmptyState("Enter at least 2 characters", icon: "win_searchmarket")
                    .foregroundStyle(Color.eveText)
            } else if acceptedEffectIds.isEmpty && filteredSearchResults.isEmpty {
                EmptyState("No matching items", icon: "win_items")
                    .foregroundStyle(Color.eveText)
            } else if !acceptedEffectIds.isEmpty && filteredCatalogSections.isEmpty {
                EmptyState("No compatible modules", icon: "win_items")
                    .foregroundStyle(Color.eveText)
            }
        }
        .navigationTitle("ADD \(slotTitle.uppercased())")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.eveBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
                    .foregroundStyle(Color.eveCyan)
            }
        }
        .task {
            if rootMarketGroupId == nil {
                await search(query)
            } else {
                await loadCatalog()
            }
        }
        .onChange(of: query) { _, newValue in
            if acceptedEffectIds.isEmpty {
                Task { await search(newValue) }
            }
        }
    }

    @ViewBuilder
    private func catalogSectionView(_ section: CatalogSection) -> some View {
        let expanded = isCatalogSectionExpanded(section)
        let leafGroups = leafGroups(for: section.entries, sectionId: section.id)

        VStack(alignment: .leading, spacing: 0) {
            EVEDisclosureSectionHeader(
                title: section.title,
                count: section.entries.count,
                isExpanded: expanded
            ) {
                toggleCatalogSection(section.id)
            }

            if expanded {
                ForEach(leafGroups) { leafGroup in
                    let showLeafHeader = shouldShowLeafHeader(leafGroup, in: section, groupCount: leafGroups.count)
                    let leafExpanded = !showLeafHeader || isCatalogLeafExpanded(leafGroup)

                    if showLeafHeader {
                        EVEDisclosureSectionHeader(
                            title: leafGroup.title,
                            count: leafGroup.entries.count,
                            isExpanded: leafExpanded
                        ) {
                            toggleCatalogLeaf(leafGroup.id)
                        }
                        .padding(.leading, 14)
                        .background(Color.eveBackground)
                    }

                    if leafExpanded {
                        ForEach(leafGroup.entries) { entry in
                            moduleButton(entry.type)
                            EVESeparator()
                        }
                    }
                }
            }
        }
    }

    private var filteredSearchResults: [ItemType] {
        guard !acceptedEffectIds.isEmpty else { return searchResults }
        return searchResults.filter { item in
            guard let profile = profiles[item.id] else { return false }
            return !profile.effectIds.isDisjoint(with: acceptedEffectIds)
        }
    }

    private var filteredCatalogSections: [CatalogSection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return catalogSections }

        return catalogSections.compactMap { section in
            let entries = section.entries.filter { entry in
                entry.type.name.localizedCaseInsensitiveContains(trimmed)
                || section.title.localizedCaseInsensitiveContains(trimmed)
            }
            guard !entries.isEmpty else { return nil }
            return CatalogSection(id: section.id, title: section.title, entries: entries)
        }
    }

    private var isSearchingCatalog: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isCatalogSectionExpanded(_ section: CatalogSection) -> Bool {
        isSearchingCatalog || expandedSectionIds.contains(section.id)
    }

    private func toggleCatalogSection(_ id: String) {
        if expandedSectionIds.contains(id) {
            expandedSectionIds.remove(id)
        } else {
            expandedSectionIds.insert(id)
        }
    }

    private func isCatalogLeafExpanded(_ leafGroup: CatalogLeafGroup) -> Bool {
        isSearchingCatalog || expandedLeafGroupIds.contains(leafGroup.id)
    }

    private func toggleCatalogLeaf(_ id: String) {
        if expandedLeafGroupIds.contains(id) {
            expandedLeafGroupIds.remove(id)
        } else {
            expandedLeafGroupIds.insert(id)
        }
    }

    private func leafGroups(for entries: [CatalogEntry], sectionId: String) -> [CatalogLeafGroup] {
        let grouped = Dictionary(grouping: entries) { entry in
            entry.leafGroupName.isEmpty ? slotTitle : entry.leafGroupName
        }

        return grouped.keys.sorted { lhs, rhs in
            lhs.localizedStandardCompare(rhs) == .orderedAscending
        }.compactMap { title in
            guard let groupEntries = grouped[title], !groupEntries.isEmpty else { return nil }
            return CatalogLeafGroup(id: "\(sectionId)::\(title)", title: title, entries: groupEntries)
        }
    }

    private func shouldShowLeafHeader(_ leafGroup: CatalogLeafGroup, in section: CatalogSection, groupCount: Int) -> Bool {
        groupCount > 1 || leafGroup.title != section.title
    }

    private func moduleButton(_ item: ItemType) -> some View {
        Button {
            onSelect(item)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                EVETypeIcon(typeId: item.id, size: 38)
                    .clipShape(CutCorner(size: 6))
                    .overlay(CutCorner(size: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.ui(14, .medium))
                        .foregroundStyle(Color.eveText)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        TypeMetaBadge(metaGroupId: item.metaGroupId)
                        if let entry = catalogEntry(for: item.id), !entry.detailPath.isEmpty {
                            Text(entry.detailPath)
                                .font(.ui(11)).monospacedDigit()
                                .foregroundStyle(Color.eveText.opacity(0.38))
                                .lineLimit(1)
                        }
                        if let profile = profiles[item.id] {
                            Text(effectSummary(profile.effectIds))
                                .font(.ui(11)).monospacedDigit()
                                .foregroundStyle(Color.eveText.opacity(0.38))
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
                EVEActionIndicator(kind: .add)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.eveBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadCatalog() async {
        guard catalogSections.isEmpty, let repo = env.repository, let rootMarketGroupId else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let rootGroup = try await repo.marketGroup(id: rootMarketGroupId) else {
                catalogSections = []
                return
            }

            let entries = try await collectCatalogEntries(repo: repo, group: rootGroup, path: [])
            let profileMap = try await repo.typeProfiles(typeIds: Set(entries.map { $0.type.id }))
            let compatibleEntries = entries.filter { entry in
                guard let profile = profileMap[entry.type.id] else { return false }
                return isCompatible(profile)
            }

            profiles = profileMap
            catalogSections = makeSections(from: compatibleEntries)
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
            catalogSections = []
        }
    }

    private func collectCatalogEntries(repo: SDERepository, group: MarketGroup, path: [MarketGroup]) async throws -> [CatalogEntry] {
        async let childGroups = repo.marketGroups(parentId: group.id)
        async let directTypes = repo.types(marketGroupId: group.id)

        let children = try await childGroups
        let types = try await directTypes
        let currentPath = path + [group]

        var entries = types.map { CatalogEntry(type: $0, groupPath: currentPath) }
        for child in children {
            entries += try await collectCatalogEntries(repo: repo, group: child, path: currentPath)
        }
        return entries
    }

    private func makeSections(from entries: [CatalogEntry]) -> [CatalogSection] {
        let grouped = Dictionary(grouping: entries) { entry in
            entry.sectionTitle
        }

        return grouped.keys.sorted(by: catalogSectionSort).compactMap { title in
            guard let sectionEntries = grouped[title], !sectionEntries.isEmpty else { return nil }
            let sortedEntries = sectionEntries.sorted { lhs, rhs in
                let lhsLeaf = lhs.leafGroupName
                let rhsLeaf = rhs.leafGroupName
                if lhsLeaf != rhsLeaf {
                    return lhsLeaf.localizedStandardCompare(rhsLeaf) == .orderedAscending
                }
                let lhsMeta = EVETypeMetaPresentation.metaLevel(for: lhs.type.metaGroupId)
                let rhsMeta = EVETypeMetaPresentation.metaLevel(for: rhs.type.metaGroupId)
                if lhsMeta != rhsMeta { return lhsMeta < rhsMeta }
                return lhs.type.name.localizedStandardCompare(rhs.type.name) == .orderedAscending
            }
            let fallbackTitle = sortedEntries.first?.groupPath.last?.name ?? slotTitle
            return CatalogSection(
                id: title.isEmpty ? fallbackTitle : title,
                title: title.isEmpty ? fallbackTitle : title,
                entries: sortedEntries
            )
        }
    }

    private func catalogEntry(for typeId: Int) -> CatalogEntry? {
        catalogSections
            .lazy
            .flatMap(\.entries)
            .first { $0.type.id == typeId }
    }

    private func catalogSectionSort(_ lhs: String, _ rhs: String) -> Bool {
        let lhsPriority = catalogSectionPriority(lhs)
        let rhsPriority = catalogSectionPriority(rhs)
        if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
        return lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    private func catalogSectionPriority(_ title: String) -> Int {
        if title.hasPrefix("Turrets & Launchers") { return 0 }
        if title.hasPrefix("Drone Upgrades") { return 1 }
        if title.hasPrefix("Engineering Equipment") { return 2 }
        if title.hasPrefix("Shield") { return 3 }
        if title.hasPrefix("Hull & Armor") { return 4 }
        if title.hasPrefix("Propulsion") { return 5 }
        if title.hasPrefix("Electronic Warfare") { return 6 }
        if title.hasPrefix("Electronics and Sensor Upgrades") { return 7 }
        if title.hasPrefix("Scanning Equipment") { return 8 }
        if title.hasPrefix("Fleet Assistance Modules") { return 9 }
        if title.hasPrefix("Harvest Equipment") { return 10 }
        if title.hasPrefix("Compressors") { return 90 }
        return 50
    }

    private func search(_ text: String) async {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2,
              let repo = env.repository else {
            searchResults = []
            profiles = [:]
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let found = try await repo.search(text)
            let ids = Set(found.map(\.id))
            let profileMap = try await repo.typeProfiles(typeIds: ids)
            profiles = profileMap
            searchResults = found
                .filter { item in
                    guard let profile = profileMap[item.id] else { return acceptedEffectIds.isEmpty }
                    return isCompatible(profile)
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
            searchResults = []
            profiles = [:]
        }
    }

    private func isCompatible(_ profile: TypeProfile) -> Bool {
        if !acceptedEffectIds.isEmpty && profile.effectIds.isDisjoint(with: acceptedEffectIds) {
            return false
        }

        if let requiredRigSize {
            guard Int((profile.attrs[1547] ?? -1).rounded()) == requiredRigSize else {
                return false
            }
        }

        if let compatibleShipTypeId {
            let restrictedShipTypeId = Int(profile.attrs[1380] ?? -1)
            guard restrictedShipTypeId == compatibleShipTypeId else { return false }

            guard let subsystemSlotId = profile.attrs[1366].map({ Int($0.rounded()) }) else {
                return false
            }
            if let requiredSubsystemSlotId {
                return subsystemSlotId == requiredSubsystemSlotId
            }
            return !occupiedSubsystemSlotIds.contains(subsystemSlotId)
        }

        return true
    }

    private func effectSummary(_ ids: Set<Int>) -> String {
        if ids.contains(12) { return "HIGH SLOT MODULE" }
        if ids.contains(13) { return "MID SLOT MODULE" }
        if ids.contains(11) { return "LOW SLOT MODULE" }
        if ids.contains(2663) { return "RIG" }
        if ids.contains(3772) { return "SUBSYSTEM" }
        if ids.contains(9) { return "CHARGE" }
        return "ITEM"
    }
}

private struct FitImportSheet: View {
    let onImport: (ESIFitting, [Int: String]) -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var text = ""
    @State private var error: String?
    @State private var isImporting = false

    var body: some View {
        ZStack {
            Color.eveBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste EFT format")
                    .font(.ui(13, .semibold))
                    .foregroundStyle(Color.eveText.opacity(0.70))
                TextEditor(text: $text)
                    .font(.ui(13)).monospacedDigit()
                    .foregroundStyle(Color.eveText)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 260)
                    .background(Color.eveCard)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if let error {
                    Text(error)
                        .font(.ui(11)).monospacedDigit()
                        .foregroundStyle(Color.eveRed)
                }

                Button {
                    Task { await importFit() }
                } label: {
                    HStack {
                        Spacer()
                        Text(isImporting ? "IMPORTING..." : "IMPORT FIT")
                            .font(.ui(13, .bold)).monospacedDigit()
                            .tracking(1.0)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .background(Color.eveAmber.opacity(0.18))
                    .foregroundStyle(Color.eveAmber)
                    .clipShape(CutCorner(size: 8))
                }
                .buttonStyle(.plain)
                .disabled(isImporting || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()
            }
            .padding(20)
        }
        .navigationTitle("IMPORT EFT")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.eveBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func importFit() async {
        guard let repo = env.repository else { return }
        isImporting = true
        error = nil
        defer { isImporting = false }

        do {
            let parsed = try await parseEFT(text, repo: repo)
            onImport(parsed.fit, parsed.names)
        } catch {
            if !error.isCancellation { self.error = error.localizedDescription }
        }
    }

    private func parseEFT(_ text: String, repo: SDERepository) async throws -> (fit: ESIFitting, names: [Int: String]) {
        let rawLines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        guard let header = rawLines.first,
              header.hasPrefix("["),
              header.contains("]") else {
            throw ImportFitError(message: "EFT header not found. Expected: [Ship, Fit Name]")
        }

        let inner = header.dropFirst().prefix { $0 != "]" }
        let headerParts = inner.split(separator: ",", maxSplits: 1).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let shipName = headerParts.first, !shipName.isEmpty else {
            throw ImportFitError(message: "Ship name is missing in EFT header.")
        }
        let fitName = headerParts.count > 1 && !headerParts[1].isEmpty ? headerParts[1] : "\(shipName) Fit"
        let ship = try await exactType(named: shipName, repo: repo)

        var names: [Int: String] = [ship.id: ship.name]
        var items: [ESIFittingItem] = []
        var slotCounters: [String: Int] = [:]

        for raw in rawLines.dropFirst() {
            let parsedLine = parseItemLine(raw)
            guard !parsedLine.name.isEmpty else { continue }
            let type = try await exactType(named: parsedLine.name, repo: repo)
            names[type.id] = type.name

            let profiles = try await repo.typeProfiles(typeIds: [type.id])
            let profile = profiles[type.id]
            let flag = flagForImportedType(profile: profile, quantity: parsedLine.quantity, counters: &slotCounters)
            items.append(ESIFittingItem(typeId: type.id, flag: flag, quantity: parsedLine.quantity))
        }

        let fit = ESIFitting(
            fittingId: -Int(Date().timeIntervalSince1970),
            name: fitName,
            description: "Imported EFT fit",
            shipTypeId: ship.id,
            items: items
        )
        return (fit, names)
    }

    private func exactType(named name: String, repo: SDERepository) async throws -> ItemType {
        let found = try await repo.search(name)
        if let exact = found.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return exact
        }
        if let first = found.first {
            return first
        }
        throw ImportFitError(message: "Type not found in SDE: \(name)")
    }

    private func parseItemLine(_ line: String) -> (name: String, quantity: Int) {
        let parts = line.split(separator: ",", maxSplits: 1)
        var name = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        var quantity = 1

        if let range = name.range(of: #" x\d+$"#, options: .regularExpression) {
            let suffix = String(name[range]).trimmingCharacters(in: .whitespaces)
            quantity = Int(suffix.dropFirst()) ?? 1
            name.removeSubrange(range)
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return (name, quantity)
    }

    private func flagForImportedType(profile: TypeProfile?, quantity: Int, counters: inout [String: Int]) -> String {
        let effects = profile?.effectIds ?? []
        let prefix: String
        if effects.contains(12) {
            prefix = "HiSlot"
        } else if effects.contains(13) {
            prefix = "MedSlot"
        } else if effects.contains(11) {
            prefix = "LoSlot"
        } else if effects.contains(2663) {
            prefix = "RigSlot"
        } else if effects.contains(3772) {
            prefix = "SubSystemSlot"
        } else {
            return "Cargo"
        }
        let index = counters[prefix, default: 0]
        counters[prefix] = index + 1
        return "\(prefix)\(index)"
    }
}

private struct FitTextSheet: View {
    let title: String
    let text: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.eveBackground.ignoresSafeArea()
            TextEditor(text: .constant(text))
                .font(.ui(13)).monospacedDigit()
                .foregroundStyle(Color.eveText)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Color.eveCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(16)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.eveBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Copy") {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = text
                    #endif
                }
                .foregroundStyle(Color.eveAmber)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .foregroundStyle(Color.eveCyan)
            }
        }
    }
}

// MARK: - ModuleState dot color

extension ModuleState {
    var shortLabel: String {
        switch self {
        case .offline:  return "OFF"
        case .online:   return "ON"
        case .active:   return "ACT"
        case .overload: return "OH"
        }
    }

    var dotColor: Color {
        switch self {
        case .offline:  return Color(white: 0.28)
        case .online:   return Color(white: 0.55)
        case .active:   return .eveCyan
        case .overload: return .eveAmber
        }
    }
}
