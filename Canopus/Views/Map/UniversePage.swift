// The universe from public ESI: incursions under way, factional warfare (each faction's totals and the
// systems closest to flipping), sovereignty timers and ship insurance. Names of places come from the
// local SDE; factions and alliances from ESI.

import SwiftUI
import Domain
import EVEAuth
import EVEStaticData

enum UniverseTab: String, CaseIterable {
    case incursions, fw, sov, insurance

    var label: String {
        switch self {
        case .incursions: "Incursions"
        case .fw: "Factional warfare"
        case .sov: "Sovereignty timers"
        case .insurance: "Insurance"
        }
    }
}

struct UniversePage: View {
    @State private var tab: UniverseTab = {
        #if DEBUG
        if let t = UserDefaults.standard.string(forKey: "universeTab").flatMap(UniverseTab.init(rawValue:)) { return t }
        #endif
        return .incursions
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CanopusTabs(tabs: UniverseTab.allCases.map { (id: $0, label: $0.label) }, selection: $tab)
                .padding(.horizontal, 12).padding(.vertical, 8)
            ScrollView {
                Group {
                    switch tab {
                    case .incursions: IncursionsView()
                    case .fw: FactionWarView()
                    case .sov: SovCampaignsView()
                    case .insurance: InsuranceView()
                    }
                }
                .padding(16)
            }
        }
        .background(C.bg)
        .navigationTitle("Universe")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Shared bits

/// A thin bar for a 0…1 share (influence, victory points).
private struct ShareBar: View {
    let value: Double
    var color: Color = C.accent

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(C.panel2)
                Capsule().fill(color).frame(width: g.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: 5)
    }
}

private struct PlaceLine: View {
    let place: SystemPlace?
    var body: some View {
        HStack(spacing: 6) {
            if let place {
                SecText(value: place.security)
                Text(verbatim: place.name).font(.ui(14, .semibold)).foregroundStyle(C.text)
                Text(verbatim: "\(place.constellation) · \(place.region)").font(.ui(11)).foregroundStyle(C.muted).lineLimit(1)
            } else {
                Text(verbatim: "…").foregroundStyle(C.muted)
            }
        }
    }
}

private struct LoadState: View {
    let error: String?
    var body: some View {
        if let error { Text(error).font(.ui(13)).foregroundStyle(C.bad) } else { ProgressView().tint(C.accent).frame(maxWidth: .infinity).padding(.top, 20) }
    }
}

/// ESI names, one request per kind so one unknown id doesn't sink the rest.
@MainActor private func esiNames(_ ids: [Int]) async -> [Int: String] {
    (try? await MarketService().names(ids: ids)) ?? [:]
}

// MARK: - Incursions

