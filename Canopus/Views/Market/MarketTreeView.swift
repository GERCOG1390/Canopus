// The in-game market tree as the desktop's MarketTree: groups open in place (▸ / ▾, the group's game icon,
// how many items are under it), items in the game's order with the short meta badge (T2, F, D…) and ⓘ for
// Show Info. A level holding a single group and nothing else shows that group's contents instead.

import SwiftUI
import Domain
import EVEStaticData

@Observable private final class MarketTreeState {
    var expanded: Set<Int> = []
    var levels: [Int: MarketTreeLevel] = [:]
}

struct MarketTreeView: View {
    /// Tapping an item; the ⓘ button opens Show Info.
    let onPick: (ItemType) -> Void
    /// Whether rows carry the ⓘ button (off when picking already opens Show Info).
    var infoButton = true
    var selected: Int?
    @State private var state = MarketTreeState()
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TreeLevel(parent: nil, depth: 0, state: state, onPick: onPick, infoButton: infoButton, selected: selected)
        }
        // Open the groups leading to the selected item (e.g. picked from search).
        .task(id: "\(selected ?? 0)/\(env.repositoryVersion)") {
            guard let selected, let path = try? await env.repository?.marketPath(typeId: selected) else { return }
            state.expanded.formUnion(path)
        }
    }
}

private struct TreeLevel: View {
    let parent: Int?
    let depth: Int
    let state: MarketTreeState
    let onPick: (ItemType) -> Void
    let infoButton: Bool
    let selected: Int?
    @Environment(AppEnvironment.self) private var env

    private var indent: CGFloat { 4 + CGFloat(depth) * 14 }

    var body: some View {
        Group {
            if let level = state.levels[parent ?? 0] {
                if level.groups.count == 1, level.types.isEmpty {
                    TreeLevel(parent: level.groups[0].id, depth: depth, state: state, onPick: onPick, infoButton: infoButton, selected: selected)
                } else if level.groups.isEmpty, level.types.isEmpty {
                    Text("Nothing found").font(.ui(12)).foregroundStyle(C.muted).padding(.leading, indent).frame(minHeight: 32)
                } else {
                    ForEach(level.groups) { g in groupRow(g) }
                    ForEach(level.types) { t in typeRow(t) }
                }
            } else {
                Text(verbatim: "…").font(.ui(13)).foregroundStyle(C.muted).padding(.leading, indent + 18).frame(minHeight: 32)
                    .task(id: env.repositoryVersion) {
                        guard let repo = env.repository, let level = try? await repo.marketLevel(parent: parent) else { return }
                        state.levels[parent ?? 0] = level
                    }
            }
        }
    }

    @ViewBuilder private func groupRow(_ g: MarketNode) -> some View {
        let open = state.expanded.contains(g.id)
        Button {
            if open { state.expanded.remove(g.id) } else { state.expanded.insert(g.id) }
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: open ? "▾" : "▸").font(.ui(11)).foregroundStyle(C.muted).frame(width: 12)
                if let icon = g.iconId { EVEIconImage(iconId: icon, size: 22) } else { Color.clear.frame(width: 22, height: 22) }
                Text(verbatim: g.name).font(.ui(13, open ? .semibold : .regular)).foregroundStyle(open ? C.text : C.text.opacity(0.88)).lineLimit(1)
                Spacer(minLength: 4)
                Text(verbatim: "\(g.count)").font(.ui(11)).foregroundStyle(C.muted)
            }
            .padding(.leading, indent).padding(.trailing, 6)
            .frame(minHeight: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if open {
            TreeLevel(parent: g.id, depth: depth + 1, state: state, onPick: onPick, infoButton: infoButton, selected: selected)
        }
    }

