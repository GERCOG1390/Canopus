// A pilot's training attributes as the desktop's CharacterContext works them out. ESI doesn't document
// whether /attributes includes implants, so the skill in training decides: whichever set reproduces its
// real SP per minute; without one, a character's own attributes always sum to 99 (5 × 17 + 14), so a
// larger sum means the implants are already in.

import Foundation
import EVEAuth
import EVEStaticData

/// Attribute ids: 164 charisma, 165 intelligence, 166 memory, 167 perception, 168 willpower.
let attributeIds = [164, 165, 166, 167, 168]
/// Character attribute → the implant attribute that raises it.
let implantBonusAttr: [Int: Int] = [164: 175, 165: 176, 166: 177, 167: 178, 168: 179]

struct PilotAttributes {
    /// Without implants
    var base: [Int: Int]
    /// With implants: what training uses
    var effective: [Int: Int]
    var implantBonus: [Int: Int] { Dictionary(uniqueKeysWithValues: attributeIds.map { ($0, (effective[$0] ?? 0) - (base[$0] ?? 0)) }) }
    var raw: ESICharacterAttributes

    /// A new character's attributes (nobody logged in).
    static let newCharacter: [Int: Int] = [164: 19, 165: 20, 166: 20, 167: 20, 168: 20]

    static func load(service: CharacterService, repository: SDERepository?) async -> PilotAttributes? {
        guard let a = try? await service.characterAttributes() else { return nil }
        let esi: [Int: Int] = [164: a.charisma, 165: a.intelligence, 166: a.memory, 167: a.perception, 168: a.willpower]
        let implants = (try? await service.implants()) ?? []
        var bonus: [Int: Int] = [:]
        if let repository, !implants.isEmpty, let maps = try? await repository.typeAttributeMaps(typeIds: Set(implants)) {
            for m in maps.values { for (attr, b) in implantBonusAttr { bonus[attr, default: 0] += Int(m[b] ?? 0) } }
        }
        let bonusSum = bonus.values.reduce(0, +)
        guard bonusSum > 0 else { return PilotAttributes(base: esi, effective: esi, raw: a) }
        let withImplants = esi.mapValues { $0 } .merging(bonus) { $0 + $1 }
        let withoutImplants = esi.merging(bonus) { $0 - $1 }

        var esiIncludesImplants: Bool
        if let queue = try? await service.skillQueue(),
           let e = queue.first(where: { ($0.finishDate ?? .distantPast) > Date() && $0.startDate != nil }),
           let start = e.startDate, let end = e.finishDate, let endSp = e.levelEndSp, let startSp = e.trainingStartSp,
           end.timeIntervalSince(start) > 0, let repository,
           let skill = try? await repository.typeAttributeMaps(typeIds: [e.skillId])[e.skillId] {
            let observed = Double(endSp - startSp) / (end.timeIntervalSince(start) / 60)
            let p = Int(skill[180] ?? 0), s = Int(skill[181] ?? 0)
            let rate = { (x: [Int: Int]) in Double(x[p] ?? 0) + Double(x[s] ?? 0) / 2 }
            esiIncludesImplants = abs(rate(esi) - observed) < abs(rate(withImplants) - observed)
        } else {
            esiIncludesImplants = esi.values.reduce(0, +) >= 99 + bonusSum
        }
        return esiIncludesImplants
            ? PilotAttributes(base: withoutImplants, effective: esi, raw: a)
            : PilotAttributes(base: esi, effective: withImplants, raw: a)
    }
}
