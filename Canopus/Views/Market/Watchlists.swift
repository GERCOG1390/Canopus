// Market watchlists: named lists of items with quantities, priced at Jita (sell and buy) with the list's
// total — a shopping list for a fit or a doctrine, or the goods a trader follows. Items are added by
// search or pasted from the inventory; a list copies back out as "Name quantity" lines.

import SwiftUI
import Domain
import EVEStaticData

private struct Watchlist: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var items: [Entry]

    struct Entry: Codable, Hashable { let typeId: Int; var qty: Int }
}

private let watchKey = "market.watchlists"

private func loadLists() -> [Watchlist] {
    UserDefaults.standard.data(forKey: watchKey).flatMap { try? JSONDecoder().decode([Watchlist].self, from: $0) } ?? []
}

struct Watchlists: View {
    @Environment(AppEnvironment.self) private var env
    @State private var lists: [Watchlist] = {
        #if DEBUG
        // Debug builds: `-watchDemo YES` shows a sample list (screenshots).
        if UserDefaults.standard.bool(forKey: "watchDemo") {
            return [Watchlist(name: "Tengu", items: [.init(typeId: 29984, qty: 1), .init(typeId: 2048, qty: 2), .init(typeId: 24471, qty: 2000)])]
        }
        #endif
        return loadLists()
    }()
    @State private var current: UUID?
    @State private var names: [Int: String] = [:]
    @State private var prices: [Int: HubPrice] = [:]
    @State private var query = ""
    @State private var hits: [ItemType] = []
    @State private var pasteText = ""
    @State private var showPaste = false
    @State private var newName = ""
    @State private var copied = false

    private var index: Int? { lists.firstIndex { $0.id == (current ?? lists.first?.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card(String(localized: "Watchlists")) {
                FlowRow(spacing: 6) {
                    ForEach(lists) { l in
                        Button(l.name) { current = l.id }
                            .buttonStyle(CanopusButtonStyle(kind: l.id == lists[index ?? 0].id ? .primary : .ghost, small: true))
                    }
                }
                HStack(spacing: 6) {
                    TextField("New list name…", text: $newName).font(.ui(13))
                        .padding(.horizontal, 8).frame(minHeight: 32)
                        .background(C.panel2, in: RoundedRectangle(cornerRadius: 6))
                    Button("Create") {
                        let l = Watchlist(name: newName.trimmingCharacters(in: .whitespaces), items: [])
                        guard !l.name.isEmpty else { return }
                        lists.append(l)
                        current = l.id
                        newName = ""
                    }
                    .buttonStyle(.canopusSmall)
                }
            }
            if let i = index { listView(i) } else {
                Text("Create a list: a shopping list for a fit, a doctrine's ships, the goods you trade.").font(.ui(12)).foregroundStyle(C.muted)
            }
        }
        .onChange(of: lists) { _, new in
            if let data = try? JSONEncoder().encode(new) { UserDefaults.standard.set(data, forKey: watchKey) }
        }
        .task(id: "\(lists.flatMap { $0.items.map(\.typeId) }.sorted())/\(env.repositoryVersion)") { await loadPrices() }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2, let repo = env.repository else { hits = []; return }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            hits = Array(((try? await repo.search(q)) ?? []).filter { $0.marketGroupId != nil }.prefix(8))
        }
    }

