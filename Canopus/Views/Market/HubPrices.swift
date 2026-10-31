// Prices at the trade hubs from Fuzzwork's aggregates (backed by ESI order snapshots, refreshed about
// every 30 minutes), as the desktop's lib/market.ts: best buy and sell with their volumes.

import Foundation
import EVEAuth

struct TradeHub: Hashable, Identifiable {
    let name: String
    let stationId: Int
    let regionId: Int
    let systemId: Int
    var id: Int { stationId }

    static let all: [TradeHub] = [
        TradeHub(name: "Jita", stationId: 60003760, regionId: 10000002, systemId: 30000142),
        TradeHub(name: "Amarr", stationId: 60008494, regionId: 10000043, systemId: 30002187),
        TradeHub(name: "Dodixie", stationId: 60011866, regionId: 10000032, systemId: 30002659),
        TradeHub(name: "Rens", stationId: 60004588, regionId: 10000030, systemId: 30002510),
        TradeHub(name: "Hek", stationId: 60005686, regionId: 10000042, systemId: 30002053),
    ]
    static let jita = all[0]
}

struct HubPrice {
    /// Lowest sell order, 0 when none.
    let sell: Double
    let sellVolume: Double
    /// Highest buy order, 0 when none.
    let buy: Double
    let buyVolume: Double
}

enum HubPrices {
    static let jitaStation = TradeHub.jita.stationId

    /// Best prices and volumes at a station, per type (200 types per request).
    static func hub(station: Int, typeIds: Set<Int>) async throws -> [Int: HubPrice] {
        var out: [Int: HubPrice] = [:]
        let ids = typeIds.sorted()
        for start in stride(from: 0, to: ids.count, by: 200) {
            let chunk = ids[start..<min(start + 200, ids.count)]
            var url = URLComponents(string: "https://market.fuzzwork.co.uk/aggregates/")!
            url.queryItems = [URLQueryItem(name: "station", value: String(station)), URLQueryItem(name: "types", value: chunk.map(String.init).joined(separator: ","))]
            var request = URLRequest(url: url.url!)
            request.setValue(EVEConstants.userAgent, forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            // Values come as strings, or as plain numbers for types without orders.
            let raw = try JSONSerialization.jsonObject(with: data) as? [String: [String: [String: Any]]] ?? [:]
            let number = { (v: Any?) in (v as? String).flatMap(Double.init) ?? (v as? NSNumber)?.doubleValue ?? 0 }
            for (id, sides) in raw {
                guard let id = Int(id) else { continue }
                out[id] = HubPrice(sell: number(sides["sell"]?["min"]), sellVolume: number(sides["sell"]?["volume"]),
                                   buy: number(sides["buy"]?["max"]), buyVolume: number(sides["buy"]?["volume"]))
            }
        }
        return out
    }

    /// Lowest Jita sell order per type.
    static func jitaSell(typeIds: Set<Int>) async throws -> [Int: Double] {
        try await hub(station: jitaStation, typeIds: typeIds).compactMapValues { $0.sell > 0 ? $0.sell : nil }
    }

    /// Lowest sell and highest buy order at a station, per type.
    static func prices(station: Int, typeIds: Set<Int>) async throws -> [Int: (sell: Double?, buy: Double?)] {
        try await hub(station: station, typeIds: typeIds).mapValues { ($0.sell > 0 ? $0.sell : nil, $0.buy > 0 ? $0.buy : nil) }
    }
}
