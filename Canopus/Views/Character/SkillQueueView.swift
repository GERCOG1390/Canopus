import SwiftUI
import EVEAuth
import EVEStaticData
import Domain

struct SkillQueueView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var entries: [SkillQueueEntry] = []
    @State private var isLoading = true
    @State private var error: Error?

    private var svc: CharacterService? { env.characterStore.selectedService }
    private var totalFinish: Date? { entries.compactMap(\.finishDate).max() }

    var body: some View {
        ZStack {
            Color.eveBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    queueHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 14)

                    if entries.isEmpty && !isLoading {
                        emptyState
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                                queueRow(entry, index: i)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 40)
            }
            if isLoading { ProgressView().tint(Color.eveCyan) }
        }
        .navigationTitle("SKILL QUEUE")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.eveBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: env.characterStore.selectedId) { await load() }
        .alert("Error", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } })
        ) {
            Button("Retry") { Task { await load() } }
            Button("Dismiss", role: .cancel) {}
        } message: { Text(error?.localizedDescription ?? "") }
    }

    // MARK: - Header

    private var queueHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("QUEUE · \(entries.count)")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(Color.eveText.opacity(0.38))
                if let finish = totalFinish {
                    Text("ends \(relativeLabel(finish))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.eveText.opacity(0.38))
                }
            }
            Spacer()
            if let sp = entries.first(where: \.isActive).map(\.levelEndSP) {
                Text("\(sp.formatted()) SP")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.eveText.opacity(0.38))
            }
        }
        .overlay(alignment: .bottom) {
            Color.eveAmber.opacity(0.16).frame(height: 1).offset(y: 10)
        }
    }

    // MARK: - Queue row

    private func queueRow(_ entry: SkillQueueEntry, index: Int) -> some View {
        let isActive = entry.isActive
        let edge: Color = isActive ? .eveCyan : Color.eveAmber.opacity(0.55)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%02d", index + 1))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.eveText.opacity(0.28))
                    .frame(width: 16)

                Text(entry.skillName ?? "Skill \(entry.skillId)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.eveText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(romanNumeral(entry.finishedLevel))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(edge)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.07))
                    Rectangle().fill(edge).frame(width: geo.size.width * entry.progress)
                }
            }
            .frame(height: 3)
            .padding(.top, 11)
            .padding(.leading, 22)

            HStack {
                Text(entry.remainingText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.eveText.opacity(0.55))
                Spacer()
                if !isActive, let finish = entry.finishDate {
                    Text(finish.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 10))
                        .tracking(1.0)
                        .foregroundStyle(Color.eveText.opacity(0.35))
                }
            }
            .padding(.top, 8)
            .padding(.leading, 22)
        }
        .padding(12)
        .background(Color.eveCard)
        .overlay(alignment: .leading) {
            Rectangle().fill(edge).frame(width: 2)
        }
        .overlay(Rectangle().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 44))
                .foregroundStyle(Color.eveText.opacity(0.2))
            Text("NO SKILLS TRAINING")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.0)
                .foregroundStyle(Color.eveText.opacity(0.3))
            Text("Add skills to your training queue in EVE Online.")
                .font(.system(size: 13))
                .foregroundStyle(Color.eveText.opacity(0.42))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 40)
    }

    // MARK: - Load

    private func load() async {
        guard let service = svc else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let raw = try await service.skillQueue()
            if let repo = env.repository {
                let ids = Set(raw.map(\.skillId))
                let nameMap = (try? await repo.types(ids: ids))?.mapValues(\.name) ?? [:]
                entries = raw.map { makeEntry($0, name: nameMap[$0.skillId]) }
            } else {
                entries = raw.map { makeEntry($0) }
            }
        } catch {
            self.error = error
        }
    }

    private func makeEntry(_ item: ESISkillQueueItem, name: String? = nil) -> SkillQueueEntry {
        SkillQueueEntry(
            queuePosition: item.queuePosition, skillId: item.skillId,
            finishedLevel: item.finishedLevel, startDate: item.startDate,
            finishDate: item.finishDate, trainingStartSP: item.trainingStartSp ?? 0,
            levelStartSP: item.levelStartSp ?? 0, levelEndSP: item.levelEndSp ?? 0,
            skillName: name
        )
    }

    // MARK: - Helpers

    private func romanNumeral(_ n: Int) -> String {
        ["0","I","II","III","IV","V"][max(0, min(5, n))]
    }

    private func relativeLabel(_ date: Date) -> String {
        let s = date.timeIntervalSinceNow
        let d = Int(s) / 86400
        let h = (Int(s) % 86400) / 3600
        let m = (Int(s) % 3600) / 60
        if d > 0 { return "\(d)d \(h)h \(m)m" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
