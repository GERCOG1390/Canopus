// The fit screen's stats and tools tabs, and the fit snapshot.

import SwiftUI
import EVEAuth
import EVEStaticData
import Domain
#if canImport(UIKit)
import UIKit
#endif

extension FitDetailView {
    // MARK: - Stats tab

    var statsTabView: some View {
        ScrollViewReader { proxy in
        ScrollView {
            if let s = fitStats {
                VStack(alignment: .leading, spacing: 12) {
                    if let fittingWarning {
                        warningBand(fittingWarning)
                    }
                    TrialSkillsCard(candidates: trialCandidates, real: characterSkills, trial: $trialLevels,
                                    service: characterService)
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

    func fitSkillsSection() -> some View {
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

    func fitSkillBucket(_ title: String, skills: [FitSkillRecommendation], color: Color) -> some View {
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

    func fitSkillRow(_ skill: FitSkillRecommendation, color: Color) -> some View {
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

    func warningBand(_ text: String) -> some View {
        Text(text)
            .font(.ui(11, .medium)).monospacedDigit()
            .foregroundStyle(Color.eveAmber)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.eveAmber.opacity(0.10))
    }

    func statItem(_ label: String, _ value: String, color: Color = .eveText, iconId: Int? = nil) -> some View {
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

    var toolsTabView: some View {
        ScrollView {
            if let spec = fitSpec {
                FitToolsView(context: FitToolContext(
                    spec: spec,
                    skills: skillSource,
                    levels: characterSkills.isEmpty ? nil : characterSkills,
                    typeName: { id in chargeNames[id] ?? typeName(id, fallback: "#\(id)") },
                    apply: applySwaps,
                    service: characterService,
                    openFit: { toolFit = DraftFitRoute(fit: $0, typeNames: typeNames) }
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
    func applySwaps(_ swaps: [(from: Int, to: Int, isDrone: Bool)]) {
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
    func openFitShot() async {
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

}
