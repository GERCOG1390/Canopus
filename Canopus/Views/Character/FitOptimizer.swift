// Fit optimizer: swaps fitted modules and drones for other versions of the same item (Tech I, Tech II,
// faction, deadspace...) to pay less for the same numbers, or to pay a little more for a big gain.
// A port of canopus-desktop src/renderer/src/pages/FitOptimize.tsx (the same rules and thresholds); the
// numbers come from the bundled engine, prices are Jita sell orders (Fuzzwork aggregates, as the desktop).

import Foundation
import EVEAuth
import Domain
import EVEStaticData

enum OptimizerMetric: String, CaseIterable, Identifiable {
    case dps, ehp, activeTank, speed, align, lockRange, cap, range, application
    var id: String { rawValue }

    var label: String {
        switch self {
        case .dps: String(localized: "Damage (DPS)")
        case .ehp: String(localized: "EHP")
        case .activeTank: String(localized: "Active tank")
        case .speed: String(localized: "Speed")
        case .align: String(localized: "Align time")
        case .lockRange: String(localized: "Targeting range")
        case .cap: String(localized: "Capacitor")
        case .range: String(localized: "Weapon range")
        case .application: String(localized: "Damage application")
        }
    }
}

/// One swap: every fitted module (or the drone stack) of `from` replaced by `to`, with the fit's numbers after it.
struct FitVariant: Identifiable {
    var id: String { "\(from)-\(to)" }
    let from: Int
    let to: Int
    let isDrone: Bool
    let count: Int
    let missingSkills: Bool
    let metrics: FitMetrics
}

struct OptimizerData {
    let base: FitMetrics
    let options: [FitVariant]
    let prices: [Int: Double]
    /// Names of every type in the options (the variants are not in the fit, so the screen doesn't know them).
    let names: [Int: String]

    func price(_ id: Int) -> Double? { prices[id].flatMap { $0 > 0 ? $0 : nil } }
}

enum FitOptimizer {
    // MARK: Comparing numbers (gain / keeps / sideEffects)

    /// Relative change where `down` means lower is better, %, "better" positive.
    static func rel(_ x: Double, _ y: Double, down: Bool) -> Double {
        guard y != 0 else { return 0 }
        return down ? (y - x) / y * 100 : (x - y) / y * 100
    }

    /// Damage application as one number: tracking for turrets, explosion radius and speed for missiles; the worst counts.
    static func applicationGain(_ m: FitMetrics, _ b: FitMetrics) -> Double {
        let parts = [
            b.tracking != 0 ? rel(m.tracking, b.tracking, down: false) : nil,
            b.explosionRadius != 0 ? rel(m.explosionRadius, b.explosionRadius, down: true) : nil,
            b.explosionVelocity != 0 ? rel(m.explosionVelocity, b.explosionVelocity, down: false) : nil,
        ].compactMap { $0 }
        guard let worst = parts.min(), let best = parts.max() else { return 0 }
        return worst < -0.05 ? worst : best
    }

    /// Relative change of a metric, %, "better" positive (shorter align time is better).
    static func gain(_ m: FitMetrics, _ b: FitMetrics, _ k: OptimizerMetric) -> Double {
        switch k {
        case .cap:
            if m.capStable && b.capStable { return (m.capLevel - b.capLevel) * 100 }
            if m.capStable != b.capStable { return m.capStable ? 100 : -100 }
            return b.capLasts != 0 ? (m.capLasts - b.capLasts) / b.capLasts * 100 : 0
        case .application:
            return applicationGain(m, b)
        default:
            let (x, y) = (value(m, k), value(b, k))
            if y == 0 { return x > 0 ? 100 : 0 }
            return k == .align ? (y - x) / y * 100 : (x - y) / y * 100
        }
    }

    private static func value(_ m: FitMetrics, _ k: OptimizerMetric) -> Double {
        switch k {
        case .dps: m.dps
        case .ehp: m.ehp
        case .activeTank: m.activeTank
        case .speed: m.speed
        case .align: m.align
        case .lockRange: m.lockRange
        case .range: m.range
        case .cap, .application: 0
        }
    }

