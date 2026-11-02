// Thera / Turnur (the desktop's map tab): today's wormhole connections from EVE-Scout's public feed —
// where each exit leads, its signatures, the ships that fit and the hours left — and how many jumps each
// exit is from you. The desktop asks ESI for every route; here the jumps come from the map's own gates.

import SwiftUI
import EVEAuth
import EVEStaticData

private struct ScoutSignature: Decodable, Identifiable {
    let id: String
    let signatureType: String?
    let outSystemName: String
    let outSignature: String
    let inSystemId: Int
    let inSystemName: String
    let inSystemClass: String
    let inRegionName: String?
    let inSignature: String?
    let maxShipSize: String?
    let remainingHours: Double?

    enum CodingKeys: String, CodingKey {
        case id, signatureType = "signature_type", outSystemName = "out_system_name", outSignature = "out_signature"
        case inSystemId = "in_system_id", inSystemName = "in_system_name", inSystemClass = "in_system_class"
        case inRegionName = "in_region_name", inSignature = "in_signature", maxShipSize = "max_ship_size", remainingHours = "remaining_hours"
    }

    var isKSpace: Bool { inSystemClass.range(of: #"^c\d+$"#, options: [.regularExpression, .caseInsensitive]) == nil }
}

private func shipSizeLabel(_ s: String?) -> String {
    switch s {
    case "small": String(localized: "Small (frigates, destroyers)")
    case "medium": String(localized: "Medium (up to cruisers)")
    case "large": String(localized: "Large (up to battleships)")
    case "xlarge": String(localized: "Freighters")
    case "capital": String(localized: "Capitals")
    default: s ?? "—"
    }
}

private func classLabel(_ c: String) -> String {
    switch c.lowercased() {
    case "hs": String(localized: "Highsec")
    case "ls": String(localized: "Lowsec")
    case "ns": String(localized: "Nullsec")
    case "pochven": "Pochven"
    default: c.uppercased()
    }
}

struct TheraPage: View {
    private enum Hub: String, CaseIterable { case all, Thera, Turnur }

    @Environment(AppEnvironment.self) private var env
    @State private var signatures: [ScoutSignature]?
    @State private var error: String?
    @State private var hub: Hub = .all
    @State private var kspaceOnly = true
    @State private var origin: (id: Int, name: String)?
    @State private var galaxy: GalaxyData?
    @State private var jumps: [Int: Int] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Card(String(localized: "Thera / Turnur")) {
                    HStack(spacing: 6) {
                        ForEach(Hub.allCases, id: \.self) { h in
                            Button(h == .all ? String(localized: "Thera and Turnur") : h.rawValue) { hub = h }
                                .buttonStyle(CanopusButtonStyle(kind: hub == h ? .primary : .ghost, small: true))
                        }
                        Spacer(minLength: 4)
                        Button(kspaceOnly ? String(localized: "✓ K-space only") : String(localized: "K-space only")) { kspaceOnly.toggle() }
                            .buttonStyle(CanopusButtonStyle(kind: kspaceOnly ? .primary : .ghost, small: true))
                    }
                    SystemPicker(label: "Count jumps from", picked: $origin)
                    HStack {
                        Text("Data from EVE-Scout (eve-scout.com). Jumps: the shortest gate route to the exit system.")
                            .font(.ui(11)).foregroundStyle(C.faint)
                        Spacer(minLength: 4)
                        Button("Refresh") { Task { await load() } }.buttonStyle(.canopusSmall)
                    }
                }
                list
            }
            .padding(16)
        }
        .background(C.bg)
        .navigationTitle("Thera / Turnur")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .task(id: env.repositoryVersion) {
            if galaxy == nil { galaxy = try? await env.repository?.galaxy() }
        }
        .task(id: env.dataKey) {
            // Start from where the character is (esi-location).
            guard origin == nil, let svc = env.characterStore.selectedService, let loc = try? await svc.location(),
                  let s = try? await env.repository?.systems(ids: [loc.solarSystemId])[loc.solarSystemId] else { return }
            origin = (loc.solarSystemId, s.name)
        }
        .task(id: "\(origin?.id ?? 0)/\(signatures?.count ?? 0)/\(galaxy?.count ?? 0)") { countJumps() }
    }

    @ViewBuilder private var list: some View {
        if let error {
            Text(error).font(.ui(13)).foregroundStyle(C.bad)
        } else if let signatures {
            let shown = signatures
                .filter { $0.signatureType == nil || $0.signatureType == "wormhole" }
                .filter { hub == .all || $0.outSystemName == hub.rawValue }
                .filter { !kspaceOnly || $0.isKSpace }
                .sorted { (jumps[$0.inSystemId] ?? 999, -($0.remainingHours ?? 0)) < (jumps[$1.inSystemId] ?? 999, -($1.remainingHours ?? 0)) }
            Card {
                if shown.isEmpty { Text("No connections right now.").font(.ui(13)).foregroundStyle(C.muted) }
                ForEach(shown) { s in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(verbatim: s.inSystemName).font(.ui(14, .semibold)).foregroundStyle(C.text)
                            Text(verbatim: classLabel(s.inSystemClass)).font(.ui(11)).foregroundStyle(C.muted)
                            Text(verbatim: s.inRegionName ?? "").font(.ui(11)).foregroundStyle(C.muted).lineLimit(1)
                            Spacer(minLength: 4)
                            if let j = jumps[s.inSystemId] {
                                Text("\(j) j.").font(.mono(12, medium: true)).foregroundStyle(C.accentText)
                            }
                        }
                        HStack(spacing: 10) {
                            Text(verbatim: "\(s.outSystemName) \(s.outSignature) → \(s.inSignature ?? "?")")
                            Text(verbatim: shipSizeLabel(s.maxShipSize))
                            Spacer(minLength: 4)
                            if let h = s.remainingHours {
                                Text("\(Int(h)) h left").foregroundStyle(h <= 2 ? C.bad : C.muted)
                            }
                        }
                        .font(.mono(10)).foregroundStyle(C.muted)
                    }
                    .padding(.vertical, 4)
                }
            }
        } else {
            ProgressView().tint(C.accent).frame(maxWidth: .infinity)
        }
    }

    private func countJumps() {
        guard let g = galaxy, let origin, let signatures else { jumps = [:]; return }
        var out: [Int: Int] = [:]
        for id in Set(signatures.filter(\.isKSpace).map(\.inSystemId)) {
            if let r = MapLogic.route(g, from: origin.id, to: id, flag: "shortest", bridges: [], avoid: []) { out[id] = r.ids.count - 1 }
        }
        jumps = out
    }

    private func load() async {
        do {
            var request = URLRequest(url: URL(string: "https://api.eve-scout.com/v2/public/signatures")!)
            request.setValue(EVEConstants.userAgent, forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            signatures = try JSONDecoder().decode([ScoutSignature].self, from: data)
            error = nil
        } catch {
            if !error.isCancellation { self.error = error.localizedDescription }
        }
    }
}
