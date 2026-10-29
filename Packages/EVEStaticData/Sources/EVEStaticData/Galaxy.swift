// Known space for the 3D map (the desktop's sde galaxy()): every system with gates, its position in
// light years, security and region, and the stargate links between them. Wormhole and abyssal systems
// (ids from 31 000 000) have no gates and sit in their own space, so they are left out.

import Foundation
import GRDB

public struct GalaxyData: Sendable {
    public let ids: [Int]
    public let names: [String]
    public let security: [Double]
    /// Index into `regionNames` per system.
    public let region: [Int]
    public let regionIds: [Int]
    public let regionNames: [String]
    /// x, y, z per system, light years, in the map's frame (the SDE's z flipped, as the desktop shows it).
    public let positions: [SIMD3<Float>]
    /// Pairs of system indices linked by a stargate, each pair once.
    public let edges: [(Int, Int)]
    /// Stargate neighbours of each system (indices).
    public let neighbors: [[Int]]
    /// A capital's jump drive can enter it: known space below 0.5, not Pochven.
    public let jumpable: [Bool]
    public let index: [Int: Int]

    public var count: Int { ids.count }
}

extension SDERepository {
    public func galaxy() async throws -> GalaxyData {
        try await dbReader.read { db in
            let lightYear = 9_460_730_472_580_800.0
            var ids: [Int] = [], names: [String] = [], sec: [Double] = [], region: [Int] = [], pos: [SIMD3<Float>] = []
            var regionIds: [Int] = [], regionNames: [String] = [], regionIndex: [Int: Int] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT s.id, s.name, s.security, s.x, s.y, s.z, c.region_id, r.name AS region_name
                FROM systems s JOIN constellations c ON c.id = s.constellation_id JOIN regions r ON r.id = c.region_id
                WHERE s.id < 31000000 AND s.x IS NOT NULL
                ORDER BY s.id
                """) {
                let rid: Int = row["region_id"]
                let ri = regionIndex[rid] ?? {
                    regionIds.append(rid)
                    regionNames.append(row["region_name"])
                    regionIndex[rid] = regionIds.count - 1
                    return regionIds.count - 1
                }()
                ids.append(row["id"])
                names.append(row["name"])
                sec.append(row["security"])
                region.append(ri)
                let x: Double = row["x"], y: Double = row["y"], z: Double = row["z"]
                pos.append(SIMD3(Float(x / lightYear), Float(y / lightYear), Float(-z / lightYear)))
            }
            let index = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
            var edges: [(Int, Int)] = []
            for row in try Row.fetchAll(db, sql: "SELECT from_id, to_id FROM jumps WHERE from_id < to_id") {
                if let a = index[row["from_id"] as Int], let b = index[row["to_id"] as Int] { edges.append((a, b)) }
            }
            var neighbors = [[Int]](repeating: [], count: ids.count)
            for (a, b) in edges {
                neighbors[a].append(b)
                neighbors[b].append(a)
            }
            let pochven = 10000070
            let jumpable = ids.indices.map { i in
                ids[i] < 31_000_000 && (sec[i] * 10).rounded() / 10 < 0.5 && regionIds[region[i]] != pochven
            }
            return GalaxyData(ids: ids, names: names, security: sec, region: region, regionIds: regionIds,
                              regionNames: regionNames, positions: pos, edges: edges, neighbors: neighbors,
                              jumpable: jumpable, index: index)
        }
    }
}

/// A ship with a jump drive and its base range (attribute 867), light years.
public struct JumpDriveShip: Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let baseRange: Double
}

extension SDERepository {
    /// Published ships that carry a jump drive, by name.
    public func jumpDriveShips() async throws -> [JumpDriveShip] {
        try await dbReader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT t.id, t.name, a.value FROM types t
                JOIN groups g ON g.id = t.group_id
                JOIN type_attributes a ON a.type_id = t.id AND a.attribute_id = 867
                WHERE g.category_id = 6 AND t.published = 1 AND a.value > 0
                ORDER BY t.name
                """).map { JumpDriveShip(id: $0["id"], name: $0["name"], baseRange: $0["value"]) }
        }
    }
}

extension SDERepository {
    /// Type ids for exact names (any case), with the category: the fleet window names ships in text.
    public func typesNamed(_ names: Set<String>) async throws -> [String: (id: Int, category: Int)] {
        guard !names.isEmpty else { return [:] }
        return try await dbReader.read { db in
            let lower = names.map { $0.lowercased() }
            var out: [String: (id: Int, category: Int)] = [:]
            for start in stride(from: 0, to: lower.count, by: 500) {
                let chunk = Array(lower[start..<min(start + 500, lower.count)])
                for row in try Row.fetchAll(db, sql: """
                    SELECT t.id, t.name, g.category_id FROM types t JOIN groups g ON g.id = t.group_id
                    WHERE lower(t.name) IN (\(chunk.map { _ in "?" }.joined(separator: ","))) AND t.published = 1
                    """, arguments: StatementArguments(chunk)) {
                    out[(row["name"] as String).lowercased()] = (row["id"], row["category_id"])
                }
            }
            return out
        }
    }
}

extension SDERepository {
    /// Names and security of solar systems.
    public func systems(ids: Set<Int>) async throws -> [Int: (name: String, security: Double)] {
        guard !ids.isEmpty else { return [:] }
        return try await dbReader.read { db in
            var out: [Int: (name: String, security: Double)] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT id, name, security FROM systems WHERE id IN (\(ids.map(String.init).joined(separator: ",")))") {
                out[row["id"]] = (row["name"], row["security"])
            }
            return out
        }
    }
}
