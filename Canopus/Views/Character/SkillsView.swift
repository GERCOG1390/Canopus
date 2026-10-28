import SwiftUI
import EVEAuth
import Domain
import EVEStaticData

struct SkillsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var skillsState: ESISkillsResponse?
    @State private var skillGroups: [SkillGroupSection] = []
    @State private var queue: [SkillQueueRow] = []
    @State private var selectedFilter: SkillFilter = .all
    @State private var searchText = ""
    @State private var error: Error?
    @State private var isLoading = false

    private var filteredGroups: [SkillGroupSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return skillGroups.compactMap { group in
            let skills = group.skills.filter { skill in
                let matchesFilter = selectedFilter.includes(skill)
                let matchesSearch = query.isEmpty
                    || skill.name.lowercased().contains(query)
                    || group.name.lowercased().contains(query)
                return matchesFilter && matchesSearch
            }
            guard !skills.isEmpty else { return nil }
            return group.replacingSkills(skills)
        }
    }

    var body: some View {
        ZStack {
            C.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let state = skillsState {
                        summarySection(state)
                    }

                    if !queue.isEmpty {
                        queueSection
                    }

                    categoriesSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, EVELayout.scrollBottomClearance)
            }
            .refreshable { await load() }

            if isLoading {
                ProgressView()
                    .tint(Color.eveCyan)
                    .scaleEffect(1.15)
            }
        }
        .navigationTitle("Skills")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search skills")
        .task(id: env.dataKey) { await load() }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Retry") { Task { await load() } }
            Button("OK", role: .cancel) {}
        } message: {
            Text(error?.localizedDescription ?? "")
        }
    }

    private func summarySection(_ state: ESISkillsResponse) -> some View {
        let lvl5 = state.skills.filter { $0.activeSkillLevel >= 5 }.count
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            StatTile(label: "Total SP", value: state.totalSp.formatted(), sub: (state.unallocatedSp ?? 0) > 0 ? String(localized: "Unallocated: \((state.unallocatedSp ?? 0).formatted())") : nil)
            StatTile(label: "Skills trained", value: state.skills.count.formatted())
            StatTile(label: "At level V", value: lvl5.formatted())
            StatTile(label: "In queue", value: queue.count.formatted(), sub: queue.compactMap(\.finishDate).max().map { relativeLabel($0) })
        }
    }

    private var queueSection: some View {
        Card(title: "Training queue", actions: {
            Text("\(queue.count)").font(.ui(12)).foregroundStyle(C.muted)
        }) {
            VStack(spacing: 0) {
                ForEach(queue.prefix(10)) { row in
                    NavigationLink {
                        TypeDetailView(typeId: row.skillId, typeName: row.name)
                    } label: {
                        queueRow(row)
                    }
                    .buttonStyle(.plain)
                    if row.id != queue.prefix(10).last?.id {
                        Rectangle().fill(C.border).frame(height: 1)
                    }
                }
            }
        }
    }

    private func queueRow(_ row: SkillQueueRow) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(row.name)
                    .font(.ui(14))
                    .foregroundStyle(C.accentText)
                    .lineLimit(1)
                Text(romanNumeral(row.finishedLevel))
                    .font(.ui(14, .bold))
                    .foregroundStyle(C.text)
                Spacer()
                Text(row.remainingText)
                    .font(.ui(13))
                    .monospacedDigit()
                    .foregroundStyle(C.muted)
            }
            if row.isActive {
                progressBar(row.progress, color: C.accent)
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CanopusTabs(tabs: SkillFilter.allCases.map { ($0, $0.title) }, selection: $selectedFilter)

            if filteredGroups.isEmpty && !isLoading {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(filteredGroups) { group in
                        NavigationLink {
                            SkillGroupDetailView(group: group)
                        } label: {
                            groupRow(group)
                        }
                        .buttonStyle(.plain)

                        if group.id != filteredGroups.last?.id {
                            Rectangle().fill(C.border).frame(height: 1).padding(.leading, 16)
                        }
                    }
                }
                .canopusSurface(padding: nil)
            }
        }
    }

    private func groupRow(_ group: SkillGroupSection) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(group.name)
                    .font(.ui(15, .medium))
                    .foregroundStyle(C.text)
                    .lineLimit(1)
                if group.queueCount > 0 {
                    Pill(text: String(localized: "\(group.queueCount) in queue"), color: C.accent)
                }
                Spacer()
                Glyph(name: .chevron, size: 14)
                    .foregroundStyle(C.faint)
            }
            Text("\(group.skills.count) skills · \(formatSP(group.totalSP)) SP")
                .font(.ui(12))
                .monospacedDigit()
                .foregroundStyle(C.muted)
            progressBar(group.completion, color: C.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func progressBar(_ progress: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(C.panel2)
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(geo.size.width, geo.size.width * progress)))
            }
        }
        .frame(height: 5)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Glyph(name: .search, size: 28)
                .foregroundStyle(C.faint)
            Text("No matching skills")
                .font(.ui(14))
                .foregroundStyle(C.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .eveCard(cut: 12)
    }

    private func load() async {
        guard let service = env.characterStore.selectedService,
              let repo = env.repository else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            async let responseTask = service.skills()
            async let queueTask = service.skillQueue()

            let response = try await responseTask
            let rawQueue = (try? await queueTask) ?? []
            skillsState = response

            let skillIds = Set(response.skills.map(\.skillId)).union(rawQueue.map(\.skillId))
            let typeMap = (try? await repo.types(ids: skillIds)) ?? [:]

            let groupMap = (try? await repo.groups(ids: Set(typeMap.values.map(\.groupId)))) ?? [:]

            let queueBySkill = Dictionary(grouping: rawQueue, by: \.skillId)
            queue = rawQueue
                .sorted { $0.queuePosition < $1.queuePosition }
                .map { item in
                    SkillQueueRow(
                        id: item.queuePosition,
                        queuePosition: item.queuePosition,
                        skillId: item.skillId,
                        name: typeMap[item.skillId]?.name ?? "Skill \(item.skillId)",
                        finishedLevel: item.finishedLevel,
                        finishDate: item.finishDate,
                        progress: queueProgress(item),
                        remainingText: remainingText(item),
                        isActive: item.queuePosition == rawQueue.map(\.queuePosition).min()
                    )
                }

            let rows: [SkillRow] = response.skills.compactMap { item in
                guard let typeInfo = typeMap[item.skillId] else { return nil }
                let queued = queueBySkill[item.skillId]?.sorted { $0.queuePosition < $1.queuePosition }.first
                return SkillRow(
                    id: item.skillId,
                    name: typeInfo.name,
                    groupId: typeInfo.groupId,
                    level: item.trainedSkillLevel,
                    activeLevel: item.activeSkillLevel,
                    sp: item.skillpointsInSkill,
                    queuedLevel: queued?.finishedLevel,
                    queuePosition: queued?.queuePosition,
                    queueFinish: queued?.finishDate
                )
            }

            let groupedRows = Dictionary(grouping: rows, by: \.groupId)
            skillGroups = groupedRows.map { groupId, skills in
                let sorted = skills.sorted { $0.name < $1.name }
                return SkillGroupSection(
                    id: groupId,
                    name: groupMap[groupId]?.name ?? "Group \(groupId)",
                    iconTypeId: sorted.first?.id ?? groupId,
                    skills: sorted
                )
            }
            .sorted { $0.name < $1.name }
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }

    private func queueProgress(_ item: ESISkillQueueItem) -> Double {
        guard item.queuePosition == 0 || item.startDate != nil else { return 0 }
        if let start = item.startDate, let finish = item.finishDate {
            let total = finish.timeIntervalSince(start)
            guard total > 0 else { return 1 }
            return max(0, min(1, Date().timeIntervalSince(start) / total))
        }
        let startSP = Double(item.levelStartSp ?? 0)
        let endSP = Double(item.levelEndSp ?? 0)
        let current = Double(item.trainingStartSp ?? 0)
        guard endSP > startSP else { return 0 }
        return max(0, min(1, (current - startSP) / (endSP - startSP)))
    }

    private func remainingText(_ item: ESISkillQueueItem) -> String {
        guard let finishDate = item.finishDate else { return "queued" }
        return relativeLabel(finishDate)
    }

    private func relativeLabel(_ date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return String(localized: "\(days)d \(hours)h") }
        if hours > 0 { return String(localized: "\(hours)h \(minutes)m") }
        return String(localized: "\(minutes)m")
    }

    private func romanNumeral(_ n: Int) -> String {
        ["0", "I", "II", "III", "IV", "V"][max(0, min(5, n))]
    }

    private func formatSP(_ n: Int) -> String {
        n.formatted(.number)
    }

    private func formatCompactSP(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1f M", Double(n) / 1_000_000)
        }
        if n >= 1_000 {
            return String(format: "%.1f K", Double(n) / 1_000)
        }
        return "\(n)"
    }
}

