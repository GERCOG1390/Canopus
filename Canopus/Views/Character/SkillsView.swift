import SwiftUI
import EVEAuth
import Domain
import EVEStaticData

struct SkillsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var skillsState: ESISkillsResponse?
    @State private var grouped: [(category: ItemCategory, skills: [SkillRow])] = []
    @State private var error: Error?
    @State private var isLoading = false
    @State private var groupCategoryCache: [Int: Int] = [:]

    struct SkillRow: Identifiable {
        let id: Int
        let name: String
        let level: Int
        let sp: Int
    }

    var body: some View {
        List {
            if isLoading {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
            if let state = skillsState {
                Section {
                    spSummary(state)
                }
                ForEach(grouped, id: \.category.id) { group in
                    Section(group.category.name) {
                        ForEach(group.skills) { row in
                            skillRow(row)
                        }
                    }
                }
            }
        }
        .navigationTitle("Skills")
        .task(id: env.characterStore.selectedId) { await load() }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error?.localizedDescription ?? "") }
    }

    private func spSummary(_ state: ESISkillsResponse) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total SP")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatSP(state.totalSp))
                    .font(.headline)
            }
            Spacer()
            if let unalloc = state.unallocatedSp, unalloc > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Unallocated")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatSP(unalloc))
                        .font(.headline)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func skillRow(_ row: SkillRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(.body)
                Text(formatSP(row.sp) + " SP").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            levelDots(row.level)
        }
    }

    private func levelDots(_ level: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Circle()
                    .fill(i <= level ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func load() async {
        guard let service = env.characterStore.selectedService,
              let repo = env.repository else { return }
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let response = try await service.skills()
            skillsState = response

            // Build category-grouped skill list using SDE.
            var byCategory: [Int: (ItemCategory, [SkillRow])] = [:]
            for item in response.skills {
                guard let typeInfo = try? await repo.type(id: item.skillId) else { continue }
                let catId = try await categoryId(for: typeInfo.groupId, repo: repo)
                let cat = try await repo.category(id: catId) ?? ItemCategory(id: catId, name: "Unknown", published: true)
                let row = SkillRow(id: item.skillId, name: typeInfo.name,
                                   level: item.trainedSkillLevel, sp: item.skillpointsInSkill)
                byCategory[catId, default: (cat, [])].1.append(row)
            }
            grouped = byCategory.values
                .sorted { $0.0.name < $1.0.name }
                .map { ($0.0, $0.1.sorted { $0.name < $1.name }) }
        } catch {
            self.error = error
        }
    }

    private func categoryId(for groupId: Int, repo: SDERepository) async throws -> Int {
        if let cached = groupCategoryCache[groupId] { return cached }
        let group = try await repo.group(id: groupId)
        let catId = group?.categoryId ?? 0
        groupCategoryCache[groupId] = catId
        return catId
    }

    private func formatSP(_ n: Int) -> String {
        n.formatted(.number)
    }
}