    /// Nothing the optimizer watches got worse by more than `tol` (a fraction), and the fit still fits.
    static func keeps(_ m: FitMetrics, _ b: FitMetrics, tol: Double) -> Bool {
        func ge(_ x: Double, _ y: Double, _ eps: Double) -> Bool { x >= y * (1 - tol) - eps }
        let cap = b.capStable ? (m.capStable && m.capLevel >= b.capLevel - tol - 0.001) : (m.capStable || m.capLasts >= b.capLasts * (1 - tol) - 1)
        return (m.fits || !b.fits)
            && ge(m.dps, b.dps, 0.05)
            && ge(m.ehp, b.ehp, 1)
            && ge(m.activeTank, b.activeTank, 0.05)
            && ge(m.speed, b.speed, 0.05)
            && m.align <= b.align * (1 + tol) + 0.005
            && ge(m.lockRange, b.lockRange, 1)
            && ge(m.scanRes, b.scanRes, 0.5)
            && m.signature <= b.signature * (1 + tol) + 0.05
            && ge(m.range, b.range, 1)
            && ge(m.tracking, b.tracking, 1e-6)
            && m.explosionRadius <= b.explosionRadius * (1 + tol) + 0.05
            && ge(m.explosionVelocity, b.explosionVelocity, 0.05)
            && cap
    }

    /// What else changes noticeably: "EHP +4% · Speed −2%".
    static func sideEffects(_ m: FitMetrics, _ b: FitMetrics, skip: OptimizerMetric? = nil) -> String {
        let main = OptimizerMetric.allCases.filter { $0 != skip }.map { ($0.label, gain(m, b, $0)) }
        let extra = [
            (String(localized: "Signature"), rel(m.signature, b.signature, down: true)),
            (String(localized: "Scan resolution"), rel(m.scanRes, b.scanRes, down: false)),
        ]
        return (main + extra).filter { abs($0.1) >= 1 }.map { "\($0.0) \(pct($0.1))" }.joined(separator: " · ")
    }

    static func pct(_ v: Double) -> String {
        (v > 0 ? "+" : "") + v.formatted(.number.precision(.fractionLength(0...1))) + "%"
    }

    // MARK: Swaps

    static func swap(_ spec: JSFitSpec, _ v: FitVariant) -> JSFitSpec {
        var s = spec
        if v.isDrone {
            for i in s.drones.indices where s.drones[i].typeId == v.from { s.drones[i].typeId = v.to }
        } else {
            for i in s.modules.indices where s.modules[i].typeId == v.from { s.modules[i].typeId = v.to }
        }
        return s
    }

    /// Every other version of each fitted module / drone type with its numbers, and Jita sell prices.
    static func load(spec: JSFitSpec, skills: JSSkills, levels: [Int: Int]?, dogma: DogmaJS, repo: SDERepository) async throws -> OptimizerData {
        let candidates = try await repo.fitVariants(
            shipTypeId: spec.shipTypeId,
            moduleTypeIds: Set(spec.modules.map(\.typeId)),
            droneTypeIds: Set(spec.drones.map(\.typeId)),
            levels: levels
        )
        let count = { (c: FitVariantCandidate) in
            c.isDrone ? spec.drones.filter { $0.typeId == c.from }.reduce(0) { $0 + $1.count } : spec.modules.filter { $0.typeId == c.from }.count
        }
        let swapped = candidates.map { c in
            var s = spec
            if c.isDrone {
                for i in s.drones.indices where s.drones[i].typeId == c.from { s.drones[i].typeId = c.to }
            } else {
                for i in s.modules.indices where s.modules[i].typeId == c.from { s.modules[i].typeId = c.to }
            }
            return s
        }
        let all = try await dogma.metrics([spec] + swapped, skills: skills)

        let options = zip(candidates, all.dropFirst()).map { c, m in
            FitVariant(from: c.from, to: c.to, isDrone: c.isDrone, count: count(c), missingSkills: c.missingSkills, metrics: m)
        }
        let ids = Set(options.flatMap { [$0.from, $0.to] })
        let prices = try await HubPrices.jitaSell(typeIds: ids)
        let names = try await repo.types(ids: ids).mapValues(\.name)
        return OptimizerData(base: all[0], options: options, prices: prices, names: names)
    }