private enum SkillFilter: CaseIterable, Hashable {
    case all
    case notMaxed
    case inQueue

    var title: String {
        switch self {
        case .all: return "Trained"
        case .notMaxed: return "Not at V"
        case .inQueue: return "In queue"
        }
    }

    func includes(_ skill: SkillRow) -> Bool {
        switch self {
        case .all:
            return true
        case .notMaxed:
            return skill.level < 5
        case .inQueue:
            return skill.queuePosition != nil
        }
    }
}

private struct SkillGroupSection: Identifiable {
    let id: Int
    let name: String
    let iconTypeId: Int
    let skills: [SkillRow]

    var totalSP: Int {
        skills.reduce(0) { $0 + $1.sp }
    }

    var queueCount: Int {
        skills.filter { $0.queuePosition != nil }.count
    }

    var completion: Double {
        guard !skills.isEmpty else { return 0 }
        let trained = skills.reduce(0) { $0 + max(0, min(5, $1.level)) }
        return Double(trained) / Double(skills.count * 5)
    }

    func replacingSkills(_ skills: [SkillRow]) -> SkillGroupSection {
        SkillGroupSection(id: id, name: name, iconTypeId: iconTypeId, skills: skills)
    }
}

private struct SkillRow: Identifiable {
    let id: Int
    let name: String
    let groupId: Int
    let level: Int
    let activeLevel: Int
    let sp: Int
    let queuedLevel: Int?
    let queuePosition: Int?
    let queueFinish: Date?
}

