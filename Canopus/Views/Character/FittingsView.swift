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

struct FlagItem: Identifiable {
    let id: String
    /// Identical modules shown as one row: a state or charge change applies to all of them.
    var group: [String] = []
}

struct FittingShipEntry: Identifiable {
    let id: Int         // shipTypeId
    let shipName: String
    let fits: [ESIFitting]
}

struct FittingClassEntry: Identifiable {
    let id: String      // class name (e.g. "Cruiser")
    let ships: [FittingShipEntry]
}

struct DraftFitRoute: Identifiable {
    let fit: ESIFitting
    let typeNames: [Int: String]
    /// Reopened after SwiftUI rebuilt the screen: continue from the saved draft.
    var restore = false

    var id: Int { fit.fittingId }
}

struct ImportFitError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct ChargeDamageProfile {
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

struct ChargeDamageBreakdown: View {
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

struct EVEModuleStateBadge: View {
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
    @State private var listToken = FitListToken()

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
                                    FitDetailView(fit: activeShipFit, typeNames: typeNames, characterService: characterService, listId: listToken.id)
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
                                            FitDetailView(fit: fit, typeNames: typeNames, characterService: characterService, listId: listToken.id)
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
                FitDetailView(fit: route.fit, typeNames: route.typeNames, characterService: characterService,
                              listId: listToken.id, restoreDraft: route.restore)
            }
            // A page-sized sheet on iPad; the fitting screen is too dense for the default form sheet.
            .presentationSizing(.page)
        }
        .task(id: env.dataKey) { await load() }
        .onAppear {
            // The fit was open in a list SwiftUI has since rebuilt (another page, the phone turned):
            // open it again where the pilot left it.
            let store = FitDraftStore.shared
            if let from = store.openFrom, from != listToken.id, !FitListToken.live.contains(from),
               let d = store.draft, draftRoute == nil {
                draftRoute = DraftFitRoute(fit: d.fitting, typeNames: d.typeNames, restore: true)
            }
        }
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
