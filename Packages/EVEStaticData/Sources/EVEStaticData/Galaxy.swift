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
            return GalaxyData(ids: ids, names: names, security: sec, region: region, regionIds: regionIds,
                              regionNames: regionNames, positions: pos, edges: edges, index: index)
        }
    }
}
