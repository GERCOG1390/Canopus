// Industry as the desktop's IndustryPage.tsx: the manufacturing calculator (materials at Jita, the job
// cost from the system's cost index, profit per run and per hour, the skills the job needs) and the
// pilot's running jobs. Planetary industry, structures and moons come with the new SSO permissions.

import SwiftUI
import Domain
import EVEAuth
import EVEStaticData

enum IndustryPageTab: String, CaseIterable {
    case calc, jobs

    var label: String {
        switch self {
        case .calc: "Manufacturing calculator"
        case .jobs: "My jobs"
        }
    }
}

struct IndustryPage: View {
    @State var tab: IndustryPageTab

    init(tab: IndustryPageTab = {
        #if DEBUG
        if let t = UserDefaults.standard.string(forKey: "industryTab").flatMap(IndustryPageTab.init(rawValue:)) { return t }
        #endif
        return .calc
    }()) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CanopusTabs(tabs: IndustryPageTab.allCases.map { (id: $0, label: $0.label) }, selection: $tab)
                .padding(.horizontal, 12).padding(.vertical, 8)
            switch tab {
            case .calc: ScrollView { ManufacturingCalculator().padding(16) }
            case .jobs: ScrollView { IndustryJobs().padding(16) }
            }
        }
        .background(C.bg)
        .navigationTitle("Industry")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Manufacturing calculator

/// SCC surcharge added to every industry job.
private let sccSurcharge = 0.04

/// ESI's adjusted prices (~15 000 types) and every system's cost indices: large, and they change about
/// once an hour, so one download serves every calculator until then.
private enum IndustryMarketCache {
    static var adjusted: (at: Date, map: [Int: Double])?
    static var indices: (at: Date, map: [Int: [String: Double]])?
    static let ttl: TimeInterval = 3600

    static func fresh<T>(_ entry: (at: Date, map: T)?) -> T? {
        guard let entry, Date().timeIntervalSince(entry.at) < ttl else { return nil }
        return entry.map
    }
}

private struct ManufacturingCalculator: View {
    @Environment(AppEnvironment.self) private var env
    @State private var product: ItemType?
    @State private var query = ""
    @State private var hits: [ItemType] = []
    @State private var runs = 1.0
    @State private var me = 10.0
    @State private var te = 20.0
    @State private var structureBonus = 1.0
    @State private var facilityTax = 0.25
    @State private var salesTax = 3.37
    @State private var buyBasis = false
    @State private var system: (id: Int, name: String) = (30000142, "Jita")
    @State private var systemQuery = ""
    @State private var systemHits: [(id: Int, name: String, security: Double)] = []