    /// Per module type the biggest saving that keeps the numbers, then the picks checked together.
    static func findCheaper(_ d: OptimizerData, spec: JSFitSpec, skills: JSSkills, tol: Double, dogma: DogmaJS) async throws -> (picks: [(v: FitVariant, saving: Double)], combined: FitMetrics?) {
        var best: [Int: (v: FitVariant, saving: Double)] = [:]
        for v in d.options {
            guard let a = d.price(v.from), let b = d.price(v.to), !v.missingSkills, b < a, keeps(v.metrics, d.base, tol: tol) else { continue }
            let saving = (a - b) * Double(v.count)
            if (best[v.from]?.saving ?? 0) < saving { best[v.from] = (v, saving) }
        }
        // Swaps can add up (two cheaper modules may not fit CPU together): drop the smallest savings until it holds.
        var picks = best.values.sorted { $0.saving > $1.saving }
        while !picks.isEmpty {
            let combinedSpec = picks.reduce(spec) { swap($0, $1.v) }
            if let m = try await dogma.metrics([combinedSpec], skills: skills).first, keeps(m, d.base, tol: tol) {
                return (picks, m)
            }
            picks.removeLast()
        }
        return ([], nil)
    }

    /// Swaps that add the most to `metric` per million ISK, within `budget` per swap and without big losses elsewhere.
    static func findUpgrades(_ d: OptimizerData, metric: OptimizerMetric, budget: Double) -> [(v: FitVariant, gain: Double, cost: Double)] {
        d.options.compactMap { v -> (v: FitVariant, gain: Double, cost: Double)? in
            guard let a = d.price(v.from), let b = d.price(v.to), !v.missingSkills, v.metrics.fits || !d.base.fits else { return nil }
            let g = gain(v.metrics, d.base, metric)
            guard g >= 0.5 else { return nil }
            // A gain bought with a big loss elsewhere (Polarized weapons: no resists) is not an upgrade.
            if OptimizerMetric.allCases.contains(where: { $0 != metric && gain(v.metrics, d.base, $0) < -3 }) { return nil }
            let cost = (b - a) * Double(v.count)
            guard cost <= budget else { return nil }
            return (v, g, cost)
        }
        // Cheaper and better first, then the most gain per million ISK.
        .sorted { x, y in x.cost <= 0 || y.cost <= 0 ? x.cost < y.cost : y.gain / (y.cost / 1e6) < x.gain / (x.cost / 1e6) }
        .prefix(25)
        .map { $0 }
    }
}

/// Best buy / sell at a trade hub from Fuzzwork's aggregates (backed by ESI order snapshots), as the desktop.
enum HubPrices {
    static let jitaStation = 60003760

    /// Lowest Jita sell order per type.
    static func jitaSell(typeIds: Set<Int>) async throws -> [Int: Double] {
        var out: [Int: Double] = [:]
        let ids = typeIds.sorted()
        for start in stride(from: 0, to: ids.count, by: 200) {
            let chunk = ids[start..<min(start + 200, ids.count)]
            var url = URLComponents(string: "https://market.fuzzwork.co.uk/aggregates/")!
            url.queryItems = [URLQueryItem(name: "station", value: String(jitaStation)), URLQueryItem(name: "types", value: chunk.map(String.init).joined(separator: ","))]
            var request = URLRequest(url: url.url!)
            request.setValue(EVEConstants.userAgent, forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            // Values come as strings, or as plain numbers for types without orders.
            let raw = try JSONSerialization.jsonObject(with: data) as? [String: [String: [String: Any]]] ?? [:]
            for (id, sides) in raw {
                let value = sides["sell"]?["min"]
                let min = (value as? String).flatMap(Double.init) ?? (value as? NSNumber)?.doubleValue
                if let id = Int(id), let min { out[id] = min }
            }
        }
        return out
    }
}
