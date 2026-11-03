// People and corporations: find any character, corporation or alliance by part of the name (ESI search,
// esi-search.search_structures.v1) and open its public card — corporation and alliance, history, members,
// and a pilot's zKillboard record.

import SwiftUI
import EVEAuth

enum EntityKind: String, Hashable { case character, corporation, alliance }

struct EntityRef: Hashable {
    let kind: EntityKind
    let id: Int
}

private struct EntityLogo: View {
    let ref: EntityRef
    var size: CGFloat = 32
    var body: some View {
        switch ref.kind {
        case .character: EVECharacterPortrait(characterId: ref.id, size: size).clipShape(RoundedRectangle(cornerRadius: size * 0.18))
        case .corporation: EVECorpLogo(corpId: ref.id, size: size)
        case .alliance: EVEAllianceLogo(allianceId: ref.id, size: size)
        }
    }
}

/// A row that opens the entity's card.
private struct EntityLink: View {
    let ref: EntityRef
    let name: String
    var sub: String? = nil

    var body: some View {
        NavigationLink(value: ref) {
            HStack(spacing: 8) {
                EntityLogo(ref: ref, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: name).font(.ui(13, .medium)).foregroundStyle(C.accentText).lineLimit(1)
                    if let sub { Text(verbatim: sub).font(.ui(11)).foregroundStyle(C.muted).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct EntitySearchPage: View {
    @Environment(AppEnvironment.self) private var env
    @State private var query: String = {
        #if DEBUG
        // Debug builds: `-peopleQuery goon` searches at launch (screenshots).
        return UserDefaults.standard.string(forKey: "peopleQuery") ?? ""
        #else
        return ""
        #endif
    }()
    /// Debug builds: `-peopleOpen alliance:1354830081` opens a card at launch (screenshots).
    @State private var opened: EntityRef? = {
        #if DEBUG
        let parts = (UserDefaults.standard.string(forKey: "peopleOpen") ?? "").split(separator: ":")
        if parts.count == 2, let kind = EntityKind(rawValue: String(parts[0])), let id = Int(parts[1]) { return EntityRef(kind: kind, id: id) }
        #endif
        return nil
    }()
    @State private var results: [EntityKind: [(id: Int, name: String)]] = [:]
    @State private var searching = false
    @State private var error: Error?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Glyph(name: .search, size: 14).foregroundStyle(C.muted)
                    TextField("Character, corporation or alliance…", text: $query)
                        .font(.ui(14)).autocorrectionDisabled().textInputAutocapitalization(.never)
                    if searching { ProgressView().controlSize(.small).tint(C.accent) }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(C.card, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(C.border, lineWidth: 1))
                if env.characterStore.selectedService == nil {
                    Text("Sign in with a character: ESI search works on behalf of a character.").font(.ui(13)).foregroundStyle(C.muted)
                } else if error != nil {
                    ScopeHint(scope: "esi-search.search_structures.v1")
                } else if query.trimmingCharacters(in: .whitespaces).count < 3 {
                    EmptyState("Find anyone in New Eden", icon: "win_contacts") { Text("At least three letters of a name.") }
                } else if !searching, results.values.allSatisfy(\.isEmpty) {
                    Text("Nothing found.").font(.ui(13)).foregroundStyle(C.muted)
                }
                // Alliances and corporations first: fewer, and usually what a short name is after.
                section(.alliance, title: String(localized: "Alliances"))
                section(.corporation, title: String(localized: "Corporations"))
                section(.character, title: String(localized: "Characters"))
            }
            .padding(16)
        }
        .background(C.bg)
        .navigationTitle("People & corporations")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: EntityRef.self) { EntityCard(ref: $0) }
        .navigationDestination(item: $opened) { EntityCard(ref: $0) }
        .task(id: query) { await search() }
    }

    @ViewBuilder private func section(_ kind: EntityKind, title: String) -> some View {
        if let list = results[kind], !list.isEmpty {
            Card("\(title): \(list.count)") {
                ForEach(list, id: \.id) { e in EntityLink(ref: EntityRef(kind: kind, id: e.id), name: e.name) }
            }
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3, let svc = env.characterStore.selectedService else { results = [:]; return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        do {
            let r = try await svc.search(q)
            // ESI returns up to 500 per category: the first 50 by name are plenty on a phone.
            let ids = [(EntityKind.character, r.character ?? []), (.corporation, r.corporation ?? []), (.alliance, r.alliance ?? [])]
            let names = (try? await MarketService().names(ids: ids.flatMap { Array($0.1.prefix(200)) })) ?? [:]
            guard !Task.isCancelled else { return }
            var out: [EntityKind: [(id: Int, name: String)]] = [:]
            let lower = q.lowercased()
            for (kind, list) in ids {
                // Names starting with the text first, then alphabetical.
                out[kind] = list.prefix(200).compactMap { id -> (id: Int, name: String)? in names[id].map { (id: id, name: $0) } }
                    .sorted { a, b in
                        let pa = a.name.lowercased().hasPrefix(lower), pb = b.name.lowercased().hasPrefix(lower)
                        return pa != pb ? pa : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                    }
                    .prefix(50).map { $0 }
            }
            results = out
            error = nil
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }
}

// MARK: - Cards

struct EntityCard: View {
    let ref: EntityRef
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let svc = env.characterStore.selectedService {
                    switch ref.kind {
                    case .character: CharacterCard(id: ref.id, svc: svc)
                    case .corporation: CorporationCard(id: ref.id, svc: svc)
                    case .alliance: AllianceCard(id: ref.id, svc: svc)
                    }
                }
            }
            .padding(16)
        }
        .background(C.bg)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct InfoLine: View {
    let label: LocalizedStringKey
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.ui(12)).foregroundStyle(C.muted)
            Spacer(minLength: 8)
            Text(verbatim: value).font(.ui(13)).foregroundStyle(C.text).multilineTextAlignment(.trailing)
        }
    }
}

