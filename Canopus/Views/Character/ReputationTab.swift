// Reputation as the desktop's character/Reputation.tsx: jump fatigue, loyalty points by corporation and
// standings with factions, NPC corporations and agents.

import SwiftUI
import Domain
import EVEAuth

struct ReputationTab: View {
    let characterService: CharacterService
    @Environment(AppEnvironment.self) private var env
    @State private var standings: [ESIStanding]??
    @State private var loyalty: [ESILoyaltyPoint]??
    @State private var fatigue: ESIJumpFatigue?
    @State private var names: [Int: String] = [:]
    @State private var openGroups: Set<String> = ["faction", "npc_corp"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let loyalty, let standings { content(loyalty, standings) } else {
                    ProgressView().tint(C.accent).frame(maxWidth: .infinity).padding(.top, 30)
                }
            }
            .padding(16)
        }
        .refreshable { await load() }
        .task(id: env.dataKey) { await load() }
    }

    @ViewBuilder private func content(_ loyalty: [ESILoyaltyPoint]?, _ standings: [ESIStanding]?) -> some View {
        let left = fatigue?.jumpFatigueExpireDate.map { $0.timeIntervalSinceNow } ?? 0
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            StatTile(label: "Jump fatigue",
                     value: fatigue == nil ? "—" : left > 0 ? Fmt.duration(seconds: left) : String(localized: "none"),
                     sub: fatigue?.lastJumpDate.map { String(localized: "last jump: \($0.formatted(date: .abbreviated, time: .shortened))") })
            StatTile(label: "Corporations with LP", value: loyalty.map { "\($0.count)" } ?? "—",
                     sub: loyalty.map { String(localized: "\($0.reduce(0) { $0 + $1.loyaltyPoints }.formatted()) LP in total") })
        }
        Card(String(localized: "Loyalty points (LP)")) {
            if let loyalty {
                if loyalty.isEmpty { Text("No LP").font(.ui(13)).foregroundStyle(C.muted) }
                ForEach(loyalty.sorted { $0.loyaltyPoints > $1.loyaltyPoints }) { l in
                    HStack(spacing: 8) {
                        EVECorpLogo(corpId: l.corporationId, size: 20)
                        Text(verbatim: names[l.corporationId] ?? "#\(l.corporationId)").font(.ui(13)).foregroundStyle(C.text).lineLimit(1)
                        Spacer()
                        Text(verbatim: "\(l.loyaltyPoints.formatted()) LP").font(.mono(12, medium: true)).foregroundStyle(C.text)
                    }
                }
            } else {
                ScopeHint(scope: "esi-characters.read_loyalty.v1")
            }
        }
        Card(String(localized: "Standings")) {
            if let standings {
                ForEach([("faction", String(localized: "Factions")), ("npc_corp", String(localized: "NPC corporations")), ("agent", String(localized: "Agents"))], id: \.0) { type, label in
                    let list = standings.filter { $0.fromType == type }.sorted { $0.standing > $1.standing }
                    if !list.isEmpty {
                        let isOpen = openGroups.contains(type)
                        Button {
                            if isOpen { openGroups.remove(type) } else { openGroups.insert(type) }
                        } label: {
                            HStack(spacing: 6) {
                                Text(verbatim: isOpen ? "▾" : "▸").font(.ui(11)).foregroundStyle(C.muted)
                                Text(verbatim: label).font(.ui(13, .semibold)).foregroundStyle(C.text)
                                Text(verbatim: "(\(list.count))").font(.ui(12)).foregroundStyle(C.muted)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if isOpen {
                            ForEach(list, id: \.fromId) { s in
                                HStack {
                                    Text(verbatim: names[s.fromId] ?? "#\(s.fromId)").font(.ui(13)).foregroundStyle(C.text).lineLimit(1)
                                    Spacer()
                                    Text(verbatim: String(format: "%.2f", s.standing)).font(.mono(12, medium: true))
                                        .foregroundStyle(s.standing > 0 ? C.good : s.standing < 0 ? C.bad : C.muted)
                                }
                                .padding(.leading, 18)
                            }
                        }
                    }
                }
            } else {
                ScopeHint(scope: "esi-characters.read_standings.v1")
            }
        }
    }

    private func load() async {
        let s = characterService
        async let st = try? s.standings()
        async let lp = try? s.loyaltyPoints()
        async let f = try? s.fatigue()
        let (standingsList, loyaltyList) = (await st, await lp)
        fatigue = await f
        let ids = (standingsList ?? []).map(\.fromId) + (loyaltyList ?? []).map(\.corporationId)
        if let resolved = try? await MarketService().names(ids: ids) { names = resolved }
        standings = .some(standingsList)
        loyalty = .some(loyaltyList)
    }
}
