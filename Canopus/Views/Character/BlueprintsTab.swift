// The blueprint library as the desktop's character/Blueprints.tsx: this character's blueprints or every
// logged-in character's, searchable by the blueprint or by what it makes ("do I have a blueprint for X?"),
// originals and copies, ME / TE / runs and where it is; identical blueprints in one place on one row.

import SwiftUI
import Domain
import EVEAuth
import EVEStaticData

struct BlueprintsTab: View {
    let characterService: CharacterService
    @Environment(AppEnvironment.self) private var env

    private struct Row: Identifiable {
        let id: String
        let bp: ESIBlueprint
        let character: Int
        var count: Int
    }

    private enum Kind: Hashable { case all, bpo, bpc }

    @State private var rows: [Row]?
    @State private var products: [Int: Int] = [:]
    @State private var names: [Int: String] = [:]
    @State private var places: [Int: String] = [:]
    @State private var filter = ""
    @State private var kind: Kind = .all
    @State private var everyone = false
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if failed {
                    ScopeHint(scope: "esi-characters.read_blueprints.v1")
                } else if let rows {
                    content(rows)
                } else {
                    ProgressView().tint(C.accent).frame(maxWidth: .infinity).padding(.top, 30)
                }
            }
            .padding(16)
        }
        .task(id: "\(env.dataKey)/\(everyone)") { await load() }
    }

    @ViewBuilder private func content(_ rows: [Row]) -> some View {
        let bpo = rows.filter { $0.bp.runs == -1 }.reduce(0) { $0 + $1.count }
        let bpc = rows.filter { $0.bp.runs != -1 }.reduce(0) { $0 + $1.count }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            StatTile(label: "Originals (BPO)", value: bpo.formatted())
            StatTile(label: "Copies (BPC)", value: bpc.formatted())
        }
        HStack(spacing: 8) {
            Glyph(name: .search, size: 14).foregroundStyle(C.muted)
            TextField("Blueprint or what it makes…", text: $filter).font(.ui(14)).autocorrectionDisabled().textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 12).frame(minHeight: 40)
        .background(C.panel2, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(C.border))
        HStack(spacing: 6) {
            ForEach([(Kind.all, String(localized: "All")), (.bpo, String(localized: "Originals only")), (.bpc, String(localized: "Copies only"))], id: \.0) { k, label in
                Button(label) { kind = k }.buttonStyle(CanopusButtonStyle(kind: kind == k ? .primary : .ghost, small: true))
            }
            Spacer(minLength: 4)
            if env.characterStore.characters.count > 1 {
                Button(everyone ? "✓ All characters" : "All characters") { everyone.toggle() }
                    .buttonStyle(CanopusButtonStyle(kind: everyone ? .primary : .ghost, small: true))
            }
        }
        let f = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let matches = { (id: Int?) in id.map { (names[$0] ?? "").lowercased().contains(f) } ?? false }
        let list = rows
            .filter { kind == .all || (kind == .bpo ? $0.bp.runs == -1 : $0.bp.runs != -1) }
            .filter { f.isEmpty || matches($0.bp.typeId) || matches(products[$0.bp.typeId]) }
            .sorted { (names[$0.bp.typeId] ?? "") < (names[$1.bp.typeId] ?? "") }
        Card {
            if list.isEmpty { Text(f.isEmpty ? "No blueprints" : "Nothing found").font(.ui(13)).foregroundStyle(C.muted) }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(list) { r in
                    row(r)
                    Rectangle().fill(C.border).frame(height: 1)
                }
            }
        }
    }

    private func row(_ r: Row) -> some View {
        let b = r.bp
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                EVETypeIcon(typeId: b.typeId, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    NavigationLink { TypeDetailView(typeId: b.typeId, typeName: names[b.typeId] ?? "") } label: {
                        Text(verbatim: names[b.typeId] ?? "#\(b.typeId)").font(.ui(13)).foregroundStyle(C.accentText).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    if let p = products[b.typeId] {
                        Text(verbatim: "→ " + (names[p] ?? "#\(p)")).font(.ui(11)).foregroundStyle(C.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Text(verbatim: b.runs == -1 ? "BPO" : "BPC").font(.ui(11)).foregroundStyle(b.runs == -1 ? C.text : C.accentText)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(C.panel2, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(C.border))
            }
            HStack(spacing: 10) {
                Text(verbatim: "ME \(b.materialEfficiency)% · TE \(b.timeEfficiency)%")
                Text(verbatim: b.runs == -1 ? "∞" : String(localized: "runs \(b.runs)"))
                if r.count > 1 { Text(verbatim: "×\(r.count)") }
                Spacer(minLength: 4)
                if everyone { Text(verbatim: env.characterStore.characters.first { $0.characterId == r.character }?.characterName ?? "") }
                Text(verbatim: places[b.locationId] ?? String(localized: "in a container")).lineLimit(1)
            }
            .font(.mono(10)).foregroundStyle(C.muted)
        }
        .padding(.vertical, 6)
    }

    private func load() async {
        let services = everyone ? env.characterStore.services : [characterService]
        var groups: [String: Row] = [:]
        var locations: [Int: String] = [:]
        var anyOK = false
        for s in services {
            guard let bps = try? await s.blueprints() else { continue }
            anyOK = true
            let cid = s.tokens.characterId
            for b in bps {
                let key = "\(cid):\(b.typeId):\(b.materialEfficiency):\(b.timeEfficiency):\(b.runs):\(b.locationId)"
                if groups[key] != nil { groups[key]!.count += 1 } else { groups[key] = Row(id: key, bp: b, character: cid, count: 1) }
            }
            // Blueprints in containers point at the container: walk up the assets to its station.
            let assets = Dictionary(((try? await s.assets()) ?? []).map { ($0.itemId, $0.locationId) }, uniquingKeysWith: { a, _ in a })
            func root(_ id: Int) -> Int {
                var cur = id
                for _ in 0..<10 { guard let up = assets[cur] else { break }; cur = up }
                return cur
            }
            let roots = Dictionary(bps.map { ($0.locationId, root($0.locationId)) }, uniquingKeysWith: { a, _ in a })
            let resolved = await LocationNames.resolve(Set(roots.values), service: s)
            for (loc, r) in roots { if let n = resolved[r] { locations[loc] = n } }
        }
        failed = !anyOK
        guard anyOK else { return }
        let list = Array(groups.values)
        let bpIds = Set(list.map(\.bp.typeId))
        products = (try? await env.repository?.blueprintProducts(bpIds)) ?? [:]
        names = ((try? await env.repository?.types(ids: bpIds.union(products.values))) ?? [:]).mapValues(\.name)
        places = locations
        rows = list
    }
}
