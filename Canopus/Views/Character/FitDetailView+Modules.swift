// The fit screen's modules tab: slot groups, module rows, drones, implants, cargo.

import SwiftUI
import EVEAuth
import EVEStaticData
import Domain
#if canImport(UIKit)
import UIKit
#endif

extension FitDetailView {
    // MARK: - Modules tab

    var modulesTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(displayedSlots.filter { $0 != .drone && $0 != .cargo }, id: \.self) { slot in
                    if (slotCapacity(slot) ?? 0) > 0 || !moduleItems(in: slot).isEmpty { slotGroup(slot) }
                }
                dronesGroup
                implantsGroup
                if !currentItems.filter({ slotFor($0.flag) == .cargo }).isEmpty { cargoGroup }
            }
            .padding(12)
            .padding(.bottom, EVELayout.scrollBottomClearance)
        }
    }

    /// The game's slot icons (the desktop's SLOT_ATTR).
    func slotIcon(_ slot: Slot) -> Int {
        switch slot {
        case .high: 14
        case .mid: 13
        case .low: 12
        case .rig: 1137
        default: 1367
        }
    }

    func slotLabel(_ slot: Slot) -> LocalizedStringKey {
        switch slot {
        case .high: "High power"
        case .mid: "Medium power"
        case .low: "Low power"
        case .rig: "Rigs"
        case .sub: "Subsystems"
        case .drone: "Drones"
        case .cargo: "Cargo hold"
        }
    }

    func slotHead<Trailing: View>(_ icon: Int?, _ label: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            if let icon { GameIcon.attribute(icon, size: 20) }
            Text(label).font(.ui(12, .medium)).tracking(1.2).textCase(.uppercase).foregroundStyle(C.text2)
            trailing()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    /// One slot group: identical modules (type, state, charge) together as "6×", empty slots after.
    func slotGroup(_ slot: Slot) -> some View {
        let mods = moduleItems(in: slot).sorted { $0.flag.localizedStandardCompare($1.flag) == .orderedAscending }
        let total = slotCapacity(slot) ?? mods.count
        let expanded = expandedSlots.contains(slot.rawValue)
        var groups: [[ESIFittingItem]] = []
        if expanded {
            groups = mods.map { [$0] }
        } else {
            var index: [String: Int] = [:]
            for m in mods {
                let cfg = configs[m.flag] ?? ModuleConfig()
                let key = "\(m.typeId):\(cfg.state.rawValue):\(cfg.chargeTypeId ?? embeddedCharge(for: m)?.typeId ?? 0)"
                if let i = index[key] { groups[i].append(m) } else { index[key] = groups.count; groups.append([m]) }
            }
        }
        return VStack(alignment: .leading, spacing: 4) {
            slotHead(slotIcon(slot), slotLabel(slot)) {
                Text(verbatim: "\(mods.count)/\(total)").font(.mono(12)).foregroundStyle(mods.count > total ? C.bad : C.muted)
            }
            ForEach(groups, id: \.first!.flag) { g in moduleRow(g, slot: slot, expanded: expanded) }
            ForEach(emptySlotFlags(for: slot), id: \.self) { flag in emptySlotRow(slot: slot, flag: flag) }
        }
    }

    func nextState(_ s: ModuleState, typeId: Int) -> ModuleState {
        var states: [ModuleState] = [.offline, .online]
        if activation[typeId]?.activatable == true { states.append(.active) }
        if activation[typeId]?.activatable == true && activation[typeId]?.overloadable == true { states.append(.overload) }
        let i = states.firstIndex(of: s) ?? 0
        return states[(i + 1) % states.count]
    }

    func stateColor(_ s: ModuleState) -> Color {
        switch s {
        case .offline: .clear
        case .online: C.faint
        case .active: C.good
        case .overload: C.bad
        }
    }

    func stateLabel(_ s: ModuleState) -> LocalizedStringKey {
        switch s {
        case .offline: "Offline"
        case .online: "Online"
        case .active: "Active"
        case .overload: "Overheated"
        }
    }

    /// The desktop's module row: state button, "6×", the module, its charge, problems, remove.
    func moduleRow(_ group: [ESIFittingItem], slot: Slot, expanded: Bool) -> some View {
        let item = group[0]
        let flags = group.map(\.flag)
        let cfg = configs[item.flag] ?? ModuleConfig()
        let chargeId = cfg.chargeTypeId ?? embeddedCharge(for: item)?.typeId
        let problems = flags.flatMap { moduleProblems[$0] ?? [] }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    let next = nextState(cfg.state, typeId: item.typeId)
                    for f in flags { configs[f, default: ModuleConfig()].state = next }
                } label: {
                    Circle().fill(stateColor(cfg.state))
                        .overlay(Circle().strokeBorder(cfg.state == .overload ? Color(hex: 0xFF8A80) : cfg.state == .offline ? C.lineStrong : stateColor(cfg.state), lineWidth: 1.5))
                        .shadow(color: cfg.state == .overload ? C.bad : .clear, radius: 4)
                        .frame(width: 18, height: 18)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(stateLabel(cfg.state)))
                if group.count > 1 || expanded {
                    Button { if expandedSlots.contains(slot.rawValue) { expandedSlots.remove(slot.rawValue) } else { expandedSlots.insert(slot.rawValue) } } label: {
                        Text(verbatim: group.count > 1 ? "\(group.count)×" : "⋯")
                            .font(.mono(12, medium: true)).foregroundStyle(C.accentText)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(C.accentSoft, in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
                Button { sheetFlag = FlagItem(id: item.flag, group: flags) } label: {
                    HStack(spacing: 8) {
                        EVETypeIcon(typeId: item.typeId, size: 28).opacity(cfg.state == .offline ? 0.45 : 1)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: typeName(item.typeId, fallback: "#\(item.typeId)"))
                                .font(.ui(14)).foregroundStyle(cfg.state == .offline ? C.muted : C.text).lineLimit(1)
                            if let chargeId {
                                Text(verbatim: chargeNames[chargeId] ?? typeName(chargeId, fallback: "#\(chargeId)"))
                                    .font(.ui(11)).foregroundStyle(C.accentText).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if !problems.isEmpty { Text(verbatim: "⚠").foregroundStyle(C.bad) }
                Button { removeItem(flag: flags.last!, typeId: item.typeId) } label: {
                    Text(verbatim: "✕").font(.ui(13)).foregroundStyle(C.bad).padding(6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(group.count > 1 ? "Remove one module" : "Remove the module"))
            }
            ForEach(problems, id: \.self) { Text("⚠ " + $0).font(.ui(11)).foregroundStyle(C.bad).padding(.leading, 34) }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(problems.isEmpty ? C.panel : C.badFill.opacity(0.08), in: EVECut())
        .overlay(EVECut().strokeBorder(problems.isEmpty ? C.border : C.bad.opacity(0.5), lineWidth: 1))
    }

    func emptySlotRow(slot: Slot, flag: String) -> some View {
        let subsystem = subsystemDefinition(for: flag)
        return Button {
            openPicker(for: slot, preferredFlag: flag, requiredSubsystemSlotId: subsystem?.dogmaSlotId)
        } label: {
            Text(subsystem.map { "— \(String(localized: String.LocalizationValue($0.title))) —" } ?? String(localized: "— empty slot —"))
                .font(.ui(12)).foregroundStyle(C.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .overlay(EVECut().stroke(C.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Drones: launched / total per type, one more, remove (the desktop's drone rows).
    var dronesGroup: some View {
        let stacks = currentItems.filter { slotFor($0.flag) == .drone }
            .reduce(into: [(typeId: Int, count: Int)]()) { acc, item in
                if let i = acc.firstIndex(where: { $0.typeId == item.typeId }) { acc[i].count += max(1, item.quantity) } else { acc.append((item.typeId, max(1, item.quantity))) }
            }
        let launched = launchedDrones(stacks)
        return VStack(alignment: .leading, spacing: 4) {
            slotHead(nil, "Drones") {
                if let s = fitStats {
                    Text(verbatim: "\(Int(s.ship.droneBay.used))/\(Int(s.ship.droneBay.total)) m³ · \(launched.values.reduce(0, +))/\(Int(s.ship.maxActiveDrones))")
                        .font(.mono(11)).foregroundStyle(C.muted)
                }
                Spacer(minLength: 0)
                Button("+") { openPicker(for: .drone) }.buttonStyle(.canopusSmall)
            }
            ForEach(stacks, id: \.typeId) { d in
                let active = launched[d.typeId] ?? 0
                HStack(spacing: 8) {
                    EVETypeIcon(typeId: d.typeId, size: 28)
                    Text(verbatim: typeName(d.typeId, fallback: "#\(d.typeId)")).font(.ui(14)).foregroundStyle(C.text).lineLimit(1)
                    Spacer(minLength: 4)
                    Button("−") { setLaunched(d.typeId, max(0, active - 1)) }.buttonStyle(.canopusSmall)
                    Text(verbatim: "\(active)/\(d.count)").font(.mono(12, medium: true)).foregroundStyle(C.text2)
                    Button("+") { setLaunched(d.typeId, min(d.count, active + 1)) }.buttonStyle(.canopusSmall)
                    Button("×+1") { changeDrones(d.typeId, by: 1) }.buttonStyle(.canopusSmall)
                    Button { changeDrones(d.typeId, by: -d.count) } label: { Text(verbatim: "✕").foregroundStyle(C.bad).padding(4) }.buttonStyle(.plain)
                }
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(C.panel, in: EVECut())
                .overlay(EVECut().strokeBorder(C.border, lineWidth: 1))
            }
            if stacks.isEmpty {
                Button { openPicker(for: .drone) } label: {
                    Text("— no drones —").font(.ui(12)).foregroundStyle(C.muted).frame(maxWidth: .infinity).padding(.vertical, 9)
                        .overlay(EVECut().stroke(C.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Launched per type: the pilot's choice, else five in all, first stacks first (the desktop's rule).
    func launchedDrones(_ stacks: [(typeId: Int, count: Int)]) -> [Int: Int] {
        var out: [Int: Int] = [:]
        var toLaunch = 5
        for d in stacks {
            let n = droneActive[d.typeId].map { min($0, d.count) } ?? min(d.count, toLaunch)
            out[d.typeId] = n
            if droneActive[d.typeId] == nil { toLaunch = max(0, toLaunch - n) }
        }
        return out
    }

    func setLaunched(_ typeId: Int, _ n: Int) {
        droneActive[typeId] = n
        scheduleFitRefresh(debounceNanoseconds: 0)
    }

    func changeDrones(_ typeId: Int, by delta: Int) {
        var items = currentItems
        if let i = items.firstIndex(where: { slotFor($0.flag) == .drone && $0.typeId == typeId }) {
            let total = items.filter { slotFor($0.flag) == .drone && $0.typeId == typeId }.reduce(0) { $0 + $1.quantity }
            items.removeAll { slotFor($0.flag) == .drone && $0.typeId == typeId }
            let next = total + delta
            if next > 0 { items.insert(ESIFittingItem(typeId: typeId, flag: "DroneBay", quantity: next), at: min(i, items.count)) }
            if next <= 0 { droneActive[typeId] = nil }
        }
        editableItems = items
        scheduleFitRefresh(debounceNanoseconds: 0)
    }

    /// The character's implants, which the stats use.
    var implantsGroup: some View {
        VStack(alignment: .leading, spacing: 4) {
            slotHead(nil, "Implants") {
                Text(characterSkills.isEmpty ? "none: skills at V" : "the character's").font(.ui(11)).foregroundStyle(C.muted)
            }
            ForEach(implantIds, id: \.self) { id in
                HStack(spacing: 8) {
                    EVETypeIcon(typeId: id, size: 24)
                    Text(verbatim: typeName(id, fallback: "#\(id)")).font(.ui(13)).foregroundStyle(C.text2).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
            }
            if implantIds.isEmpty {
                Text("— no implants —").font(.ui(12)).foregroundStyle(C.muted).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
        }
    }

    var cargoGroup: some View {
        let grouped = Dictionary(grouping: currentItems.filter { slotFor($0.flag) == .cargo }, by: \.typeId)
        return VStack(alignment: .leading, spacing: 4) {
            slotHead(nil, "Cargo hold") { EmptyView() }
            ForEach(grouped.keys.sorted { typeName($0, fallback: "") < typeName($1, fallback: "") }, id: \.self) { id in
                HStack(spacing: 8) {
                    EVETypeIcon(typeId: id, size: 24)
                    Text(verbatim: typeName(id, fallback: "#\(id)")).font(.ui(13)).foregroundStyle(C.text2).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(verbatim: "×\(grouped[id]!.reduce(0) { $0 + $1.quantity })").font(.mono(12)).foregroundStyle(C.muted)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
            }
        }
    }

    func addType(_ type: ItemType, to slot: Slot, preferredFlag: String? = nil) {
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

    func removeItem(flag: String, typeId: Int) {
        editableItems = currentItems.filter { $0.flag != flag }
        configs[flag] = nil
        scheduleFitRefresh(debounceNanoseconds: 0)
    }

    @MainActor
    func scheduleFitRefresh(debounceNanoseconds: UInt64 = 150_000_000) {
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

    func nextFlag(for slot: Slot, in items: [ESIFittingItem]) -> String {
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

    func nextIndexedFlag(prefix: String, slot: Slot, items: [ESIFittingItem]) -> String {
        let used = Set(items.filter { slotFor($0.flag) == slot }.compactMap { item in
            Int(item.flag.replacingOccurrences(of: prefix, with: ""))
        })
        var index = 0
        while used.contains(index) { index += 1 }
        return "\(prefix)\(index)"
    }

    func sanitizeDuplicateSubsystems() {
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

    func sanitizeHardpointOverflow() {
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

    func loadProfilesAndNames(for typeIds: Set<Int>) async {
        guard let repo = env.repository, !typeIds.isEmpty else { return }
        if let profiles = try? await repo.typeProfiles(typeIds: typeIds) {
            for (id, profile) in profiles {
                moduleTypeProfiles[id] = profile
            }
        }
        await resolveLocalNames(repo: repo, typeIds: typeIds)
    }

    func refreshFitSkillRecommendations(repo: SDERepository) async {
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

    func fitSkillCategory(name: String, reason: String) -> FitSkillCategory {
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

    func mergedInfluences(_ influences: [SkillInfluence]) -> [Int: SkillInfluence] {
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

    func fitRecommendationTypeIds() -> Set<Int> {
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

    func requiredSkillTargets(repo: SDERepository, typeIds: Set<Int>) async -> [Int: (level: Int, sources: Set<String>)] {
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

    func requiredReason(_ sources: Set<String>) -> String {
        let names = sources.sorted().prefix(3).joined(separator: ", ")
        let extra = sources.count > 3 ? " +\(sources.count - 3)" : ""
        return "Required by \(names)\(extra)"
    }

    func influenceReason(_ influence: SkillInfluence) -> String {
        let groups = influence.affectedGroups.prefix(2).joined(separator: ", ")
        let attrs = influence.modifiedAttributes.prefix(2).joined(separator: ", ")
        if attrs.isEmpty {
            return "Affects \(groups)"
        }
        return "Affects \(groups) · \(attrs)"
    }

    func exportEFT(english: [Int: String]) -> String {
        let typeName = { (id: Int, fallback: String) in english[id] ?? self.typeName(id, fallback: fallback) }
        var lines: [String] = []
        lines.append("[\(typeName(fit.shipTypeId, "Ship \(fit.shipTypeId)")), \(fit.name)]")

        let moduleOrder: [Slot] = [.low, .mid, .high, .rig, .sub]
        for slot in moduleOrder {
            let modules = moduleItems(in: slot).sorted { $0.flag < $1.flag }
            if !modules.isEmpty {
                lines.append("")
                for item in modules {
                    lines.append(typeName(item.typeId, "Type \(item.typeId)"))
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
            for typeId in cargo.keys.sorted(by: { typeName($0, "") < typeName($1, "") }) {
                let quantity = cargo[typeId] ?? 1
                let name = typeName(typeId, "Type \(typeId)")
                lines.append(quantity > 1 ? "\(name) x\(quantity)" : name)
            }
        }

        return lines.joined(separator: "\n")
    }

    func esiFittingItems() -> [ESICreateFittingItem] {
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

    func sendFittingToEVE() async {
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

    func sanitizedFittingName() -> String {
        let trimmed = fit.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(50))
    }

    func sanitizedFittingDescription() -> String {
        let trimmed = fit.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = trimmed.isEmpty ? "Created by Canopus" : trimmed
        return String(description.prefix(500))
    }

    func fittingSendErrorMessage(_ error: Error) -> String {
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

}
