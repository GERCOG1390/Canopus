// The corporation's structures and moon mining, as the desktop's Structures.tsx / Moons.tsx: state and
// timers, fuel left and services (Station Manager role), moon extractions (Station Manager) and who mined
// what from the moons in the last 30 days (Accountant), valued at Jita buy.

import SwiftUI
import Domain
import EVEAuth
import EVEStaticData

/// ESI refuses corporation data (403) when the character lacks the role in the game.
private func roleMessage(_ error: Error, role: String) -> String {
    if case AuthError.httpError(403, _) = error { return String(localized: "ESI refused: the character needs the \(role) role in the corporation.") }
    return error.localizedDescription
}

private func structureState(_ s: String) -> (label: String, color: Color) {
    switch s {
    case "shield_vulnerable", "online_deprecated": (String(localized: "Online"), C.good)
    case "armor_vulnerable": (String(localized: "Armor vulnerable"), C.warn)
    case "hull_vulnerable": (String(localized: "Hull vulnerable"), C.bad)
    case "armor_reinforce": (String(localized: "Reinforced (armor)"), C.bad)
    case "hull_reinforce": (String(localized: "Reinforced (hull)"), C.bad)
    case "anchoring": (String(localized: "Anchoring"), C.muted)
    case "onlining_vulnerable": (String(localized: "Onlining"), C.muted)
    case "deploy_vulnerable": (String(localized: "Deploying"), C.muted)
    case "fitting_invulnerable": (String(localized: "Invulnerable"), C.muted)
    case "unanchored": (String(localized: "Unanchored"), C.muted)
    default: (s, C.muted)
    }
}

// MARK: - Structures

