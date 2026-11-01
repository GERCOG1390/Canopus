// The skill planner (the desktop's character/SkillPlanner.tsx): goals — fits, ships, modules or skills to a
// level — become the queue in training order with the time for the pilot's attributes, the best remap,
// two remaps split along the plan, +5 implants, and the large skill injectors that would cover it.

import SwiftUI
import Domain
import EVEAuth
import EVEStaticData

private struct PlanGoal: Codable, Hashable {
    let typeId: Int
    /// For a skill goal: the level to reach
    var level: Int?
}

private let goalsKey = "skillPlan.goals"
private let yearMinutes = 365.0 * 24 * 60
private let dayMinutes = 24.0 * 60
private let largeInjector = 40520

/// Every legal remap: each attribute 17–27, 14 points on top of 5 × 17.
private let allRemaps: [[Int: Int]] = {
    var out: [[Int: Int]] = []
    for a in 0...10 { for b in 0...10 where a + b <= 14 { for c in 0...10 where a + b + c <= 14 { for d in 0...10 where a + b + c + d <= 14 {
        let e = 14 - a - b - c - d
        guard e <= 10 else { continue }
        out.append([164: 17 + a, 165: 17 + b, 166: 17 + c, 167: 17 + d, 168: 17 + e])
    } } } }
    return out
}()

private struct TodoStep: Hashable {
    let step: SkillPlanStep
    /// Skill points still to train for this level
    let sp: Int
}

private func rate(_ s: SkillPlanStep, _ a: [Int: Int]) -> Double {
    max(1, Double(a[s.primary] ?? 0) + Double(a[s.secondary] ?? 0) / 2)
}

private func planMinutes(_ steps: [TodoStep], _ a: [Int: Int]) -> Double {
    steps.reduce(0) { $0 + Double($1.sp) / rate($1.step, a) }
}

private func plus(_ a: [Int: Int], _ b: [Int: Int]) -> [Int: Int] {
    Dictionary(uniqueKeysWithValues: attributeIds.map { ($0, (a[$0] ?? 0) + (b[$0] ?? 0)) })
}

/// The best pair of remaps: the first now, the second after `k` levels, no earlier than `wait` minutes in.
private func twoRemaps(_ steps: [TodoStep], bonus: [Int: Int], wait: Double) -> (first: [Int: Int], second: [Int: Int], k: Int, switchAt: Double, minutes: Double)? {
    let n = steps.count
    guard n >= 2 else { return nil }
    let prefix: [[Double]] = allRemaps.map { r in
        let a = plus(r, bonus)
        var p = [Double](repeating: 0, count: n + 1)
        for k in 0..<n { p[k + 1] = p[k] + Double(steps[k].sp) / rate(steps[k].step, a) }
        return p
    }
    // Best remap for everything after step k.
    let tail: [(r: Int, min: Double)] = (0...n).map { k in
        var best = (r: 0, min: Double.infinity)
        for (r, p) in prefix.enumerated() where p[n] - p[k] < best.min { best = (r, p[n] - p[k]) }
        return best
    }
    var best: (first: [Int: Int], second: [Int: Int], k: Int, switchAt: Double, minutes: Double)?
    for (r, p) in prefix.enumerated() {
        for k in 1..<n where p[k] >= wait {
            let m = p[k] + tail[k].min
            if best == nil || m < best!.minutes { best = (allRemaps[r], allRemaps[tail[k].r], k, p[k], m) }
        }
    }
    return best
}

/// Skill points a large skill injector gives at a character's total SP.
private func injectorSP(totalSP: Int) -> Int {
    switch totalSP {
    case ..<5_000_000: 500_000
    case ..<50_000_000: 400_000
    case ..<80_000_000: 300_000
    default: 150_000
    }
}

