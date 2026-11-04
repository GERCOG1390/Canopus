// Killmails as fits, and saved fits as the engine's spec (the rules themselves live in EVEStaticData's
// FitItems, shared with the fitting screen and covered by its tests).

import Foundation
import Domain
import EVEAuth
import EVEStaticData

enum FitSpecBuilder {
    /// Killmail inventory flags as the fitting names ESI uses for saved fits.
    static func flagName(_ flag: Int) -> String? {
        switch flag {
        case 11...18: "LoSlot\(flag - 11)"
        case 19...26: "MedSlot\(flag - 19)"
        case 27...34: "HiSlot\(flag - 27)"
        case 92...99: "RigSlot\(flag - 92)"
        case 125...132: "SubSystemSlot\(flag - 125)"
        case 87: "DroneBay"
        case 5: "Cargo"
        default: nil
        }
    }

    /// A killmail's victim as a fit the fitting screen can open.
    static func fitting(from km: ESIKillVictim, killmailId: Int) -> ESIFitting {
        let items = (km.items ?? []).compactMap { i -> ESIFittingItem? in
            guard let flag = flagName(i.flag) else { return nil }
            return ESIFittingItem(typeId: i.itemTypeId, flag: flag, quantity: max(1, (i.quantityDestroyed ?? 0) + (i.quantityDropped ?? 0)))
        }
        return ESIFitting(fittingId: -killmailId, name: "zKill \(killmailId)", description: "", shipTypeId: km.shipTypeId, items: items)
    }

    /// The engine's fit for a saved fit or killmail (the shared rules in EVEStaticData's FitItems).
    static func spec(for fit: ESIFitting, repo: SDERepository) async throws -> JSFitSpec {
        try await repo.fitSpec(shipTypeId: fit.shipTypeId, name: fit.name,
                               items: fit.items.map { FitItem(typeId: $0.typeId, flag: $0.flag, quantity: $0.quantity) })
    }
}