    private func typeRow(_ t: ItemType) -> some View {
        HStack(spacing: 6) {
            Button { onPick(t) } label: {
                HStack(spacing: 6) {
                    EVETypeIcon(typeId: t.id, size: 26)
                    Text(verbatim: t.name).font(.ui(13)).foregroundStyle(selected == t.id ? C.accentText : C.text)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    MarketMetaBadge(metaGroupId: t.metaGroupId)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if infoButton {
                NavigationLink { TypeDetailView(typeId: t.id, typeName: t.name) } label: {
                    Text(verbatim: "i").font(.ui(12, .semibold)).italic().foregroundStyle(C.muted)
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(C.border))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, indent + 18).padding(.trailing, 6)
        .frame(minHeight: 36)
        .background(selected == t.id ? C.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// The desktop's short meta badge: T2, S (storyline), F (faction), O (officer), D (deadspace), T3; none for Tech I.
struct MarketMetaBadge: View {
    let metaGroupId: Int?

    var body: some View {
        if let meta = metaGroupId, let label = [2: "T2", 3: "S", 4: "F", 5: "O", 6: "D", 14: "T3"][meta] {
            let color: Color = switch meta {
            case 2: Color(hex: 0xF0B84A)
            case 4: Color(hex: 0x6FD26A)
            case 5, 6: Color(hex: 0xD88AE8)
            case 14: Color(hex: 0x6FB6F0)
            default: C.muted
            }
            Text(verbatim: label).font(.ui(11)).foregroundStyle(color)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(C.panel2, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(color.opacity(0.4)))
        }
    }
}

/// An item row as the tree shows it, for search results next to the tree.
struct MarketTypeRow: View {
    let type: ItemType

    var body: some View {
        HStack(spacing: 6) {
            EVETypeIcon(typeId: type.id, size: 26)
            Text(verbatim: type.name).font(.ui(13)).foregroundStyle(C.text).lineLimit(2).multilineTextAlignment(.leading)
            Spacer(minLength: 4)
            MarketMetaBadge(metaGroupId: type.metaGroupId)
        }
        .frame(minHeight: 36)
        .contentShape(Rectangle())
    }
}

/// Search by name (Russian or English) over the market tree, as the desktop's market panel and Ctrl+K item
/// search: while the field is empty the tree shows, otherwise the matching items.
struct ItemLookup: View {
    let onPick: (ItemType) -> Void
    var selected: Int?
    var infoButton = true
    /// Only items sold on the market (the Market page); the reference also finds the rest.
    var marketOnly = false
    var hint: LocalizedStringKey?
    @Environment(AppEnvironment.self) private var env
    @State private var query = ""
    @State private var hits: [ItemType] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Glyph(name: .search, size: 14).foregroundStyle(C.muted)
                TextField("Item name (Russian or English)…", text: $query)
                    .font(.ui(14)).autocorrectionDisabled().textInputAutocapitalization(.never)
                if !query.isEmpty {
                    Button { query = "" } label: { Text(verbatim: "✕").font(.ui(12)).foregroundStyle(C.muted) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).frame(minHeight: 40)
            .background(C.panel2, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(C.border))
            Card {
                if query.trimmingCharacters(in: .whitespaces).count >= 2 {
                    let shown = marketOnly ? hits.filter { $0.marketGroupId != nil } : hits
                    if shown.isEmpty {
                        Text("Nothing found").font(.ui(13)).foregroundStyle(C.muted)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(shown.prefix(60)) { t in
                            HStack(spacing: 6) {
                                Button { onPick(t) } label: { MarketTypeRow(type: t) }.buttonStyle(.plain)
                                if infoButton {
                                    NavigationLink { TypeDetailView(typeId: t.id, typeName: t.name) } label: {
                                        Text(verbatim: "i").font(.ui(12, .semibold)).italic().foregroundStyle(C.muted)
                                            .frame(width: 26, height: 26).overlay(Circle().stroke(C.border))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                } else {
                    MarketTreeView(onPick: onPick, infoButton: infoButton, selected: selected)
                }
                if let hint { Text(hint).font(.ui(11)).foregroundStyle(C.faint) }
            }
        }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2, let repo = env.repository else { hits = []; return }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            hits = (try? await repo.search(q)) ?? []
        }
    }
}