struct CorpStructuresView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var list: [ESICorpStructure]?
    @State private var places: [Int: SystemPlace] = [:]
    @State private var error: Error?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if env.characterStore.selectedService == nil {
                Text("Sign in with a character to see the corporation's structures.").font(.ui(13)).foregroundStyle(C.muted)
            } else if let error {
                if case AuthError.httpError(403, _) = error {
                    Text(roleMessage(error, role: "Station Manager")).font(.ui(13)).foregroundStyle(C.warn)
                } else {
                    ScopeHint(scope: "esi-corporations.read_structures.v1")
                }
            } else if let list {
                TimelineView(.periodic(from: .now, by: 60)) { ctx in
                    Card(title: String(localized: "Corporation structures: \(list.count)"), actions: {
                        Button("Refresh") { Task { await load() } }.buttonStyle(.canopusSmall)
                    }) {
                        if list.isEmpty { Text("The corporation has no structures.").font(.ui(13)).foregroundStyle(C.muted) }
                        ForEach(list) { s in
                            row(s, now: ctx.date)
                            if s.id != list.last?.id { Divider().overlay(C.border) }
                        }
                    }
                }
            } else {
                ProgressView().tint(C.accent).frame(maxWidth: .infinity).padding(.top, 30)
            }
        }
        .task(id: env.dataKey) { await load() }
    }

    private func row(_ s: ESICorpStructure, now: Date) -> some View {
        let state = structureState(s.state)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                EVETypeIcon(typeId: s.typeId, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: s.name ?? "#\(s.structureId)").font(.ui(14, .semibold)).foregroundStyle(C.text).lineLimit(2)
                    HStack(spacing: 5) {
                        if let p = places[s.systemId] {
                            SecText(value: p.security)
                            Text(verbatim: "\(p.name) · \(p.region)").font(.ui(11)).foregroundStyle(C.muted).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(verbatim: state.label).font(.ui(12, .medium)).foregroundStyle(state.color)
                    if let t = s.stateTimerEnd, t > now {
                        Text("timer in \(Fmt.duration(seconds: t.timeIntervalSince(now)))").font(.ui(11)).foregroundStyle(C.muted)
                    }
                }
            }
            HStack(spacing: 6) {
                Text("Fuel").font(.ui(11)).foregroundStyle(C.muted)
                if let f = s.fuelExpires {
                    let left = f.timeIntervalSince(now)
                    Text(verbatim: Fmt.duration(seconds: left)).font(.mono(12, medium: true))
                        .foregroundStyle(left < 3 * 86_400 ? C.bad : left < 7 * 86_400 ? C.warn : C.text)
                } else {
                    Text("no fuel").font(.ui(12)).foregroundStyle(C.muted)
                }
            }
            if let services = s.services, !services.isEmpty {
                Text(verbatim: services.map { $0.state == "online" ? $0.name : "\($0.name) (\($0.state))" }.joined(separator: " · "))
                    .font(.ui(11)).foregroundStyle(services.contains { $0.state != "online" } ? C.warn : C.faint)
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        guard let svc = env.characterStore.selectedService else { return }
        do {
            var all: [ESICorpStructure]
            #if DEBUG
            // Debug builds: `-corpDemo YES` shows sample structures (screenshots without the role).
            if UserDefaults.standard.bool(forKey: "corpDemo") {
                let iso = { (h: Double) in ISO8601DateFormatter().string(from: Date().addingTimeInterval(h * 3600)) }
                let json = """
                [{"structure_id":1,"name":"Perimeter - Sample Fortizar","type_id":35833,"system_id":30000144,"state":"shield_vulnerable","fuel_expires":"\(iso(50))",
                  "services":[{"name":"Manufacturing (Standard)","state":"online"},{"name":"Clone Bay","state":"offline"}]},
                 {"structure_id":2,"name":"Jita - Sample Athanor","type_id":35835,"system_id":30000142,"state":"armor_reinforce","state_timer_end":"\(iso(20))","fuel_expires":"\(iso(400))",
                  "services":[{"name":"Moon Drilling","state":"online"}]},
                 {"structure_id":3,"name":"New Caldari - Sample Raitaru","type_id":35825,"system_id":30000145,"state":"shield_vulnerable"}]
                """
                all = try JSONDecoder.esi.decode([ESICorpStructure].self, from: Data(json.utf8))
            } else {
                all = try await svc.corporationStructures(corpId: try await svc.characterInfo().corporationId)
            }
            #else
            all = try await svc.corporationStructures(corpId: try await svc.characterInfo().corporationId)
            #endif
            places = (try? await env.repository?.systemPlaces(ids: Set(all.map(\.systemId)))) ?? [:]
            // Fuel running out first on top.
            list = all.sorted { ($0.fuelExpires ?? .distantFuture) < ($1.fuelExpires ?? .distantFuture) }
            error = nil
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }
}

// MARK: - Moon mining

struct MoonMiningView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var extractions: [(e: ESIMoonExtraction, refinery: String, moon: String)]?
    @State private var extractionsError: Error?
    @State private var ledger: (pilots: [(id: Int, units: Int, isk: Double)], ores: [(id: Int, units: Int, isk: Double)], total: Double)?
    @State private var ledgerError: Error?
    @State private var names: [Int: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if env.characterStore.selectedService == nil {
                Text("Sign in with a character to see the corporation's moon mining.").font(.ui(13)).foregroundStyle(C.muted)
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { ctx in
                    Card(String(localized: "Moon extractions")) {
                        if let extractionsError {
                            Text(roleMessage(extractionsError, role: "Station Manager")).font(.ui(13)).foregroundStyle(C.warn)
                        } else if let extractions {
                            if extractions.isEmpty { Text("No active extractions.").font(.ui(13)).foregroundStyle(C.muted) }
                            ForEach(extractions, id: \.e.structureId) { x in
                                let arrival = x.e.chunkArrivalTime.timeIntervalSince(ctx.date)
                                let decay = x.e.naturalDecayTime.timeIntervalSince(ctx.date)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(verbatim: x.moon).font(.ui(13, .semibold)).foregroundStyle(C.text)
                                        Spacer(minLength: 4)
                                        if arrival > 0 {
                                            Text(verbatim: Fmt.duration(seconds: arrival)).font(.mono(12, medium: true)).foregroundStyle(C.text)
                                        } else {
                                            Text("Chunk ready").font(.ui(12, .medium)).foregroundStyle(C.good)
                                        }
                                    }
                                    HStack {
                                        Text(verbatim: x.refinery).lineLimit(1)
                                        Spacer(minLength: 4)
                                        Text(decay > 0 ? String(localized: "self-fractures in \(Fmt.duration(seconds: decay))") : String(localized: "fractured"))
                                    }
                                    .font(.ui(11)).foregroundStyle(C.muted)
                                }
                                .padding(.vertical, 3)
                            }
                        } else {
                            ProgressView().tint(C.accent).frame(maxWidth: .infinity)
                        }
                    }
                }
                if let ledgerError {
                    Text(roleMessage(ledgerError, role: "Accountant")).font(.ui(13)).foregroundStyle(C.warn)
                } else if let ledger {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                        StatTile(label: "Moon ore, 30 days (Jita buy)", value: Fmt.isk(ledger.total))
                        StatTile(label: "Pilots", value: "\(ledger.pilots.count)")
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], alignment: .leading, spacing: 12) {
                        Card(String(localized: "By pilot")) {
                            ForEach(ledger.pilots, id: \.id) { p in
                                HStack(spacing: 6) {
                                    EVECharacterPortrait(characterId: p.id, size: 22)
                                    Text(verbatim: names[p.id] ?? "#\(p.id)").font(.ui(13)).foregroundStyle(C.text).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text(verbatim: p.units.formatted()).font(.mono(11)).foregroundStyle(C.muted)
                                    Text(verbatim: Fmt.isk(p.isk)).font(.mono(12)).foregroundStyle(C.text)
                                }
                            }
                        }
                        Card(String(localized: "By ore")) {
                            ForEach(ledger.ores, id: \.id) { o in
                                HStack(spacing: 6) {
                                    EVETypeIcon(typeId: o.id, size: 22)
                                    Text(verbatim: names[o.id] ?? "#\(o.id)").font(.ui(13)).foregroundStyle(C.text).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text(verbatim: o.units.formatted()).font(.mono(11)).foregroundStyle(C.muted)
                                    Text(verbatim: Fmt.isk(o.isk)).font(.mono(12)).foregroundStyle(C.text)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task(id: env.dataKey) { await load() }
    }

    private func load() async {
        guard let svc = env.characterStore.selectedService else { return }
        guard let corp = try? await svc.characterInfo().corporationId else { return }
        let market = MarketService()
        do {
            let list = try await svc.moonExtractions(corpId: corp).sorted { $0.chunkArrivalTime < $1.chunkArrivalTime }
            // Refinery names from the structures list (same role).
            let structures = (try? await svc.corporationStructures(corpId: corp)) ?? []
            let refinery = Dictionary(structures.map { ($0.structureId, $0.name ?? "#\($0.structureId)") }, uniquingKeysWith: { a, _ in a })
            var moons: [Int: String] = [:]
            for e in list { moons[e.moonId] = try? await market.moonName(e.moonId) }
            extractions = list.map { ($0, refinery[$0.structureId] ?? "#\($0.structureId)", moons[$0.moonId] ?? "#\($0.moonId)") }
            extractionsError = nil
        } catch {
            if !error.isCancellation { extractionsError = error }
        }
        do {
            let observers = try await svc.miningObservers(corpId: corp)
            var rows: [ESIObserverEntry] = []
            for o in observers { rows += (try? await svc.observerLedger(corpId: corp, observerId: o.observerId)) ?? [] }
            let prices = (try? await HubPrices.hub(station: HubPrices.jitaStation, typeIds: Set(rows.map(\.typeId)))) ?? [:]
            func group(_ key: (ESIObserverEntry) -> Int) -> [(id: Int, units: Int, isk: Double)] {
                var m: [Int: (units: Int, isk: Double)] = [:]
                for r in rows { m[key(r), default: (0, 0)].units += r.quantity; m[key(r), default: (0, 0)].isk += Double(r.quantity) * (prices[r.typeId]?.buy ?? 0) }
                return m.map { ($0.key, $0.value.units, $0.value.isk) }.sorted { $0.isk > $1.isk }
            }
            var n = ((try? await env.repository?.types(ids: Set(rows.map(\.typeId)))) ?? [:]).mapValues(\.name)
            n.merge((try? await market.names(ids: Array(Set(rows.map(\.characterId))))) ?? [:]) { a, _ in a }
            names = n
            ledger = (group(\.characterId), group(\.typeId), rows.reduce(0) { $0 + Double($1.quantity) * (prices[$1.typeId]?.buy ?? 0) })
            ledgerError = nil
        } catch {
            if !error.isCancellation { ledgerError = error }
        }
    }
}
