// Item comparison: any items side by side, attribute by attribute in the info screen's categories, with
// "only differences". Items come from the search here or the "Compare" button on an item's info.

import SwiftUI
import Domain
import EVEStaticData

/// The items being compared, kept between launches.
@Observable
final class CompareStore {
    static let shared = CompareStore()
    private static let key = "compare.items"

    private(set) var ids: [Int] = {
        #if DEBUG
        // Debug builds: `-compareTypes 2048,2046` sets the list (screenshots).
        if let list = UserDefaults.standard.string(forKey: "compareTypes") { return list.split(separator: ",").compactMap { Int($0) } }
        #endif
        return (UserDefaults.standard.array(forKey: key) as? [Int]) ?? []
    }()

    func add(_ id: Int) {
        guard !ids.contains(id) else { return }
        ids.append(id)
        save()
    }

    func remove(_ id: Int) {
        ids.removeAll { $0 == id }
        save()
    }

    func clear() {
        ids = []
        save()
    }

    private func save() { UserDefaults.standard.set(ids, forKey: Self.key) }
}

struct CompareView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var store = CompareStore.shared
    @State private var bundles: [Int: TypeInfoBundle] = [:]
    @State private var onlyDifferences = true
    @State private var query = ""
    @State private var hits: [ItemType] = []

    private static var russian: Bool { Locale.current.language.languageCode?.identifier == "ru" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Glyph(name: .search, size: 14).foregroundStyle(C.muted)
                TextField("+ item to compare…", text: $query).font(.ui(14)).autocorrectionDisabled().textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 10).frame(minHeight: 38)
            .background(C.panel2, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(C.border))
            ForEach(hits) { t in
                Button { store.add(t.id); query = "" } label: { MarketTypeRow(type: t) }.buttonStyle(.plain)
            }
            if store.ids.count < 2 {
                Text("Add at least two items: search here or tap “Compare” on an item's info.").font(.ui(12)).foregroundStyle(C.muted)
            }
            if !store.ids.isEmpty {
                HStack(spacing: 6) {
                    Button(onlyDifferences ? "✓ Only differences" : "Only differences") { onlyDifferences.toggle() }
                        .buttonStyle(CanopusButtonStyle(kind: onlyDifferences ? .primary : .ghost, small: true))
                    Spacer()
                    Button("Clear") { store.clear() }.buttonStyle(.canopusSmall)
                }
                table
            }
        }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2, let repo = env.repository else { hits = []; return }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            hits = Array(((try? await repo.search(q)) ?? []).prefix(8))
        }
        .task(id: "\(store.ids)/\(env.repositoryVersion)") {
            guard let repo = env.repository else { return }
            for id in store.ids where bundles[id] == nil {
                if let b = try? await repo.typeInfo(id: id, russian: Self.russian) { bundles[id] = b }
            }
        }
    }

    private struct Row: Hashable { let id: Int; let name: String }

    private var table: some View {
        let items = store.ids.compactMap { bundles[$0] }
        // Attributes in the info screen's categories, in the order the items list them; references to
        // other types (skills, groups) belong to the requirements, not here.
        var order: [String] = []
        var rows: [String: [Row]] = [:]
        var seen: Set<Int> = []
        for b in items {
            for a in b.attributes where ![115, 116, 119].contains(a.unit ?? 0) && seen.insert(a.id).inserted {
                if rows[a.category] == nil { order.append(a.category) }
                rows[a.category, default: []].append(Row(id: a.id, name: a.name))
            }
        }
        let values: [Int: [Int: TypeInfoBundle.Attribute]] = Dictionary(uniqueKeysWithValues: items.map { b in
            (b.typeId, Dictionary(b.attributes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }))
        })
        let differs = { (attr: Int) in Set(items.map { b in values[b.typeId]?[attr].map { "\($0.value)" } ?? "—" }).count > 1 }
        let nameWidth: CGFloat = 170, colWidth: CGFloat = 120
        return ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    Color.clear.frame(width: nameWidth, height: 1)
                    ForEach(items, id: \.typeId) { b in
                        VStack(spacing: 4) {
                            EVETypeIcon(typeId: b.typeId, size: 34)
                            Text(verbatim: b.name).font(.ui(11, .medium)).foregroundStyle(C.text).multilineTextAlignment(.center).lineLimit(3)
                            Button { store.remove(b.typeId); bundles[b.typeId] = nil } label: { Text(verbatim: "✕").font(.ui(11)).foregroundStyle(C.muted) }
                                .buttonStyle(.plain)
                        }
                        .frame(width: colWidth)
                    }
                }
                .padding(.bottom, 8)
                ForEach(order, id: \.self) { cat in
                    let list = (rows[cat] ?? []).filter { !onlyDifferences || differs($0.id) }
                    if !list.isEmpty {
                        Text(String(localized: String.LocalizationValue(attributeCategoryKey[cat] ?? cat)))
                            .font(.ui(11, .medium)).textCase(.uppercase).tracking(1.2).foregroundStyle(C.muted)
                            .padding(.top, 10).padding(.bottom, 4)
                        ForEach(list, id: \.id) { row in
                            HStack(spacing: 0) {
                                Text(verbatim: row.name).font(.ui(12)).foregroundStyle(C.text2).lineLimit(2)
                                    .frame(width: nameWidth, alignment: .leading)
                                ForEach(items, id: \.typeId) { b in
                                    let a = values[b.typeId]?[row.id]
                                    Text(verbatim: a.map { formatValue($0.value, unit: $0.unit, unitName: $0.unitName) } ?? "—")
                                        .font(.mono(12, medium: a != nil)).foregroundStyle(a == nil ? C.faint : C.text)
                                        .frame(width: colWidth)
                                }
                            }
                            .padding(.vertical, 4)
                            .background(differs(row.id) ? C.accent.opacity(0.06) : .clear)
                            Rectangle().fill(C.border).frame(height: 1)
                        }
                    }
                }
            }
            .padding(12)
        }
        .canopusSurface(padding: nil)
    }
}
