import SwiftUI
import EVEAuth
import EVEStaticData
import Domain

struct IndustryView: View {
    let characterService: CharacterService
    @Environment(AppEnvironment.self) private var env
    @State private var jobs: [ESIIndustryJob] = []
    @State private var typeNames: [Int: String] = [:]
    @State private var isLoading = true
    @State private var error: Error?

    private var readyJobs: [ESIIndustryJob] {
        jobs.filter { $0.status == "ready" }
    }
    private var activeJobs: [ESIIndustryJob] {
        jobs.filter { $0.status == "active" || $0.status == "paused" }
            .sorted { $0.endDate < $1.endDate }
    }
    private var deliveredJobs: [ESIIndustryJob] {
        jobs.filter { $0.status == "delivered" }
            .sorted { $0.endDate > $1.endDate }
    }

    var body: some View {
        List {
            if !readyJobs.isEmpty {
                Section("Ready to deliver (\(readyJobs.count))") {
                    ForEach(readyJobs) { job in
                        IndustryJobRow(job: job, typeNames: typeNames)
                    }
                }
            }
            if !activeJobs.isEmpty {
                Section("In progress (\(activeJobs.count))") {
                    ForEach(activeJobs) { job in
                        IndustryJobRow(job: job, typeNames: typeNames)
                    }
                }
            }
            if !deliveredJobs.isEmpty {
                Section("Recently delivered") {
                    ForEach(deliveredJobs.prefix(20)) { job in
                        IndustryJobRow(job: job, typeNames: typeNames)
                    }
                }
            }
        }
        .navigationTitle("Industry")
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if isLoading {
                ProgressView()
            } else if jobs.isEmpty && error == nil {
                ContentUnavailableView(
                    "No industry jobs",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("Start a job in EVE Online to see it here.")
                )
            }
        }
        .task { await load() }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Retry") { Task { await load() } }
            Button("Dismiss", role: .cancel) {}
        } message: { Text(error?.localizedDescription ?? "") }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            jobs = try await characterService.industryJobs()
            let ids: Set<Int> = Set(jobs.flatMap { job -> [Int] in
                var ids = [job.blueprintTypeId]
                if let p = job.productTypeId { ids.append(p) }
                return ids
            })
            if let repo = env.repository {
                for id in ids {
                    if let t = try? await repo.type(id: id) { typeNames[id] = t.name }
                }
            }
        } catch {
            self.error = error
        }
    }
}

private struct IndustryJobRow: View {
    let job: ESIIndustryJob
    let typeNames: [Int: String]

    private var displayTypeId: Int { job.productTypeId ?? job.blueprintTypeId }
    private var displayName: String {
        typeNames[displayTypeId] ?? typeNames[job.blueprintTypeId] ?? "Job \(job.jobId)"
    }

    var body: some View {
        HStack(spacing: 12) {
            EVETypeIcon(typeId: displayTypeId, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(activityLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if job.runs > 1 {
                        Text("×\(job.runs)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                switch job.status {
                case "active":
                    HStack(spacing: 3) {
                        Text(job.endDate, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tint)
                        Text("remaining")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                case "paused":
                    Text("Paused")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                case "ready":
                    Text("Ready — deliver in game")
                        .font(.caption2)
                        .foregroundStyle(.green)
                default:
                    EmptyView()
                }

                HStack(spacing: 8) {
                    Text(durationText)
                    if let cost = job.cost, cost > 0 {
                        Text("Cost \(isk(cost))")
                    }
                    Text("Facility \(job.facilityId)")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)
            statusBadge
        }
        .padding(.vertical, 2)
    }

    private var statusBadge: some View {
        Text(job.status.capitalized)
            .font(.caption2.bold())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.18), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch job.status {
        case "active": return .accentColor
        case "ready": return .green
        case "paused": return .orange
        default: return .secondary
        }
    }

    private var activityLabel: String {
        switch job.activityId {
        case 1: return "Manufacturing"
        case 3: return "TE Research"
        case 4: return "ME Research"
        case 5: return "Copying"
        case 7: return "Reverse Engineering"
        case 8: return "Invention"
        case 9: return "Reactions"
        default: return "Activity \(job.activityId)"
        }
    }

    private var durationText: String {
        let days = job.duration / 86400
        let hours = (job.duration % 86400) / 3600
        if days > 0 { return "\(days)d \(hours)h" }
        return "\(max(1, hours))h"
    }

    private func isk(_ amount: Double) -> String {
        if amount >= 1_000_000_000 { return String(format: "%.2fB", amount / 1_000_000_000) }
        if amount >= 1_000_000     { return String(format: "%.2fM", amount / 1_000_000) }
        if amount >= 1_000         { return String(format: "%.1fK", amount / 1_000) }
        return String(format: "%.0f", amount)
    }
}