private struct Header: View {
    let ref: EntityRef
    let title: String
    let sub: String?
    var body: some View {
        HStack(spacing: 12) {
            EntityLogo(ref: ref, size: 72)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title).font(.display(20)).foregroundStyle(C.text)
                if let sub { Text(verbatim: sub).font(.ui(12)).foregroundStyle(C.muted) }
            }
            Spacer(minLength: 0)
        }
    }
}

private func descriptionCard(_ text: String?) -> some View {
    let plain = (text ?? "").strippedEVEHTML.trimmingCharacters(in: .whitespacesAndNewlines)
    return Group {
        if !plain.isEmpty {
            Card(String(localized: "Description")) {
                Text(verbatim: plain).font(.ui(13)).foregroundStyle(C.text2).textSelection(.enabled)
            }
        }
    }
}

private struct CharacterCard: View {
    let id: Int
    let svc: CharacterService
    @State private var info: ESICharacterInfo?
    @State private var corp: ESICorporationInfo?
    @State private var alliance: ESIAllianceInfo?
    @State private var history: [ESIEmploymentHistoryItem] = []
    @State private var names: [Int: String] = [:]
    @State private var error: String?

    var body: some View {
        if let info {
            Card {
                Header(ref: EntityRef(kind: .character, id: id), title: info.name,
                       sub: info.birthday.map { String(localized: "Born \($0.formatted(date: .long, time: .omitted))") })
                if let s = info.securityStatus {
                    HStack {
                        Text("Security status").font(.ui(12)).foregroundStyle(C.muted)
                        Spacer()
                        Text(verbatim: String(format: "%.2f", s)).font(.mono(13, medium: true)).foregroundStyle(C.sec(s))
                    }
                }
                EntityLink(ref: EntityRef(kind: .corporation, id: info.corporationId), name: corp.map { "\($0.name) [\($0.ticker)]" } ?? "…",
                           sub: String(localized: "Corporation"))
                if let a = info.allianceId {
                    EntityLink(ref: EntityRef(kind: .alliance, id: a), name: alliance.map { "\($0.name) <\($0.ticker)>" } ?? "…", sub: String(localized: "Alliance"))
                }
                NavigationLink {
                    ScrollView { PilotBoardContent(pilotId: id, name: info.name).padding(16) }.background(C.bg)
                } label: {
                    HStack(spacing: 6) {
                        Image("win_killreport").resizable().frame(width: 20, height: 20)
                        Text("Kills and losses (zKillboard)").font(.ui(13, .medium)).foregroundStyle(C.accentText)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            descriptionCard(info.description)
            if !history.isEmpty {
                Card(String(localized: "Employment history")) {
                    ForEach(history) { h in
                        EntityLink(ref: EntityRef(kind: .corporation, id: h.corporationId), name: names[h.corporationId] ?? "#\(h.corporationId)",
                                   sub: h.startDate.formatted(date: .abbreviated, time: .omitted))
                    }
                }
            }
        } else if let error {
            Text(error).font(.ui(13)).foregroundStyle(C.bad)
        } else {
            ProgressView().tint(C.accent).frame(maxWidth: .infinity).padding(.top, 30)
                .task { await load() }
        }
    }

    private func load() async {
        do {
            let i = try await svc.characterInfo(id: id)
            corp = try? await svc.corporationInfo(corpId: i.corporationId)
            if let a = i.allianceId { alliance = try? await svc.allianceInfo(allianceId: a) }
            history = ((try? await svc.corporationHistory(characterId: id)) ?? []).sorted { $0.startDate > $1.startDate }
            names = (try? await MarketService().names(ids: history.map(\.corporationId))) ?? [:]
            info = i
        } catch {
            if !error.isCancellation { self.error = error.localizedDescription }
        }
    }
}

private struct CorporationCard: View {
    let id: Int
    let svc: CharacterService
    @State private var info: ESICorporationInfo?
    @State private var alliance: ESIAllianceInfo?
    @State private var ceo: String?
    @State private var error: String?

    var body: some View {
        if let info {
            Card {
                Header(ref: EntityRef(kind: .corporation, id: id), title: info.name, sub: "[\(info.ticker)]")
                if let a = info.allianceId {
                    EntityLink(ref: EntityRef(kind: .alliance, id: a), name: alliance.map { "\($0.name) <\($0.ticker)>" } ?? "…", sub: String(localized: "Alliance"))
                }
                if let c = info.ceoId, c > 1 {
                    EntityLink(ref: EntityRef(kind: .character, id: c), name: ceo ?? "…", sub: String(localized: "CEO"))
                }
                if let m = info.memberCount { InfoLine(label: "Members", value: m.formatted()) }
                if let d = info.dateFounded { InfoLine(label: "Founded", value: d.formatted(date: .long, time: .omitted)) }
                if let t = info.taxRate { InfoLine(label: "Tax rate", value: "\(Int((t * 100).rounded()))%") }
                if let u = info.url, let url = URL(string: u), !u.isEmpty, url.scheme?.hasPrefix("http") == true {
                    Link(destination: url) { Text(verbatim: u).font(.ui(12)).foregroundStyle(C.accentText).lineLimit(1) }
                }
            }
            descriptionCard(info.description)
        } else if let error {
            Text(error).font(.ui(13)).foregroundStyle(C.bad)
        } else {
            ProgressView().tint(C.accent).frame(maxWidth: .infinity).padding(.top, 30)
                .task { await load() }
        }
    }

    private func load() async {
        do {
            let i = try await svc.corporationInfo(corpId: id)
            if let a = i.allianceId { alliance = try? await svc.allianceInfo(allianceId: a) }
            if let c = i.ceoId, c > 1 { ceo = try? await svc.characterInfo(id: c).name }
            info = i
        } catch {
            if !error.isCancellation { self.error = error.localizedDescription }
        }
    }
}

private struct AllianceCard: View {
    let id: Int
    let svc: CharacterService
    @State private var info: ESIAllianceInfo?
    @State private var corps: [(id: Int, name: String, members: Int)] = []
    @State private var corpCount = 0
    @State private var error: String?

    var body: some View {
        if let info {
            Card {
                Header(ref: EntityRef(kind: .alliance, id: id), title: info.name, sub: "<\(info.ticker)>")
                if let d = info.dateFounded { InfoLine(label: "Founded", value: d.formatted(date: .long, time: .omitted)) }
                if !corps.isEmpty {
                    InfoLine(label: "Corporations", value: corpCount.formatted())
                    if corpCount <= corps.count { InfoLine(label: "Members", value: corps.reduce(0) { $0 + $1.members }.formatted()) }
                }
                if let e = info.executorCorporationId, let c = corps.first(where: { $0.id == e }) {
                    EntityLink(ref: EntityRef(kind: .corporation, id: e), name: c.name, sub: String(localized: "Executor"))
                }
            }
            if !corps.isEmpty {
                Card(String(localized: "Member corporations")) {
                    ForEach(corps.prefix(100), id: \.id) { c in
                        EntityLink(ref: EntityRef(kind: .corporation, id: c.id), name: c.name, sub: String(localized: "\(c.members) members"))
                    }
                }
            }
        } else if let error {
            Text(error).font(.ui(13)).foregroundStyle(C.bad)
        } else {
            ProgressView().tint(C.accent).frame(maxWidth: .infinity).padding(.top, 30)
                .task { await load() }
        }
    }

    private func load() async {
        do {
            let i = try await svc.allianceInfo(allianceId: id)
            let ids = (try? await svc.allianceCorporations(allianceId: id)) ?? []
            // Member counts for the largest alliances take a request per corporation: the first 100.
            var list: [(Int, String, Int)] = []
            await withTaskGroup(of: (Int, String, Int)?.self) { group in
                for c in ids.prefix(100) {
                    group.addTask { @MainActor in
                        guard let info = try? await svc.corporationInfo(corpId: c) else { return nil }
                        return (c, info.name, info.memberCount ?? 0)
                    }
                }
                for await r in group { if let r { list.append(r) } }
            }
            corpCount = ids.count
            corps = list.sorted { $0.2 > $1.2 }.map { (id: $0.0, name: $0.1, members: $0.2) }
            info = i
        } catch {
            if !error.isCancellation { self.error = error.localizedDescription }
        }
    }
}
