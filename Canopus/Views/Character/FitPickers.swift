// Pickers of the fit screen: ship, module, import and EFT text sheets.

import SwiftUI
import EVEAuth
import EVEStaticData
import Domain
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Fit Builder Pickers

struct ShipPickerView: View {
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

struct ModulePickerView: View {
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

struct FitImportSheet: View {
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
        // The exact name in English or in the app's language first: shown names may be Russian.
        if let exact = try await repo.type(named: name) {
            return exact
        }
        let found = try await repo.search(name)
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

struct FitTextSheet: View {
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
