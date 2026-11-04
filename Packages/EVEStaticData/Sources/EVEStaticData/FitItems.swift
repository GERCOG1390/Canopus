// How an ESI item list becomes a fit — shared by every path that builds one (saved fits, the live ship
// from assets, killmails) and covered by tests, so a rule can't drift between them. The rules follow the
// desktop's fromEsiItems: modules by slot flag with their default state, the charge loaded in the same
// slot or else the most plentiful compatible one in the hold, drones five launched in all.

import Foundation

public enum FitSlotKind: String, Sendable, CaseIterable {
    case hi, med, lo, rig, sub, drone, cargo
}

/// One stack of an item list: a saved fit's item, or an asset inside the ship.
public struct FitItem: Sendable, Hashable {
    public let typeId: Int
    public let flag: String
    public let quantity: Int

    public init(typeId: Int, flag: String, quantity: Int) {
        self.typeId = typeId
        self.flag = flag
        self.quantity = quantity
    }
}

/// An asset as ESI lists it, the parts a ship's contents need.
public struct FitAsset: Sendable, Hashable {
    public let itemId: Int
    public let typeId: Int
    public let locationId: Int
    public let locationType: String
    public let flag: String
    public let quantity: Int

    public init(itemId: Int, typeId: Int, locationId: Int, locationType: String, flag: String, quantity: Int) {
        self.itemId = itemId
        self.typeId = typeId
        self.locationId = locationId
        self.locationType = locationType
        self.flag = flag
        self.quantity = quantity
    }
}

public enum FitItems {
    /// Where an item with this ESI flag sits. Only the numbered slots are fitted: SubSystemBay (spare
    /// subsystems), the fleet / fuel / ore holds and the rest are holds, counted as cargo.
    public static func slot(forFlag flag: String) -> FitSlotKind {
        if flag.hasPrefix("HiSlot") { return .hi }
        if flag.hasPrefix("MedSlot") { return .med }
        if flag.hasPrefix("LoSlot") { return .lo }
        if flag.hasPrefix("RigSlot") { return .rig }
        if flag.hasPrefix("SubSystemSlot") { return .sub }
        if flag == "DroneBay" || flag == "FighterBay" { return .drone }
        return .cargo
    }

    /// Everything directly inside the ship (its fitted modules, charges in them, drones and holds).
    public static func liveShip(assets: [FitAsset], shipItemId: Int) -> [FitItem] {
        assets.filter { $0.locationType == "item" && $0.locationId == shipItemId }
            .map { FitItem(typeId: $0.typeId, flag: $0.flag, quantity: $0.quantity) }
    }
}

extension SDERepository {
    /// The engine's fit for an item list (saved fit, live ship, killmail), with every module in its default
    /// state and charges as the desktop picks them.
    public func fitSpec(shipTypeId: Int, name: String, items: [FitItem]) async throws -> JSFitSpec {
        let ids = Set(items.map(\.typeId))
        let profiles = try await typeProfiles(typeIds: ids)
        let activation = (try? await moduleActivation(typeIds: ids)) ?? [:]
        let isModule = { (id: Int) in !(profiles[id]?.effectIds.isDisjoint(with: [11, 12, 13, 2663, 3772]) ?? true) }
        let isCharge = { (id: Int) in profiles[id]?.effectIds.contains(9) == true }
        let cargo = items.filter { FitItems.slot(forFlag: $0.flag) == .cargo }

        var modules: [JSFitModule] = []
        var chargeFor: [Int: Int?] = [:]
        for item in items {
            let slot = FitItems.slot(forFlag: item.flag)
            guard [.hi, .med, .lo, .rig, .sub].contains(slot), isModule(item.typeId) else { continue }
            var charge = items.first { $0.flag == item.flag && $0.typeId != item.typeId && isCharge($0.typeId) }?.typeId
            // An unloaded weapon takes the most plentiful compatible charge in the hold.
            if charge == nil, !cargo.isEmpty {
                if chargeFor[item.typeId] == nil {
                    let fits = Set(((try? await compatibleCharges(weaponTypeId: item.typeId)) ?? []).map(\.id))
                    let stock = cargo.filter { fits.contains($0.typeId) }.reduce(into: [Int: Int]()) { $0[$1.typeId, default: 0] += $1.quantity }
                    chargeFor[item.typeId] = stock.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
                }
                charge = chargeFor[item.typeId] ?? nil
            }
            let state = (activation[item.typeId]?.defaultState ?? .online).rawValue.lowercased()
            modules.append(JSFitModule(typeId: item.typeId, slot: slot.rawValue, state: state, chargeTypeId: charge))
        }

        var drones: [JSFitDrone] = []
        for item in items where FitItems.slot(forFlag: item.flag) == .drone {
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
        return JSFitSpec(shipTypeId: shipTypeId, name: name, modules: modules, drones: drones, implants: [])
    }
}