private struct SkillQueueRow: Identifiable {
    let id: Int
    let queuePosition: Int
    let skillId: Int
    let name: String
    let finishedLevel: Int
    let finishDate: Date?
    let progress: Double
    let remainingText: String
    let isActive: Bool
}

private struct SkillGroupDetailView: View {
    let group: SkillGroupSection

    var body: some View {
        ZStack {
            C.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header

                    VStack(spacing: 0) {
                        ForEach(group.skills) { skill in
                            NavigationLink {
                                TypeDetailView(typeId: skill.id, typeName: skill.name)
                            } label: {
                                skillRow(skill)
                            }
                            .buttonStyle(.plain)

                            if skill.id != group.skills.last?.id {
                                Rectangle().fill(C.border).frame(height: 1).padding(.leading, 16)
                            }
                        }
                    }
                    .canopusSurface(padding: nil)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, EVELayout.scrollBottomClearance)
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(spacing: 10) {
            StatTile(label: "Skills", value: group.skills.count.formatted())
            StatTile(label: "SP", value: group.totalSP.formatted())
        }
    }

    private func skillRow(_ skill: SkillRow) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(skill.name)
                    .font(.ui(15))
                    .foregroundStyle(C.accentText)
                    .lineLimit(1)
                Text("\(skill.sp.formatted()) SP")
                    .font(.ui(12))
                    .monospacedDigit()
                    .foregroundStyle(C.muted)
            }
            Spacer()
            if let queuedLevel = skill.queuedLevel {
                Text("→ \(["0", "I", "II", "III", "IV", "V"][max(0, min(5, queuedLevel))])")
                    .font(.ui(12, .semibold))
                    .foregroundStyle(C.accentText)
            }
            LevelPips(level: skill.level)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}