private struct IncursionsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var list: [ESIIncursion]?
    @State private var places: [Int: SystemPlace] = [:]
    @State private var factions: [Int: String] = [:]
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let list {
                if list.isEmpty { Card { Text("No incursions right now.").font(.ui(13)).foregroundStyle(C.muted) } }
                ForEach(list, id: \.constellationId) { row($0) }
                Text("Influence: how strong the incursion's hold is — at 100% the constellation's systems get the full penalties. The staging system is where fleets form up.")
                    .font(.ui(11)).foregroundStyle(C.faint)
            } else {
                LoadState(error: error)
            }
        }
        .task(id: env.repositoryVersion) { await load() }
    }

    private func row(_ i: ESIIncursion) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    EVECorpLogo(corpId: i.factionId, size: 28)
                    PlaceLine(place: places[i.stagingSolarSystemId])
                    Spacer(minLength: 4)
                    Pill(text: stateLabel(i.state), color: stateColor(i.state))
                }
                HStack(spacing: 10) {
                    Text(verbatim: factions[i.factionId] ?? "")
                    Text("\(i.infestedSolarSystems.count) systems")
                    if i.hasBoss { Pill(text: "Mothership", color: C.bad) }
                    Spacer(minLength: 4)
                    Text(verbatim: "\(Int((i.influence * 100).rounded()))%").font(.mono(12, medium: true)).foregroundStyle(C.text)
                }
                .font(.ui(12)).foregroundStyle(C.muted)
                ShareBar(value: i.influence, color: C.bad)
                Text(verbatim: i.infestedSolarSystems.compactMap { places[$0]?.name }.sorted().joined(separator: ", "))
                    .font(.ui(11)).foregroundStyle(C.faint)
            }
        }
    }

    private func stateLabel(_ s: String) -> String {
        switch s {
        case "established": "Established"
        case "mobilizing": "Mobilizing"
        case "withdrawing": "Withdrawing"
        default: s
        }
    }

    private func stateColor(_ s: String) -> Color {
        switch s {
        case "established": C.accent
        case "mobilizing": C.warn
        default: C.muted
        }
    }

    private func load() async {
        do {
            let all = try await MarketService().incursions().sorted { $0.influence > $1.influence }
            if let repo = env.repository {
                places = (try? await repo.systemPlaces(ids: Set(all.flatMap { $0.infestedSolarSystems + [$0.stagingSolarSystemId] }))) ?? [:]
            }
            factions = await esiNames(Array(Set(all.map(\.factionId))))
            list = all
            error = nil
        } catch {
            if !error.isCancellation { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Factional warfare

private struct FactionWarView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var stats: [ESIFactionWarStats]?
    @State private var systems: [ESIFactionWarSystem] = []
    @State private var places: [Int: SystemPlace] = [:]
    @State private var factions: [Int: String] = [:]
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let stats {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                    ForEach(stats, id: \.factionId) { faction($0) }
                }
                contested
            } else {
                LoadState(error: error)
            }
        }
        .task(id: env.repositoryVersion) { await load() }
    }

    private func faction(_ f: ESIFactionWarStats) -> some View {
        Card {
            HStack(spacing: 10) {
                EVECorpLogo(corpId: f.factionId, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: factions[f.factionId] ?? "").font(.ui(14, .semibold)).foregroundStyle(C.text)
                    Text("\(f.pilots.formatted()) pilots · \(f.systemsControlled) systems").font(.ui(11)).foregroundStyle(C.muted)
                }
                Spacer(minLength: 0)
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                GridRow {
                    Text(verbatim: "")
                    Text("Yesterday").foregroundStyle(C.muted)
                    Text("Last week").foregroundStyle(C.muted)
                }
                GridRow {
                    Text("Kills").foregroundStyle(C.muted)
                    Text(verbatim: f.kills.yesterday.formatted())
                    Text(verbatim: f.kills.lastWeek.formatted())
                }
                GridRow {
                    Text("Victory points").foregroundStyle(C.muted)
                    Text(verbatim: f.victoryPoints.yesterday.formatted())
                    Text(verbatim: f.victoryPoints.lastWeek.formatted())
                }
            }
            .font(.mono(12)).foregroundStyle(C.text)
        }
    }

    private var contested: some View {
        let close = systems.filter { $0.victoryPoints > 0 && $0.victoryPointsThreshold > 0 }
            .sorted { Double($0.victoryPoints) / Double($0.victoryPointsThreshold) > Double($1.victoryPoints) / Double($1.victoryPointsThreshold) }
            .prefix(30)
        return Card(String(localized: "Closest to flipping")) {
            if close.isEmpty { Text("No contested systems.").font(.ui(13)).foregroundStyle(C.muted) }
            ForEach(Array(close), id: \.solarSystemId) { s in
                let share = Double(s.victoryPoints) / Double(s.victoryPointsThreshold)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        PlaceLine(place: places[s.solarSystemId])
                        Spacer(minLength: 4)
                        Text(verbatim: "\(Int((share * 100).rounded()))%").font(.mono(12, medium: true)).foregroundStyle(share >= 0.9 ? C.bad : C.text)
                    }
                    HStack(spacing: 6) {
                        EVECorpLogo(corpId: s.occupierFactionId, size: 16)
                        Text(verbatim: factions[s.occupierFactionId] ?? "")
                        Spacer(minLength: 4)
                        Text(verbatim: "\(s.victoryPoints.formatted()) / \(s.victoryPointsThreshold.formatted())")
                    }
                    .font(.ui(11)).foregroundStyle(C.muted)
                    ShareBar(value: share, color: share >= 0.9 ? C.bad : C.warn)
                }
                .padding(.vertical, 3)
            }
        }
    }

    private func load() async {
        do {
            let market = MarketService()
            async let s = market.factionWarStats()
            async let sys = market.factionWarSystems()
            let all = try await s.sorted { $0.factionId < $1.factionId }
            systems = (try? await sys) ?? []
            if let repo = env.repository { places = (try? await repo.systemPlaces(ids: Set(systems.map(\.solarSystemId)))) ?? [:] }
            factions = await esiNames(Array(Set(all.map(\.factionId) + systems.map(\.occupierFactionId))))
            stats = all
            error = nil
        } catch {
            if !error.isCancellation { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Sovereignty timers

private struct SovCampaignsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var list: [ESISovereigntyCampaign]?
    @State private var places: [Int: SystemPlace] = [:]
    @State private var defenders: [Int: String] = [:]
    @State private var region = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let list {
                let regions = Array(Set(list.compactMap { places[$0.solarSystemId]?.region })).sorted()
                Card {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Button("All regions") { region = "" }.buttonStyle(CanopusButtonStyle(kind: region.isEmpty ? .primary : .ghost, small: true))
                            ForEach(regions, id: \.self) { r in
                                Button(r) { region = r }.buttonStyle(CanopusButtonStyle(kind: region == r ? .primary : .ghost, small: true))
                            }
                        }
                    }
                    Text("Defense events for sovereignty structures: the attacker needs the score to reach 100% before the defender does.")
                        .font(.ui(11)).foregroundStyle(C.faint)
                }
                let shown = list.filter { region.isEmpty || places[$0.solarSystemId]?.region == region }
                Card {
                    if shown.isEmpty { Text("No sovereignty timers.").font(.ui(13)).foregroundStyle(C.muted) }
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, c in row(c) }
                }
            } else {
                LoadState(error: error)
            }
        }
        .task(id: env.repositoryVersion) { await load() }
    }

    private func row(_ c: ESISovereigntyCampaign) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                PlaceLine(place: places[c.solarSystemId])
                Spacer(minLength: 4)
                Pill(text: eventLabel(c.eventType), color: C.accent)
            }
            HStack(spacing: 6) {
                if let d = c.defenderId {
                    EVEAllianceLogo(allianceId: d, size: 16)
                    Text(verbatim: defenders[d] ?? "")
                }
                Spacer(minLength: 4)
                if c.startTime > .now {
                    Text("in \(Fmt.duration(until: c.startTime))").foregroundStyle(C.text)
                } else {
                    Text("Under way").foregroundStyle(C.bad)
                    if let a = c.attackersScore, let d = c.defenderScore {
                        Text(verbatim: "\(Int((a * 100).rounded()))% / \(Int((d * 100).rounded()))%").font(.mono(11))
                    }
                }
            }
            .font(.ui(11)).foregroundStyle(C.muted)
            Text(verbatim: c.startTime.formatted(date: .abbreviated, time: .shortened)).font(.mono(10)).foregroundStyle(C.faint)
        }
        .padding(.vertical, 3)
    }

    private func eventLabel(_ e: String) -> String {
        switch e {
        case "tcu_defense": "TCU"
        case "ihub_defense": String(localized: "Sovereignty Hub")
        case "station_defense": String(localized: "Station")
        case "station_freeport": String(localized: "Freeport")
        default: e
        }
    }

    private func load() async {
        do {
            let all = try await MarketService().sovereigntyCampaigns().sorted { $0.startTime < $1.startTime }
            if let repo = env.repository { places = (try? await repo.systemPlaces(ids: Set(all.map(\.solarSystemId)))) ?? [:] }
            defenders = await esiNames(Array(Set(all.compactMap(\.defenderId))))
            list = all
            error = nil
        } catch {
            if !error.isCancellation { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Insurance

private struct InsuranceView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var prices: [Int: [ESIInsurancePrice.Level]]?
    @State private var query = ""
    @State private var hits: [ItemType] = []
    @State private var ship: ItemType?
    @State private var hull: Double?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ship").font(.ui(11)).foregroundStyle(C.muted)
                    TextField("e.g. Raven, Catalyst, Vexor Navy Issue", text: $query)
                        .font(.ui(14)).autocorrectionDisabled().textInputAutocapitalization(.never)
                        .padding(.horizontal, 10).frame(minHeight: 38)
                        .background(C.panel2, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(C.border))
                    ForEach(hits) { t in
                        Button {
                            ship = t
                            query = t.name
                            hits = []
                        } label: { MarketTypeRow(type: t) }
                        .buttonStyle(.plain)
                    }
                }
                Text("Insurance pays out when the ship is destroyed; a policy lasts 12 weeks. Loss is what losing the ship costs you with that policy: the hull at Jita sell plus the policy, minus the payout.")
                    .font(.ui(11)).foregroundStyle(C.faint)
            }
            if let ship, let levels = prices?[ship.id] {
                Card(ship.name) {
                    if let hull {
                        Text("Hull at Jita sell: \(Fmt.isk(hull))").font(.ui(12)).foregroundStyle(C.muted)
                    }
                    Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
                        GridRow {
                            Text("Level").gridColumnAlignment(.leading)
                            Text("Cost")
                            Text("Payout")
                            Text("Loss if destroyed")
                        }
                        .font(.ui(11)).foregroundStyle(C.muted)
                        ForEach(levels, id: \.name) { l in
                            GridRow {
                                Text(LocalizedStringKey(l.name)).font(.ui(13)).foregroundStyle(C.text)
                                Text(verbatim: Fmt.isk(l.cost))
                                Text(verbatim: Fmt.isk(l.payout))
                                if let hull {
                                    let loss = hull + l.cost - l.payout
                                    Text(verbatim: Fmt.isk(loss)).foregroundStyle(loss <= 0 ? C.accentText : C.bad)
                                } else {
                                    Text(verbatim: "—")
                                }
                            }
                            .font(.mono(12)).foregroundStyle(C.text)
                        }
                    }
                }
            } else if ship != nil, prices != nil {
                Text("This ship can't be insured.").font(.ui(13)).foregroundStyle(C.muted)
            } else if prices == nil {
                LoadState(error: error)
            }
        }
        .task { await load() }
        .task(id: ship?.id) {
            hull = nil
            guard let id = ship?.id else { return }
            hull = try? await HubPrices.jitaSell(typeIds: [id])[id]
        }
        #if DEBUG
        // Debug builds: `-insuranceShip 638` picks a ship (screenshots).
        .task(id: env.repositoryVersion) {
            let id = UserDefaults.standard.integer(forKey: "insuranceShip")
            if id > 0, ship == nil, let t = try? await env.repository?.types(ids: [id])[id] { ship = t; query = t.name }
        }
        #endif
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2, q != ship?.name, let repo = env.repository else { hits = []; return }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let insured = prices ?? [:]
            hits = Array(((try? await repo.search(q)) ?? []).filter { insured[$0.id] != nil }.prefix(8))
        }
    }

    private func load() async {
        guard prices == nil else { return }
        do {
            let all = try await MarketService().insurancePrices()
            prices = Dictionary(all.map { ($0.typeId, $0.levels) }, uniquingKeysWith: { a, _ in a })
            error = nil
        } catch {
            if !error.isCancellation { self.error = error.localizedDescription }
        }
    }
}
