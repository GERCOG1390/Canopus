// Assets as the desktop's character/Assets.tsx: valued at Jita sell (blueprint copies count as nothing),
// grouped by the place they sit in (items inside ships and containers go to their station), search by
// place or item in either language, the richest places first.

import SwiftUI
import Domain
import EVEAuth
import EVEStaticData

struct AssetsTab: View {
    let characterService: CharacterService
    @Environment(AppEnvironment.self) private var env

    private struct Group: Identifiable {
        let id: Int
        var name = ""
        var items: [Int: (qty: Int, value: Double)] = [:]
        var value = 0.0
        var count = 0
    }

    @State private var groups: [Group]?
    @State private var total = 0.0
    @State private var stacks = 0
    @State private var typeNames: [Int: String] = [:]
    /// Lower-cased names for the search, made once per load rather than on every keystroke.
    @State private var searchNames: [Int: String] = [:]
    @State private var filter = ""
    @State private var open: Int?
    @State private var error: Error?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error {
                    Text(error.localizedDescription).font(.ui(13)).foregroundStyle(C.bad)
                } else if let groups {
                    content(groups)
                } else {
                    VStack(spacing: 8) {
                        ProgressView().tint(C.accent)
                        Text("Loading assets and prices…").font(.ui(12)).foregroundStyle(C.muted)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 30)
                }
            }
            .padding(16)
        }
        .refreshable { await load() }
        .task(id: env.dataKey) { await load() }
    }

    @ViewBuilder private func content(_ groups: [Group]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            StatTile(label: "Value (Jita sell)", value: Fmt.isk(total), sub: String(localized: "blueprint copies not counted"))
            StatTile(label: "Items (stacks)", value: stacks.formatted())
            StatTile(label: "Locations", value: groups.count.formatted())
        }
        HStack(spacing: 8) {
            Glyph(name: .search, size: 14).foregroundStyle(C.muted)
            TextField("Search by place or item (Russian or English)…", text: $filter)
                .font(.ui(14)).autocorrectionDisabled().textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 12).frame(minHeight: 40)
        .background(C.panel2, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(C.border))
        let f = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let matches = { (id: Int) in searchNames[id]?.contains(f) ?? false }
        let visible = groups.filter { f.isEmpty || $0.name.lowercased().contains(f) || $0.items.keys.contains(where: matches) }
        Card {
            if visible.isEmpty { Text("Nothing found").font(.ui(13)).foregroundStyle(C.muted) }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(visible) { g in
                    let isOpen = open == g.id || (!f.isEmpty && visible.count <= 3)
                    Button { open = open == g.id ? nil : g.id } label: {
                        HStack(spacing: 6) {
                            Text(verbatim: isOpen ? "▾" : "▸").font(.ui(11)).foregroundStyle(C.muted).frame(width: 12)
                            Text(verbatim: g.name).font(.ui(13, isOpen ? .semibold : .regular)).foregroundStyle(C.text).lineLimit(2).multilineTextAlignment(.leading)
                            Spacer(minLength: 6)
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(verbatim: Fmt.isk(g.value)).font(.mono(12, medium: true)).foregroundStyle(C.text)
                                Text("\(g.count) stacks").font(.ui(10)).foregroundStyle(C.muted)
                            }
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if isOpen {
                        let byName = f.isEmpty || g.name.lowercased().contains(f)
                        ForEach(g.items.filter { byName || matches($0.key) }.sorted { $0.value.value > $1.value.value }.prefix(500), id: \.key) { id, it in
                            NavigationLink { TypeDetailView(typeId: id, typeName: typeNames[id] ?? "") } label: {
                                HStack(spacing: 6) {
                                    EVETypeIcon(typeId: id, size: 22)
                                    Text(verbatim: typeNames[id] ?? "#\(id)").font(.ui(12)).foregroundStyle(C.accentText).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text(verbatim: "×\(it.qty.formatted())").font(.mono(11)).foregroundStyle(C.muted)
                                    Text(verbatim: Fmt.isk(it.value)).font(.mono(11)).foregroundStyle(C.text).frame(minWidth: 70, alignment: .trailing)
                                }
                                .padding(.leading, 18).padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Rectangle().fill(C.border).frame(height: 1)
                }
            }
        }
    }

    private func load() async {
        do {
            let assets = try await characterService.assets()
            let byItem = Dictionary(assets.map { ($0.itemId, $0) }, uniquingKeysWith: { a, _ in a })
            func root(_ a: ESIAsset) -> Int {
                var cur = a
                for _ in 0..<10 { guard let parent = byItem[cur.locationId] else { break }; cur = parent }
                return cur.locationId
            }
            let typeIds = Set(assets.map(\.typeId))
            let prices = (try? await HubPrices.jitaSell(typeIds: typeIds)) ?? [:]
            var out: [Int: Group] = [:]
            var sum = 0.0
            for a in assets {
                let r = root(a)
                var g = out[r] ?? Group(id: r)
                let unit = a.isBlueprintCopy == true ? 0 : prices[a.typeId] ?? 0
                let v = unit * Double(a.quantity)
                let it = g.items[a.typeId] ?? (0, 0)
                g.items[a.typeId] = (it.qty + a.quantity, it.value + v)
                g.value += v
                g.count += 1
                sum += v
                out[r] = g
            }
            typeNames = ((try? await env.repository?.types(ids: typeIds)) ?? [:]).mapValues(\.name)
            searchNames = typeNames.mapValues { $0.lowercased() }
            let names = await LocationNames.resolve(out.keys, service: characterService)
            for k in out.keys { out[k]?.name = names[k] ?? String(localized: "Location \(k)") }
            total = sum
            stacks = assets.count
            groups = out.values.sorted { $0.value > $1.value }
            error = nil
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }
}
