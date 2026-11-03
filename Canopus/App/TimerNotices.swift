// What the desktop's notifier checks in the background (industry jobs done, PI extractors stopped,
// structure fuel and reinforce timers, moon chunks), done the iPhone way: every one of these happens at a
// time ESI already knows, so Canopus schedules local notifications for them whenever it opens. Each
// character and kind has its own id prefix, so a later refresh replaces what was scheduled before.

import Foundation
import Domain
import EVEAuth
import EVEStaticData

@MainActor
enum TimerNotices {
    /// Last refresh per character, so coming back to the app every minute doesn't hit ESI each time.
    private static var refreshed: [Int: Date] = [:]

    static func refreshAll(_ services: [CharacterService], repo: SDERepository?) async {
        let settings = NotificationSettings.shared
        await settings.refresh()
        for svc in services {
            let id = svc.tokens.characterId
            if let at = refreshed[id], Date().timeIntervalSince(at) < 600 { continue }
            refreshed[id] = .now
            let name = svc.tokens.characterName
            await industry(svc, name: name, repo: repo, enabled: settings.industryDone)
            await planets(svc, name: name, enabled: settings.piExtractors)
            await corporation(svc, enabled: settings.structures)
        }
    }

    private static func industry(_ svc: CharacterService, name: String, repo: SDERepository?, enabled: Bool) async {
        guard let jobs = try? await svc.industryJobs() else { return }
        let active = jobs.filter { $0.status == "active" }
        let names = ((try? await repo?.types(ids: Set(active.map { $0.productTypeId ?? $0.blueprintTypeId }))) ?? [:]).mapValues(\.name)
        let notices = active.map { j in
            TimedNotice(id: "\(j.jobId)", date: j.endDate, title: String(localized: "Industry job done"),
                        body: String(localized: "\(name): \(names[j.productTypeId ?? j.blueprintTypeId] ?? "#\(j.blueprintTypeId)") ×\(j.runs) — deliver it"))
        }
        await TimedNotices.replace(prefix: "canopus.job.\(svc.tokens.characterId).", with: notices, enabled: enabled)
    }

    private static func planets(_ svc: CharacterService, name: String, enabled: Bool) async {
        guard let colonies = try? await svc.planets() else { return }
        let market = MarketService()
        var notices: [TimedNotice] = []
        for c in colonies {
            guard let pins = try? await svc.planet(c.planetId).pins,
                  let expiry = pins.filter({ $0.extractorDetails != nil }).compactMap(\.expiryTime).min() else { continue }
            let planet = (try? await market.planetName(c.planetId)) ?? "#\(c.planetId)"
            notices.append(TimedNotice(id: "\(c.planetId)", date: expiry, title: String(localized: "Extractors stopped"),
                                       body: String(localized: "\(name): \(planet) — restart the extraction programs")))
        }
        await TimedNotices.replace(prefix: "canopus.pi.\(svc.tokens.characterId).", with: notices, enabled: enabled)
    }

    /// Fuel for three days left and reinforce timers ending (Station Manager), moon chunks arriving.
    private static func corporation(_ svc: CharacterService, enabled: Bool) async {
        guard let corp = try? await svc.characterInfo().corporationId else { return }
        var notices: [TimedNotice] = []
        // A character without the roles sees nothing: keep what a corp mate's refresh scheduled.
        var answered = false
        if let structures = try? await svc.corporationStructures(corpId: corp) {
            answered = true
            for s in structures {
                let name = s.name ?? "#\(s.structureId)"
                if let fuel = s.fuelExpires {
                    notices.append(TimedNotice(id: "fuel.\(s.structureId)", date: fuel.addingTimeInterval(-3 * 86_400),
                                               title: String(localized: "\(name): fuel running low"), body: String(localized: "Fuel for 3 days left")))
                }
                if let end = s.stateTimerEnd, s.state.hasSuffix("_reinforce") {
                    notices.append(TimedNotice(id: "rf.\(s.structureId)", date: end.addingTimeInterval(-30 * 60),
                                               title: String(localized: "\(name): out of reinforce in 30 minutes"), body: String(localized: "The structure becomes vulnerable")))
                }
            }
        }
        if let extractions = try? await svc.moonExtractions(corpId: corp) {
            answered = true
            let market = MarketService()
            for e in extractions {
                let moon = (try? await market.moonName(e.moonId)) ?? "#\(e.moonId)"
                notices.append(TimedNotice(id: "moon.\(e.structureId)", date: e.chunkArrivalTime, title: String(localized: "Moon chunk ready"),
                                           body: String(localized: "\(moon): fracture it before it self-fractures")))
            }
        }
        // Corporation-wide: one set per corporation, not per character.
        guard answered || !enabled else { return }
        await TimedNotices.replace(prefix: "canopus.corp.\(corp).", with: notices, enabled: enabled)
    }
}
