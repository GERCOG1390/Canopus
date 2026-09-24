import WidgetKit
import SwiftUI

// MARK: - Entry

struct SkillEntry: TimelineEntry {
    let date: Date
    let characterName: String?
    let skillName: String?
    let skillLevel: Int?
    let finishDate: Date?
    let queueCount: Int
}

// MARK: - Provider

struct SkillProvider: TimelineProvider {
    func placeholder(in context: Context) -> SkillEntry {
        SkillEntry(
            date: .now,
            characterName: "Pilot Name",
            skillName: "Drone Interfacing",
            skillLevel: 4,
            finishDate: .now.addingTimeInterval(3600 * 18),
            queueCount: 12
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SkillEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SkillEntry>) -> Void) {
        let entry = currentEntry()
        var nextRefresh = Date.now.addingTimeInterval(3600)
        if let finish = entry.finishDate, finish > .now, finish < nextRefresh {
            nextRefresh = finish.addingTimeInterval(60)
        }
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func currentEntry() -> SkillEntry {
        guard let data = WidgetData.load() else {
            return SkillEntry(date: .now, characterName: nil, skillName: nil,
                              skillLevel: nil, finishDate: nil, queueCount: 0)
        }
        return SkillEntry(
            date: .now,
            characterName: data.characterName,
            skillName: data.activeSkillName,
            skillLevel: data.activeSkillLevel,
            finishDate: data.activeSkillFinishDate,
            queueCount: data.queueCount
        )
    }
}

// MARK: - Views

private let romanNumerals = ["0", "I", "II", "III", "IV", "V"]

private func roman(_ n: Int?) -> String {
    guard let n else { return "" }
    return romanNumerals[max(0, min(5, n))]
}

struct SkillWidgetSmallView: View {
    let entry: SkillEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.characterName ?? "—")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let skill = entry.skillName {
                VStack(alignment: .leading, spacing: 2) {
                    Text(skill)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .lineLimit(3)
                    Text("→ \(roman(entry.skillLevel))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                finishLabel
            } else {
                Text("No active\ntraining")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var finishLabel: some View {
        if let finish = entry.finishDate {
            if finish > Date() {
                Text(finish, style: .timer)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("Finishing…")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct SkillWidgetMediumView: View {
    let entry: SkillEntry

    var body: some View {
        HStack {
            SkillWidgetSmallView(entry: entry)
            Divider().padding(.vertical, 12)
            VStack(alignment: .leading, spacing: 8) {
                Label("\(entry.queueCount) skills queued", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let finish = entry.finishDate {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Finishes at")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(finish, style: .time)
                            .font(.callout.monospacedDigit())
                    }
                }
            }
            .padding()
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Entry view

struct SkillWidgetEntryView: View {
    let entry: SkillEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium:
            SkillWidgetMediumView(entry: entry)
        default:
            SkillWidgetSmallView(entry: entry)
        }
    }
}

// MARK: - Widget

struct SkillTrainingWidget: Widget {
    let kind = "SkillTrainingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SkillProvider()) { entry in
            SkillWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Skill Training")
        .description("Shows your active EVE Online skill in training.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