    @State private var job: BlueprintJob?
    @State private var noBlueprint = false
    @State private var prices: [Int: HubPrice] = [:]
    @State private var adjusted: [Int: Double] = [:]
    @State private var indices: [Int: [String: Double]] = [:]
    @State private var systemSec: Double?
    @State private var names: [Int: String] = [:]
    @State private var pilotSkills: [Int: Int]?
    @State private var loadingMarket = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            form
            if noBlueprint {
                Text("This item has no blueprint or reaction formula.").font(.ui(13)).foregroundStyle(C.bad)
            } else if let job, !loadingMarket, !prices.isEmpty || !adjusted.isEmpty {
                result(job)
            } else if product != nil {
                ProgressView().tint(C.accent).frame(maxWidth: .infinity).padding(.top, 20)
            } else {
                Text("Pick the item you want to build (search in Russian or English).").font(.ui(13)).foregroundStyle(C.muted)
            }
        }
        .task(id: product?.id) { await loadBlueprint() }
        #if DEBUG
        // Debug builds: `-industryProduct 587` picks an item (screenshots).
        .task(id: env.repositoryVersion) {
            let id = UserDefaults.standard.integer(forKey: "industryProduct")
            if id > 0, product == nil, let t = try? await env.repository?.types(ids: [id])[id] { product = t; query = t.name }
        }
        #endif
        .task(id: "\(job?.blueprintId ?? 0)/\(system.id)") { await loadMarket() }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2, q != product?.name, let repo = env.repository else { hits = []; return }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            hits = Array(((try? await repo.search(q)) ?? []).prefix(8))
        }
        .task(id: systemQuery) {
            guard systemQuery != system.name, let repo = env.repository else { systemHits = []; return }
            systemHits = (try? await repo.systems(matching: systemQuery, limit: 6)) ?? []
        }
    }

    // MARK: Form

    private var form: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text("Product").font(.ui(11)).foregroundStyle(C.muted)
                field("e.g. Rifter, Hobgoblin II, Fernite Carbide", text: $query)
                ForEach(hits) { t in
                    Button {
                        product = t
                        query = t.name
                        hits = []
                    } label: { MarketTypeRow(type: t) }
                    .buttonStyle(.plain)
                }
            }
            let reaction = job?.isReaction == true
            FlowRow(spacing: 10) {
                NumberField(label: "Runs", value: $runs)
                NumberField(label: "ME", value: $me).disabled(reaction).opacity(reaction ? 0.4 : 1)
                NumberField(label: "TE", value: $te).disabled(reaction).opacity(reaction ? 0.4 : 1)
                NumberField(label: "Structure bonus, %", value: $structureBonus)
                NumberField(label: "Facility tax, %", value: $facilityTax)
                NumberField(label: "Sales tax, %", value: $salesTax)
            }
            HStack(spacing: 6) {
                Text("Material prices").font(.ui(11)).foregroundStyle(C.muted)
                Button("Jita sell") { buyBasis = false }.buttonStyle(CanopusButtonStyle(kind: buyBasis ? .ghost : .primary, small: true))
                Button("Jita buy") { buyBasis = true }.buttonStyle(CanopusButtonStyle(kind: buyBasis ? .primary : .ghost, small: true))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Manufacturing system").font(.ui(11)).foregroundStyle(C.muted)
                field("System…", text: $systemQuery)
                ForEach(systemHits, id: \.id) { s in
                    Button {
                        system = (s.id, s.name)
                        systemQuery = s.name
                        systemHits = []
                    } label: {
                        HStack(spacing: 6) {
                            Text(verbatim: String(format: "%.1f", s.security)).font(.mono(12)).foregroundStyle(C.sec(s.security))
                            Text(verbatim: s.name).font(.ui(13)).foregroundStyle(C.text)
                            Spacer()
                        }
                        .frame(minHeight: 30).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear { if systemQuery.isEmpty { systemQuery = system.name } }
    }

    private func field(_ prompt: LocalizedStringKey, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .font(.ui(14)).autocorrectionDisabled().textInputAutocapitalization(.never)
            .padding(.horizontal, 10).frame(minHeight: 38)
            .background(C.panel2, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(C.border))
    }

    // MARK: Result

    @ViewBuilder private func result(_ job: BlueprintJob) -> some View {
        let runs = max(1, Int(self.runs))
        let me = job.isReaction ? 0 : min(10, max(0, self.me))
        let te = job.isReaction ? 0 : min(20, max(0, self.te))
        let price = { (id: Int) in (buyBasis ? prices[id]?.buy : prices[id]?.sell) ?? 0 }
        let rows = job.materials.map { m -> (id: Int, qty: Int, unit: Double, total: Double) in
            let raw = Double(m.quantity * runs) * (1 - me / 100) * (1 - structureBonus / 100)
            // As the game (and the desktop): round to cents first, then up; never below one per run.
            let qty = max(runs, Int(((raw * 100).rounded() / 100).rounded(.up)))
            return (m.typeId, qty, price(m.typeId), Double(qty) * price(m.typeId))
        }
        let materialCost = rows.reduce(0) { $0 + $1.total }
        let eiv = job.materials.reduce(0) { $0 + Double($1.quantity) * (adjusted[$1.typeId] ?? 0) } * Double(runs)
        let costIndex = indices[system.id]?[job.isReaction ? "reaction" : "manufacturing"] ?? 0
        let jobCost = eiv * (costIndex + facilityTax / 100 + sccSurcharge)
        let outputQty = job.productQuantity * runs
        let revenue = Double(outputQty) * (prices[job.productId]?.sell ?? 0)
        let tax = revenue * salesTax / 100
        let totalCost = materialCost + jobCost
        let profit = revenue - tax - totalCost
        let time = Double(job.time * runs) * (1 - te / 100)

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            StatTile(label: "Production cost", value: Fmt.isk(totalCost), sub: String(localized: "per unit \(Fmt.isk(totalCost / Double(max(1, outputQty))))"))
            StatTile(label: String(localized: "Sale of \(outputQty.formatted()) (Jita sell)"), value: Fmt.isk(revenue), sub: String(localized: "tax \(Fmt.isk(tax))"))
            StatTile(label: "Profit", value: Fmt.isk(profit),
                     sub: totalCost > 0 ? String(localized: "margin \(String(format: "%.1f", profit / totalCost * 100))%") : nil,
                     valueColor: profit >= 0 ? C.good : C.bad)
            StatTile(label: "Time", value: Fmt.duration(seconds: time), sub: String(localized: "\(Fmt.isk(profit / max(1, time / 3600))) per hour"))
        }
        Card(buyBasis ? String(localized: "Materials (through buy orders)") : String(localized: "Materials (bought at sell)")) {
            ForEach(rows, id: \.id) { r in
                HStack(spacing: 6) {
                    EVETypeIcon(typeId: r.id, size: 22)
                    NavigationLink { TypeDetailView(typeId: r.id, typeName: names[r.id] ?? "") } label: {
                        Text(verbatim: names[r.id] ?? "#\(r.id)").font(.ui(13)).foregroundStyle(C.accentText).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(verbatim: Fmt.isk(r.total)).font(.mono(12, medium: true)).foregroundStyle(C.text)
                        Text(verbatim: "×\(r.qty.formatted()) · \(Fmt.isk(r.unit, compact: false))").font(.mono(10)).foregroundStyle(C.muted)
                    }
                }
            }
            HStack {
                Text("Materials").font(.ui(13, .semibold)).foregroundStyle(C.text)
                Spacer()
                Text(verbatim: Fmt.isk(materialCost)).font(.mono(12, medium: true)).foregroundStyle(C.text)
            }
            .padding(.top, 4)
        }
        Card(String(localized: "Job cost")) {
            kv(String(localized: "System"), systemSec.map { String(format: "%.1f ", $0) + system.name } ?? system.name)
            kv("Estimated Item Value", Fmt.isk(eiv))
            kv(job.isReaction ? String(localized: "Cost index (reactions)") : String(localized: "Cost index (manufacturing)"), String(format: "%.2f%%", costIndex * 100))
            kv(String(localized: "Facility tax"), String(format: "%g%%", facilityTax))
            kv(String(localized: "SCC surcharge"), String(format: "%g%%", sccSurcharge * 100))
            kv(String(localized: "Installation cost"), Fmt.isk(jobCost), bold: true)
            Text("Blueprint: \(names[job.blueprintId] ?? "#\(job.blueprintId)") · \(job.productQuantity) per run · max runs on a copy: \(job.maxRuns). Data: CCP SDE.")
                .font(.ui(11)).foregroundStyle(C.faint)
        }
        if !job.skills.isEmpty {
            Card(String(localized: "Skills to start the job")) {
                ForEach(job.skills, id: \.typeId) { s in
                    let have = pilotSkills?[s.typeId] ?? 0
                    HStack(spacing: 6) {
                        Text(verbatim: pilotSkills == nil ? "·" : have >= s.level ? "✓" : "✗")
                            .font(.ui(13, .bold)).foregroundStyle(pilotSkills == nil ? C.muted : have >= s.level ? C.good : C.bad).frame(width: 14)
                        NavigationLink { TypeDetailView(typeId: s.typeId, typeName: names[s.typeId] ?? "") } label: {
                            Text(verbatim: names[s.typeId] ?? "#\(s.typeId)").font(.ui(13)).foregroundStyle(C.accentText)
                        }
                        .buttonStyle(.plain)
                        Text(verbatim: ["0", "I", "II", "III", "IV", "V"][min(5, s.level)]).font(.ui(13, .bold)).foregroundStyle(C.text)
                        Spacer()
                        if pilotSkills != nil, have < s.level {
                            Text("you have \(have)").font(.ui(11)).foregroundStyle(C.bad)
                        }
                    }
                }
            }
        }
    }

    private func kv(_ k: String, _ v: String, bold: Bool = false) -> some View {
        HStack {
            Text(verbatim: k).font(.ui(13, bold ? .semibold : .regular)).foregroundStyle(C.text)
            Spacer()
            Text(verbatim: v).font(.mono(12, medium: bold)).foregroundStyle(C.text)
        }
    }

    // MARK: Loading

    private func loadBlueprint() async {
        guard let product, let repo = env.repository else { job = nil; return }
        noBlueprint = false
        let found = try? await repo.blueprintJob(for: product.id)
        job = found
        noBlueprint = found == nil
        guard let found else { return }
        let ids = Set([found.blueprintId, found.productId] + found.materials.map(\.typeId) + found.skills.map(\.typeId))
        names = ((try? await repo.types(ids: ids)) ?? [:]).mapValues(\.name)
        if let svc = env.characterStore.selectedService, let skills = try? await svc.skills() {
            pilotSkills = Dictionary(skills.skills.map { ($0.skillId, $0.activeSkillLevel) }, uniquingKeysWith: { a, _ in a })
        }
    }

    private func loadMarket() async {
        guard let job else { return }
        loadingMarket = true
        defer { loadingMarket = false }
        let market = MarketService()
        let cachedAdjusted = IndustryMarketCache.fresh(IndustryMarketCache.adjusted)
        let cachedIndices = IndustryMarketCache.fresh(IndustryMarketCache.indices)
        async let p = try? HubPrices.hub(station: HubPrices.jitaStation, typeIds: Set([job.productId] + job.materials.map(\.typeId)))
        async let adj = cachedAdjusted == nil ? (try? await market.marketPrices()) : nil
        async let idx = cachedIndices == nil ? (try? await market.industrySystems()) : nil
        prices = await p ?? [:]
        if let list = await adj {
            let map = Dictionary(list.map { ($0.typeId, $0.adjustedPrice ?? 0) }, uniquingKeysWith: { a, _ in a })
            IndustryMarketCache.adjusted = (Date(), map)
        }
        if let list = await idx {
            let map = Dictionary(list.map { s in (s.solarSystemId, Dictionary(s.costIndices.map { ($0.activity, $0.costIndex) }, uniquingKeysWith: { a, _ in a })) },
                                 uniquingKeysWith: { a, _ in a })
            IndustryMarketCache.indices = (Date(), map)
        }
        adjusted = IndustryMarketCache.adjusted?.map ?? [:]
        indices = IndustryMarketCache.indices?.map ?? [:]
        systemSec = try? await env.repository?.systems(ids: [system.id])[system.id]?.security
    }
}

// MARK: - Industry jobs

private func activityLabel(_ id: Int) -> String {
    switch id {
    case 1: String(localized: "Manufacturing")
    case 3: String(localized: "TE research")
    case 4: String(localized: "ME research")
    case 5: String(localized: "Copying")
    case 8: String(localized: "Invention")
    case 9, 11: String(localized: "Reaction")
    default: "\(id)"
    }
}

private struct IndustryJobs: View {
    @Environment(AppEnvironment.self) private var env
    @State private var jobs: [ESIIndustryJob]?
    @State private var names: [Int: String] = [:]
    @State private var error: Error?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if env.characterStore.selectedService == nil {
                Text("Sign in with a character to see the jobs.").font(.ui(13)).foregroundStyle(C.muted)
            } else if error != nil {
                ScopeHint(scope: "esi-industry.read_character_jobs.v1")
            } else if let jobs {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Card(title: String(localized: "Active jobs: \(jobs.count)"), actions: {
                        Button("Refresh") { Task { await load() } }.buttonStyle(.canopusSmall)
                    }) {
                        if jobs.isEmpty { Text("No active jobs.").font(.ui(13)).foregroundStyle(C.muted) }
                        ForEach(jobs) { j in row(j, now: ctx.date) }
                    }
                }
            } else {
                ProgressView().tint(C.accent).frame(maxWidth: .infinity).padding(.top, 30)
            }
        }
        .task(id: env.dataKey) { await load() }
    }

    private func row(_ j: ESIIndustryJob, now: Date) -> some View {
        let total = j.endDate.timeIntervalSince(j.startDate)
        let left = j.endDate.timeIntervalSince(now)
        let progress = total > 0 ? min(1, max(0, now.timeIntervalSince(j.startDate) / total)) : 1
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                EVETypeIcon(typeId: j.blueprintTypeId, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: names[j.blueprintTypeId] ?? "#\(j.blueprintTypeId)").font(.ui(13)).foregroundStyle(C.text).lineLimit(1)
                    if let p = j.productTypeId, p != j.blueprintTypeId {
                        Text(verbatim: "→ " + (names[p] ?? "#\(p)")).font(.ui(11)).foregroundStyle(C.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(verbatim: activityLabel(j.activityId)).font(.ui(11)).foregroundStyle(C.muted)
                    Text(verbatim: "×\(j.runs)").font(.mono(11)).foregroundStyle(C.muted)
                }
            }
            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(C.panel2)
                        Capsule().fill(left <= 0 ? C.good : C.accent).frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 6)
                Text(verbatim: left <= 0 ? String(localized: "Done — deliver it!") : Fmt.duration(seconds: left))
                    .font(.mono(11)).foregroundStyle(left <= 0 ? C.good : C.text).frame(minWidth: 90, alignment: .trailing)
            }
        }
        .padding(.vertical, 5)
    }

    private func load() async {
        guard let svc = env.characterStore.selectedService else { return }
        do {
            let list = try await svc.industryJobs().filter { $0.status == "active" || $0.status == "ready" || $0.status == "paused" }
                .sorted { $0.endDate < $1.endDate }
            names = ((try? await env.repository?.types(ids: Set(list.flatMap { [$0.blueprintTypeId, $0.productTypeId ?? 0] }))) ?? [:]).mapValues(\.name)
            jobs = list
            error = nil
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }
}
