// Trial skill levels for the fitting (the desktop's TrialSkills.tsx): see the fit as it would be with some
// skills at another level — a hull skill not started yet, a support skill at IV instead of V — without
// training anything. The levels go on top of the character's skills (or of "all V"); the metrics at the
// top show the difference from the real numbers while any are set.

import SwiftUI
import Domain
import EVEAuth
import EVEStaticData

struct TrialSkillsCard: View {
    /// The fit's required skills and those changing its modules, with the level the fit needs.
    let candidates: [Int: (name: String, required: Int?)]
    /// The character's levels; empty = every skill at V.
    let real: [Int: Int]
    @Binding var trial: [Int: Int]
    let service: CharacterService
    @Environment(AppEnvironment.self) private var env
    @State private var open = UserDefaults.standard.string(forKey: "fitTrial") != nil && _isDebugAssertConfiguration()
    @State private var extra: [Int: String] = [:]
    @State private var query = ""
    @State private var hits: [ItemType] = []
    /// Rank, primary and secondary attribute per skill (training time).
    @State private var skillAttrs: [Int: [Int: Double]] = [:]
    @State private var attributes: [Int: Int]?

    private var allV: Bool { real.isEmpty }
    private func have(_ id: Int) -> Int { allV ? 5 : real[id] ?? 0 }
    private func name(_ id: Int) -> String { candidates[id]?.name ?? extra[id] ?? "#\(id)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { open.toggle() } label: {
                HStack(spacing: 6) {
                    Text(verbatim: open ? "▾" : "▸").foregroundStyle(C.muted)
                    Text("Trial skill levels").font(.ui(13, .semibold)).foregroundStyle(C.text)
                    if trial.isEmpty {
                        Text("— see the fit with other levels").font(.ui(11)).foregroundStyle(C.muted).lineLimit(1)
                    } else {
                        let ms = trial.reduce(0.0) { $0 + seconds($1.key, to: $1.value) }
                        Text(ms > 0 ? String(localized: "\(trial.count) skills · train ≈ \(Fmt.duration(seconds: ms))") : String(localized: "\(trial.count) skills"))
                            .font(.ui(11, .medium)).foregroundStyle(C.warn).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open { content }
        }
        .padding(12)
        .background(C.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(trial.isEmpty ? C.border : C.warn.opacity(0.5)))
        .task(id: "\(open)/\(trial.count)") { if open { await loadAttributes() } }
        .task(id: query) { await search() }
    }

    @ViewBuilder private var content: some View {
        Text(allV ? "Fitting with every skill at V: lower some skills here to see what changes."
                  : "Levels on top of the character's skills: set a skill you don't have yet to I–V and see the stats. Hull bonuses come from the skills the ship requires.")
            .font(.ui(11)).foregroundStyle(C.faint)
        HStack(spacing: 6) {
            Button("Required at V") {
                var t = trial
                for id in candidates.keys where have(id) < 5 { t[id] = 5 }
                trial = t
            }
            .buttonStyle(.canopusSmall)
            Button("Reset") { trial = [:] }.buttonStyle(.canopusSmall).disabled(trial.isEmpty)
        }
        TextField("+ another skill…", text: $query)
            .font(.ui(13)).autocorrectionDisabled().textInputAutocapitalization(.never)
            .padding(.horizontal, 10).frame(minHeight: 34)
            .background(C.panel2, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(C.border))
        ForEach(hits) { t in
            Button {
                extra[t.id] = t.name
                query = ""
                hits = []
                Task { await loadSkillAttrs([t.id]) }
            } label: {
                HStack(spacing: 6) {
                    EVETypeIcon(typeId: t.id, size: 20)
                    Text(verbatim: t.name).font(.ui(13)).foregroundStyle(C.text)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        let ids = Set(candidates.keys).union(extra.keys).union(trial.keys)
            .sorted { a, b in
                let ta = trial[a] != nil, tb = trial[b] != nil
                return ta != tb ? ta : name(a).localizedCaseInsensitiveCompare(name(b)) == .orderedAscending
            }
        ForEach(ids, id: \.self) { id in row(id) }
    }

    private func row(_ id: Int) -> some View {
        let level = trial[id] ?? have(id)
        let changed = trial[id] != nil
        let secs = seconds(id, to: level)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                EVETypeIcon(typeId: id, size: 18)
                Text(verbatim: name(id)).font(.ui(12, changed ? .semibold : .regular)).foregroundStyle(changed ? C.warn : C.text).lineLimit(1)
                LevelPips(level: have(id))
                Spacer(minLength: 4)
                Group {
                    if secs > 0 { Text("train \(Fmt.duration(seconds: secs))") }
                    else if changed, level < have(id) { Text("below yours") }
                    else if let r = candidates[id]?.required { Text("needs \(roman(r))") }
                }
                .font(.ui(10)).foregroundStyle(C.muted)
            }
            HStack(spacing: 4) {
                ForEach(0...5, id: \.self) { x in
                    Button(x == 0 ? "—" : roman(x)) { set(id, x) }
                        .buttonStyle(CanopusButtonStyle(kind: level == x ? (changed ? .primary : .ghost) : .ghost, small: true))
                        .opacity(level == x || changed ? 1 : 0.75)
                }
            }
        }
        .padding(.vertical, 3)
        .task { if skillAttrs[id] == nil { await loadSkillAttrs([id]) } }
    }

    private func roman(_ n: Int) -> String { ["0", "I", "II", "III", "IV", "V"][max(0, min(5, n))] }

    private func set(_ id: Int, _ level: Int) {
        var t = trial
        if level == have(id) { t[id] = nil } else { t[id] = level }
        trial = t
    }

    /// Seconds to train from the character's level to `level` (none for "all V" or going down).
    private func seconds(_ id: Int, to level: Int) -> Double {
        guard !allV, level > have(id), let a = skillAttrs[id], let attrs = attributes else { return 0 }
        let rank = Int(a[275] ?? 1)
        let rate = Double(attrs[Int(a[180] ?? 0)] ?? 20) + Double(attrs[Int(a[181] ?? 0)] ?? 20) / 2
        let sp = skillPoints(rank: rank, level: level) - skillPoints(rank: rank, level: have(id))
        return rate > 0 ? Double(sp) / rate * 60 : 0
    }

    private func loadAttributes() async {
        // Names of trial skills the fit doesn't list (a skill added before the fit changed).
        let unnamed = Set(trial.keys).subtracting(candidates.keys).subtracting(extra.keys)
        if !unnamed.isEmpty, let types = try? await env.repository?.types(ids: unnamed) {
            for (id, t) in types { extra[id] = t.name }
        }
        guard attributes == nil, !allV else { return }
        attributes = await PilotAttributes.load(service: service, repository: env.repository)?.effective
        await loadSkillAttrs(Set(candidates.keys).union(trial.keys))
    }

    private func loadSkillAttrs(_ ids: Set<Int>) async {
        let missing = ids.subtracting(skillAttrs.keys)
        guard !missing.isEmpty, let maps = try? await env.repository?.typeAttributeMaps(typeIds: missing) else { return }
        skillAttrs.merge(maps) { _, b in b }
    }

    /// Skills by name (a skill has a rank, attribute 275).
    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, let repo = env.repository else { hits = []; return }
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled, let found = try? await repo.search(q) else { return }
        let maps = (try? await repo.typeAttributeMaps(typeIds: Set(found.prefix(40).map(\.id)))) ?? [:]
        hits = Array(found.prefix(40).filter { maps[$0.id]?[275] != nil }.prefix(6))
    }
}
