// An ESI item list (a saved fit, a killmail) as the engine's fit, by the desktop's fromEsiItems rules:
// modules by slot flag with their default state, the charge loaded in the same slot or else the most
// plentiful compatible one in the hold, drones five launched in all.

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

    static func spec(for fit: ESIFitting, repo: SDERepository) async throws -> JSFitSpec {
        let ids = Set(fit.items.map(\.typeId))
        let profiles = try await repo.typeProfiles(typeIds: ids)
        let activation = (try? await repo.moduleActivation(typeIds: ids)) ?? [:]
        let slotOf: (String) -> String? = { flag in
            if flag.hasPrefix("HiSlot") { return "hi" }
            if flag.hasPrefix("MedSlot") { return "med" }
            if flag.hasPrefix("LoSlot") { return "lo" }
            if flag.hasPrefix("RigSlot") { return "rig" }
            if flag.hasPrefix("SubSystem") { return "sub" }
            return nil
        }
        let isModule = { (id: Int) in !(profiles[id]?.effectIds.isDisjoint(with: [11, 12, 13, 2663, 3772]) ?? true) }
        let isCharge = { (id: Int) in profiles[id]?.effectIds.contains(9) == true }
        let cargo = fit.items.filter { $0.flag == "Cargo" }

        var modules: [JSFitModule] = []
        var chargeFor: [Int: Int?] = [:]
        for item in fit.items {
            guard let slot = slotOf(item.flag), isModule(item.typeId) else { continue }
            var charge = fit.items.first { $0.flag == item.flag && $0.typeId != item.typeId && isCharge($0.typeId) }?.typeId
            // An unloaded weapon takes the most plentiful compatible charge in the hold.
            if charge == nil, !cargo.isEmpty {
                if chargeFor[item.typeId] == nil {
                    let fits = Set(((try? await repo.compatibleCharges(weaponTypeId: item.typeId)) ?? []).map(\.id))
                    let stock = cargo.filter { fits.contains($0.typeId) }.reduce(into: [Int: Int]()) { $0[$1.typeId, default: 0] += $1.quantity }
                    chargeFor[item.typeId] = stock.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
                }
                charge = chargeFor[item.typeId] ?? nil
            }
            let state = (activation[item.typeId]?.defaultState ?? .online).rawValue.lowercased()
            modules.append(JSFitModule(typeId: item.typeId, slot: slot, state: state, chargeTypeId: charge))
        }

        var drones: [JSFitDrone] = []
        for item in fit.items where item.flag == "DroneBay" {
            if let i = drones.firstIndex(where: { $0.typeId == item.typeId }) {
                drones[i].count += max(1, item.quantity)
            } else {
                drones.append(JSFitDrone(typeId: item.typeId, count: max(1, item.quantity), active: 0))
            }
        }
        var toLaunch = 5
        for i in drones.indices {
            drones[i].active = min(drones[i].count, toLaunch)
            toLaunch -= drones[i].active
        }
        return JSFitSpec(shipTypeId: fit.shipTypeId, name: fit.name, modules: modules, drones: drones, implants: [])
    }
}
