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
            Color.eveBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let state = skillsState {
                        summarySection(state)
                    }

                    if !queue.isEmpty {
                        queueSection
                    }

                    categoriesSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, EVELayout.scrollBottomClearance)
            }

            if isLoading {
                ProgressView()
                    .tint(Color.eveCyan)
                    .scaleEffect(1.15)
            }
        }
        .navigationTitle("Skills")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.eveBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .searchable(text: $searchText, prompt: "Search skills")
        .task(id: env.characterStore.selectedId) { await load() }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Retry") { Task { await load() } }
            Button("OK", role: .cancel) {}
        } message: {
            Text(error?.localizedDescription ?? "")
        }
    }

    private func summarySection(_ state: ESISkillsResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SKILL POINTS").hudLabel()

            HStack(spacing: 12) {
                summaryMetric("TOTAL", formatCompactSP(state.totalSp), color: .eveText)
                summaryMetric("TRAINED", "\(state.skills.count)", color: .eveCyan)
                summaryMetric("QUEUE", "\(queue.count)", color: .eveAmber)
                if let unallocated = state.unallocatedSp, unallocated > 0 {
                    summaryMetric("FREE", formatCompactSP(unallocated), color: .eveGreen)
                }
            }
        }
        .padding(14)
        .eveCard(cut: 12, border: Color.eveCyan.opacity(0.24))
    }

    private func summaryMetric(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).hudLabel()
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("SKILL QUEUE · \(queue.count)").hudLabel()
                Spacer()
                if let finish = queue.compactMap(\.finishDate).max() {
                    Text(relativeLabel(finish))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.eveText.opacity(0.45))
                }
            }

            VStack(spacing: 0) {
                ForEach(queue.prefix(6)) { row in
                    NavigationLink {
                        TypeDetailView(typeId: row.skillId, typeName: row.name)
                    } label: {
                        queueRow(row)
                    }
                    .buttonStyle(.plain)

                    if row.id != queue.prefix(6).last?.id {
                        Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 40)
                    }
                }
            }
            .padding(.vertical, 4)
            .eveCard(cut: 10)
        }
    }

    private func queueRow(_ row: SkillQueueRow) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                EVETypeIcon(typeId: row.skillId, size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.eveText)
                        .lineLimit(1)
                    Text("#\(row.queuePosition) · \(row.remainingText)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.eveText.opacity(0.42))
                }

                Spacer()

                Text(romanNumeral(row.finishedLevel))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(row.isActive ? Color.eveCyan : Color.eveAmber)
            }

            progressBar(row.progress, color: row.isActive ? .eveCyan : .eveAmber)
                .padding(.leading, 38)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SKILL CATEGORIES").hudLabel()

            filterBar

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
                            Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 58)
                        }
                    }
                }
                .eveCard(cut: 12)
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 0) {
            ForEach(SkillFilter.allCases, id: \.self) { filter in
                Button {
                    selectedFilter = filter
                } label: {
                    Text(filter.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selectedFilter == filter ? Color.eveText : Color.eveText.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if selectedFilter == filter {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.18))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func groupRow(_ group: SkillGroupSection) -> some View {
        HStack(spacing: 12) {
            EVETypeIcon(typeId: group.iconTypeId, size: 34)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(group.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.eveText)
                        .lineLimit(1)

                    if group.queueCount > 0 {
                        Text("\(group.queueCount) in Queue")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.eveCyan)
                    }
                }

                Text("\(group.skills.count) Skills · \(formatSP(group.totalSP)) SP")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.eveText.opacity(0.42))

                progressBar(group.completion, color: .eveCyan)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.eveText.opacity(0.32))
        }
        .padding(12)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(group.queueCount > 0 ? Color.eveCyan.opacity(0.45) : Color.clear)
                .frame(width: 3)
        }
    }

    private func progressBar(_ progress: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.08))
                Rectangle()
                    .fill(color)
                    .frame(width: max(0, min(geo.size.width, geo.size.width * progress)))
            }
        }
        .frame(height: 3)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(Color.eveText.opacity(0.22))
            Text("NO MATCHING SKILLS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Color.eveText.opacity(0.38))
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
            self.error = error
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
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
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

private enum SkillFilter: CaseIterable {
    case all
    case completed
    case inQueue

    var title: String {
        switch self {
        case .all: return "All"
        case .completed: return "Completed"
        case .inQueue: return "In Queue"
        }
    }

    func includes(_ skill: SkillRow) -> Bool {
        switch self {
        case .all:
            return true
        case .completed:
            return skill.level >= 5
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
            Color.eveBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
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
                                Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 58)
                            }
                        }
                    }
                    .eveCard(cut: 12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, EVELayout.scrollBottomClearance)
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.eveBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: 12) {
            EVETypeIcon(typeId: group.iconTypeId, size: 42)

            VStack(alignment: .leading, spacing: 5) {
                Text(group.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.eveText)
                Text("\(group.skills.count) skills · \(group.totalSP.formatted()) SP")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.eveText.opacity(0.45))
            }
            Spacer()
        }
        .padding(14)
        .eveCard(cut: 12, border: Color.eveCyan.opacity(0.24))
    }

    private func skillRow(_ skill: SkillRow) -> some View {
        HStack(spacing: 12) {
            EVETypeIcon(typeId: skill.id, size: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(skill.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.eveText)
                    .lineLimit(1)
                Text("\(skill.sp.formatted()) SP")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.eveText.opacity(0.42))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                levelDots(skill.level)
                if let queuedLevel = skill.queuedLevel {
                    Text("Q\(skill.queuePosition ?? 0) · L\(queuedLevel)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.eveCyan)
                }
            }
        }
        .padding(12)
    }

    private func levelDots(_ level: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index <= level ? Color.eveCyan : Color.white.opacity(0.14))
                    .frame(width: 10, height: 7)
            }
        }
    }
}