    @ViewBuilder private func listView(_ i: Int) -> some View {
        let list = lists[i]
        let sell = list.items.reduce(0) { $0 + Double($1.qty) * (prices[$1.typeId]?.sell ?? 0) }
        let buy = list.items.reduce(0) { $0 + Double($1.qty) * (prices[$1.typeId]?.buy ?? 0) }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            StatTile(label: "Buy now (Jita sell)", value: Fmt.isk(sell), sub: String(localized: "\(list.items.count) items"))
            StatTile(label: "Sell now (Jita buy)", value: Fmt.isk(buy))
        }
        Card(list.name) {
            FlowRow(spacing: 6) {
                Button(copied ? String(localized: "Copied") : String(localized: "Copy")) { copy(list) }.buttonStyle(.canopusSmall)
                Button("Paste list") { showPaste.toggle() }.buttonStyle(.canopusSmall)
                Button("Delete list") { lists.remove(at: i); current = lists.first?.id }.buttonStyle(.canopusSmall)
            }
            if showPaste {
                TextEditor(text: $pasteText).font(.mono(12)).scrollContentBackground(.hidden).frame(minHeight: 90)
                    .padding(6).background(C.panel2, in: RoundedRectangle(cornerRadius: 8))
                Button("Add to the list") { Task { await paste(into: i) } }.buttonStyle(CanopusButtonStyle(kind: .primary, small: true))
            }
            HStack(spacing: 8) {
                Glyph(name: .search, size: 14).foregroundStyle(C.muted)
                TextField("+ item…", text: $query).font(.ui(14)).autocorrectionDisabled().textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 10).frame(minHeight: 36)
            .background(C.panel2, in: RoundedRectangle(cornerRadius: 8))
            ForEach(hits) { t in
                Button { add(t.id, qty: 1, to: i); names[t.id] = t.name; query = "" } label: { MarketTypeRow(type: t) }.buttonStyle(.plain)
            }
            if list.items.isEmpty { Text("No items yet.").font(.ui(12)).foregroundStyle(C.muted) }
            ForEach(Array(list.items.enumerated()), id: \.element.typeId) { k, e in
                HStack(spacing: 6) {
                    EVETypeIcon(typeId: e.typeId, size: 24)
                    NavigationLink { TypeMarketView(typeId: e.typeId, name: names[e.typeId] ?? "") } label: {
                        Text(verbatim: names[e.typeId] ?? "#\(e.typeId)").font(.ui(13)).foregroundStyle(C.accentText).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 4)
                    TextField("", value: Binding(get: { lists[i].items[k].qty }, set: { lists[i].items[k].qty = max(1, $0) }), format: .number)
                        .keyboardType(.numberPad).font(.mono(12)).multilineTextAlignment(.trailing)
                        .frame(width: 70).padding(.horizontal, 6).padding(.vertical, 3)
                        .background(C.card, in: RoundedRectangle(cornerRadius: 5))
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(verbatim: Fmt.isk(Double(e.qty) * (prices[e.typeId]?.sell ?? 0))).font(.mono(12, medium: true)).foregroundStyle(C.text)
                        Text(verbatim: prices[e.typeId].map { "\(Fmt.isk($0.sell, compact: false)) / \(Fmt.isk($0.buy, compact: false))" } ?? "—")
                            .font(.mono(9)).foregroundStyle(C.muted)
                    }
                    .frame(minWidth: 96, alignment: .trailing)
                    Button { lists[i].items.remove(at: k) } label: { Text(verbatim: "✕").font(.ui(12)).foregroundStyle(C.muted) }.buttonStyle(.plain)
                }
            }
            Text("Price per unit: Jita sell / buy.").font(.ui(11)).foregroundStyle(C.faint)
        }
    }

    private func add(_ typeId: Int, qty: Int, to i: Int) {
        if let k = lists[i].items.firstIndex(where: { $0.typeId == typeId }) { lists[i].items[k].qty += qty } else {
            lists[i].items.append(.init(typeId: typeId, qty: qty))
        }
    }

    private func paste(into i: Int) async {
        guard let repo = env.repository else { return }
        for (name, qty) in parseItemList(pasteText) {
            if let t = try? await repo.type(named: name) { add(t.id, qty: qty, to: i); names[t.id] = t.name }
        }
        pasteText = ""
        showPaste = false
    }

    private func copy(_ list: Watchlist) {
        UIPasteboard.general.string = list.items.map { "\(names[$0.typeId] ?? "\($0.typeId)") \($0.qty)" }.joined(separator: "\n")
        copied = true
        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
    }

    private func loadPrices() async {
        let ids = Set(lists.flatMap { $0.items.map(\.typeId) })
        guard !ids.isEmpty else { return }
        let missing = ids.filter { names[$0] == nil }
        if !missing.isEmpty, let repo = env.repository {
            names.merge(((try? await repo.types(ids: missing)) ?? [:]).mapValues(\.name)) { _, new in new }
        }
        prices = (try? await HubPrices.hub(station: HubPrices.jitaStation, typeIds: ids)) ?? prices
    }
}
