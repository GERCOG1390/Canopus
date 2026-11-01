// Wormhole data (the desktop's sde wormholeTypes / system): every wormhole type with where it leads,
// its lifetime and mass limits, and a J-space system's class and effect (importer 5).

import Foundation
import GRDB

public struct WormholeType: Sendable, Identifiable, Hashable {
    public let id: Int
    /// Signature code: C247, K162…
    public let code: String
    /// Destination class (1–6 C1–C6, 7 highsec, 8 lowsec, 9 nullsec, 12 Thera, 25 Pochven…)
    public let target: Int
    /// Minutes
    public let lifetime: Double
    /// Kilograms
    public let mass: Double
    public let jumpMass: Double
    /// Kilograms a day
    public let regen: Double
}

public struct WormholeSystem: Sendable, Hashable {
    public let id: Int
    public let name: String
    public let security: Double
    public let region: String
    public let wormholeClass: Int?
    /// The effect beacon type (Magnetar, Pulsar…)
    public let effectTypeId: Int?
}

extension SDERepository {
    public func wormholeTypes() async throws -> [WormholeType] {
        try await dbReader.read { db in
            var attrs: [Int: [Int: Double]] = [:]
            for r in try Row.fetchAll(db, sql: """
                SELECT a.type_id, a.attribute_id, a.value FROM type_attributes a JOIN types t ON t.id = a.type_id
                WHERE t.group_id = 988 AND a.attribute_id IN (1381, 1382, 1383, 1384, 1385)
                """) {
                attrs[r["type_id"], default: [:]][r["attribute_id"]] = r["value"]
            }
            var byCode: [String: WormholeType] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT id, name FROM types WHERE group_id = 988") {
                let id: Int = r["id"]
                let name: String = r["name"]
                let code = name.replacingOccurrences(of: "Wormhole ", with: "", options: [.anchored, .caseInsensitive])
                guard code.count == 4, code.allSatisfy({ $0.isUppercase || $0.isNumber }) else { continue }
                let a = attrs[id] ?? [:]
                let w = WormholeType(id: id, code: code, target: Int(a[1381] ?? 0), lifetime: a[1382] ?? 0, mass: a[1383] ?? 0,
                                     jumpMass: a[1385] ?? 0, regen: a[1384] ?? 0)
                // One entry per code (some codes exist as several types).
                if (byCode[code]?.mass ?? -1) < w.mass { byCode[code] = w }
            }
            return byCode.values.sorted { $0.code < $1.code }
        }
    }

    /// A system by its exact name, with its wormhole class and effect when the database has them.
    public func wormholeSystem(named name: String) async throws -> WormholeSystem? {
        try await dbReader.read { db in
            let hasClass = try db.columns(in: "systems").contains { $0.name == "wormhole_class" }
            let extra = hasClass ? ", s.wormhole_class, s.effect_type_id" : ""
            guard let r = try Row.fetchOne(db, sql: """
                SELECT s.id, s.name, s.security, r.name AS region\(extra) FROM systems s
                JOIN constellations c ON c.id = s.constellation_id JOIN regions r ON r.id = c.region_id
                WHERE lower(s.name) = lower(?)
                """, arguments: [name]) else { return nil }
            return WormholeSystem(id: r["id"], name: r["name"], security: r["security"], region: r["region"],
                                  wormholeClass: hasClass ? r["wormhole_class"] : nil, effectTypeId: hasClass ? r["effect_type_id"] : nil)
        }
    }
}