struct SkillPlannerTab: View {
    let characterService: CharacterService
    @Environment(AppEnvironment.self) private var env
    @State private var goals: [PlanGoal] = {
        (UserDefaults.standard.data(forKey: goalsKey)).flatMap { try? JSONDecoder().decode([PlanGoal].self, from: $0) } ?? []
    }()
    @State private var steps: [SkillPlanStep]?
    @State private var names: [Int: String] = [:]
    @State private var skillCategory: Set<Int> = []
    @State private var pilotSkills: [Int: (level: Int, sp: Int)] = [:]
    @State private var totalSP = 0
    @State private var attributes: PilotAttributes?
    @State private var gameFits: [ESIFitting] = []
    @State private var injectorPrice: Double?
    @State private var query = ""
    @State private var hits: [ItemType] = []
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                goalsCard
                if !goals.isEmpty { result }
            }
            .padding(16)
        }
        .task(id: "\(env.dataKey)/\(env.repositoryVersion)") { await loadPilot() }
        #if DEBUG
        // Debug builds: `-planGoal 28659` puts a goal in the plan (screenshots).
        .task {
            let id = UserDefaults.standard.integer(forKey: "planGoal")
            if id > 0, !goals.contains(where: { $0.typeId == id }) { goals = [PlanGoal(typeId: id)] }
        }
        #endif
        .task(id: "\(goals.map { "\($0.typeId):\($0.level ?? 0)" })/\(env.repositoryVersion)") {
            if let data = try? JSONEncoder().encode(goals) { UserDefaults.standard.set(data, forKey: goalsKey) }
            await loadPlan()
        }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2, let repo = env.repository else { hits = []; return }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            hits = Array(((try? await repo.search(q)) ?? []).prefix(8))
            let groups = Set(hits.map(\.groupId))
            let cats = (try? await repo.groups(ids: groups)) ?? [:]
            skillCategory.formUnion(hits.filter { cats[$0.groupId]?.categoryId == 16 }.map(\.id))
        }
    }

    // MARK: Goals

    private var goalsCard: some View {
        Card(String(localized: "Goals")) {
            FlowRow(spacing: 6) {
                if let d = FitDraftStore.shared.draft {
                    Button(String(localized: "+ fit from fitting: \(names[d.shipTypeId] ?? d.typeNames[d.shipTypeId] ?? d.name)")) {
                        add(fitGoals(ship: d.shipTypeId, items: d.items.map(\.typeId) + d.configs.values.compactMap(\.chargeTypeId)))
                    }
                    .buttonStyle(.canopusSmall)
                }
                if !gameFits.isEmpty {
                    Menu {
                        ForEach(gameFits) { f in
                            Button { add(fitGoals(ship: f.shipTypeId, items: f.items.map(\.typeId))) } label: {
                                Text(verbatim: "\(names[f.shipTypeId] ?? "#\(f.shipTypeId)") — \(f.name)")
                            }
                        }
                    } label: {
                        Text("+ fit from the game…").font(.ui(12, .medium)).foregroundStyle(C.accentText)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(C.border))
                    }
                }
            }
            HStack(spacing: 8) {
                Glyph(name: .search, size: 14).foregroundStyle(C.muted)
                TextField("+ ship, module or skill…", text: $query).font(.ui(14)).autocorrectionDisabled().textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 10).frame(minHeight: 38)
            .background(C.panel2, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(C.border))
            ForEach(hits) { t in
                Button {
                    add([PlanGoal(typeId: t.id, level: skillCategory.contains(t.id) ? 5 : nil)])
                    names[t.id] = t.name
                    query = ""
                } label: { MarketTypeRow(type: t) }
                .buttonStyle(.plain)
            }
            if goals.isEmpty {
                Text("Add what you want to fly or use: a fit, a ship, a module — or a skill to the level you need.")
                    .font(.ui(12)).foregroundStyle(C.muted)
            } else {
                ForEach(Array(goals.enumerated()), id: \.offset) { i, g in
                    HStack(spacing: 6) {
                        EVETypeIcon(typeId: g.typeId, size: 20)
                        Text(verbatim: names[g.typeId] ?? "#\(g.typeId)").font(.ui(13)).foregroundStyle(C.text).lineLimit(1)
                        if let level = g.level {
                            Menu {
                                ForEach(1...5, id: \.self) { l in Button { goals[i].level = l } label: { Text(verbatim: roman(l)) } }
                            } label: {
                                Text(verbatim: roman(level)).font(.ui(12, .bold)).foregroundStyle(C.accentText)
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(C.border))
                            }
                        }
                        Spacer(minLength: 4)
                        Button { goals.remove(at: i) } label: { Text(verbatim: "✕").font(.ui(12)).foregroundStyle(C.muted) }.buttonStyle(.plain)
                    }
                }
                Button("Clear") { goals = [] }.buttonStyle(.canopusSmall)
            }
        }
    }

    private func fitGoals(ship: Int, items: [Int]) -> [PlanGoal] {
        var seen: Set<Int> = []
        return ([ship] + items).filter { $0 > 0 && seen.insert($0).inserted }.map { PlanGoal(typeId: $0) }
    }

    private func add(_ list: [PlanGoal]) {
        for g in list where !goals.contains(where: { $0.typeId == g.typeId && $0.level == g.level }) { goals.append(g) }
    }

    // MARK: Result

    /// What is left to train, with SP already put into a partially trained level.
    private var todo: [TodoStep] {
        (steps ?? []).compactMap { s in
            let have = pilotSkills[s.skill]?.level ?? 0
            guard have < s.level else { return nil }
            let from = skillPoints(rank: s.rank, level: s.level - 1)
            let to = skillPoints(rank: s.rank, level: s.level)
            let done = s.level == have + 1 ? max(0, min(to, pilotSkills[s.skill]?.sp ?? 0) - from) : 0
            return TodoStep(step: s, sp: to - from - done)
        }
    }

    @ViewBuilder private var result: some View {
        let todo = self.todo
        if let steps, todo.isEmpty, !steps.isEmpty || !goals.isEmpty {
            Text("Everything is trained — you can fly it.").font(.ui(13)).foregroundStyle(C.good)
        } else if !todo.isEmpty {
            let base = attributes?.base ?? PilotAttributes.newCharacter
            let bonus = attributes?.implantBonus ?? [:]
            let plus5 = Dictionary(uniqueKeysWithValues: attributeIds.map { ($0, max(bonus[$0] ?? 0, 5)) })
            let now = planMinutes(todo, plus(base, bonus))
            let best = allRemaps.map { (attrs: $0, min: planMinutes(todo, plus($0, bonus))) }.min { $0.min < $1.min }!
            let raw = attributes?.raw
            let cooldown = max(0, (raw?.accruedRemapCooldownDate?.timeIntervalSinceNow ?? 0) / 60)
            let bonusRemaps = raw?.bonusRemaps ?? 0
            let remapsNow = (cooldown == 0 ? 1 : 0) + bonusRemaps
            let secondWait = remapsNow >= 2 ? 0 : remapsNow == 1 ? (cooldown == 0 ? yearMinutes : cooldown) : cooldown + yearMinutes
            let two = twoRemaps(todo, bonus: bonus, wait: secondWait).flatMap { $0.minutes < best.min - dayMinutes ? $0 : nil }
            let sp = todo.reduce(0) { $0 + $1.sp }
            let injectors = injectorsNeeded(sp: sp)
            let skipped = (steps?.count ?? 0) - todo.count

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                StatTile(label: "Time now", value: Fmt.duration(seconds: now * 60),
                         sub: skipped > 0 ? String(localized: "\(todo.count) levels · \(skipped) already trained") : String(localized: "\(todo.count) levels"))
                StatTile(label: "With the best remap", value: Fmt.duration(seconds: best.min * 60), sub: attrLine(best.attrs))
                if let two {
                    StatTile(label: "Two remaps", value: Fmt.duration(seconds: two.minutes * 60),
                             sub: String(localized: "\(attrLine(two.first)) → after \(two.k) levels: \(attrLine(two.second))"))
                }
                StatTile(label: "With +5 implants", value: Fmt.duration(seconds: planMinutes(todo, plus(base, plus5)) * 60))
                StatTile(label: "Remap + implants +5", value: Fmt.duration(seconds: planMinutes(todo, plus(best.attrs, plus5)) * 60))
                StatTile(label: "Large skill injectors", value: "\(injectors)",
                         sub: injectorPrice.map { String(localized: "≈ \(Fmt.isk(Double(injectors) * $0)) at Jita · \(sp.formatted()) SP") } ?? String(localized: "\(sp.formatted()) SP"))
            }
            if attributes != nil {
                let when = cooldown == 0 ? String(localized: "A remap is available now") : String(localized: "Next remap in \(Fmt.duration(seconds: cooldown * 60))")
                Text(verbatim: when + (bonusRemaps > 0 ? String(localized: " · bonus remaps: \(bonusRemaps)") : ""))
                    .font(.ui(12)).foregroundStyle(C.muted)
            }
            queueCard(todo, attrs: plus(base, bonus))
        } else if steps == nil {
            ProgressView().tint(C.accent).frame(maxWidth: .infinity)
        }
    }

    private func queueCard(_ todo: [TodoStep], attrs: [Int: Int]) -> some View {
        // Each level's time and the running total, worked out before the rows are built.
        var running = 0.0
        let rows = todo.map { t -> (step: TodoStep, minutes: Double, total: Double) in
            let m = Double(t.sp) / rate(t.step, attrs)
            running += m
            return (t, m, running)
        }
        return Card(title: String(localized: "Training queue"), actions: {
            Button(copied ? String(localized: "Copied") : String(localized: "Copy list")) { Task { await copyPlan(todo) } }
                .buttonStyle(.canopusSmall)
        }) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    let t = row.step, minutes = row.minutes, total = row.total
                    HStack(spacing: 6) {
                        Text(verbatim: "\(i + 1)").font(.mono(11)).foregroundStyle(C.faint).frame(width: 26, alignment: .leading)
                        NavigationLink { TypeDetailView(typeId: t.step.skill, typeName: names[t.step.skill] ?? "") } label: {
                            Text(verbatim: names[t.step.skill] ?? "#\(t.step.skill)").font(.ui(13)).foregroundStyle(C.accentText).lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        Text(verbatim: roman(t.step.level)).font(.ui(13, .bold)).foregroundStyle(C.text)
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(verbatim: Fmt.duration(seconds: minutes * 60)).font(.mono(12)).foregroundStyle(C.text)
                            Text(verbatim: "\(short(t.step.primary))/\(short(t.step.secondary)) · Σ \(Fmt.duration(seconds: total * 60))")
                                .font(.mono(10)).foregroundStyle(C.muted)
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
            Text(attributes != nil
                 ? "Time uses the character's attributes and implants (Omega). The remap tries every legal split (17–27, 14 points on top)."
                 : "No character: time for a new character's attributes without implants, every skill from zero.")
                .font(.ui(11)).foregroundStyle(C.faint)
        }
    }

    private func attrLine(_ a: [Int: Int]) -> String {
        [167, 166, 168, 165, 164].map { "\(short($0)) \(a[$0] ?? 0)" }.joined(separator: " · ")
    }

    private func short(_ attr: Int) -> String {
        switch attr {
        case 164: String(localized: "Cha")
        case 165: String(localized: "Int")
        case 166: String(localized: "Mem")
        case 167: String(localized: "Per")
        case 168: String(localized: "Wil")
        default: "?"
        }
    }

    private func roman(_ n: Int) -> String { ["0", "I", "II", "III", "IV", "V"][min(5, max(0, n))] }

    /// Large injectors to cover the plan, as each one gives less once the character's SP grows.
    private func injectorsNeeded(sp: Int) -> Int {
        var left = sp, total = totalSP, n = 0
        while left > 0, n < 10_000 {
            let got = injectorSP(totalSP: total)
            left -= got
            total += got
            n += 1
        }
        return n
    }

    /// "Skill Level" lines in English, as the game's skill plan import reads them.
    private func copyPlan(_ todo: [TodoStep]) async {
        let english = (try? await env.repository?.englishNames(ids: Set(todo.map(\.step.skill)))) ?? [:]
        UIPasteboard.general.string = todo.map { "\(english[$0.step.skill] ?? "\($0.step.skill)") \($0.step.level)" }.joined(separator: "\n")
        copied = true
        try? await Task.sleep(for: .seconds(2))
        copied = false
    }

    // MARK: Loading

    private func loadPilot() async {
        let s = characterService
        if let skills = try? await s.skills() {
            pilotSkills = Dictionary(skills.skills.map { ($0.skillId, ($0.activeSkillLevel, $0.skillpointsInSkill)) }, uniquingKeysWith: { a, _ in a })
            totalSP = skills.totalSp
        }
        attributes = await PilotAttributes.load(service: s, repository: env.repository)
        gameFits = ((try? await s.fittings()) ?? []).sorted { $0.name < $1.name }
        if let repo = env.repository {
            let ids = Set(gameFits.map(\.shipTypeId) + [FitDraftStore.shared.draft?.shipTypeId ?? 0] + goals.map(\.typeId))
            names.merge(((try? await repo.types(ids: ids)) ?? [:]).mapValues(\.name)) { _, new in new }
        }
        injectorPrice = (try? await HubPrices.jitaSell(typeIds: [largeInjector]))?[largeInjector]
    }

    private func loadPlan() async {
        guard let repo = env.repository else { return }
        guard !goals.isEmpty else { steps = []; return }
        let plan = (try? await repo.skillPlan(goals: goals.map { ($0.typeId, $0.level) })) ?? []
        let ids = Set(plan.map(\.skill) + goals.map(\.typeId)).filter { names[$0] == nil }
        if !ids.isEmpty { names.merge(((try? await repo.types(ids: ids)) ?? [:]).mapValues(\.name)) { _, new in new } }
        steps = plan
    }
}
