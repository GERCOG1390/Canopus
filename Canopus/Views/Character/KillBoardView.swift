import SwiftUI
import EVEAuth
import EVEStaticData
import Domain

struct KillBoardView: View {
    let characterService: CharacterService

    @State private var mode: KBMode = .kills
    @State private var kills:  [KBRecord] = []
    @State private var losses: [KBRecord] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var killsPage  = 1
    @State private var lossesPage = 1
    @State private var killsHasMore  = true
    @State private var lossesHasMore = true
    @State private var error: Error?

    private let zkb = KillBoardService()
    private var charId: Int { characterService.tokens.characterId }

    private var current: [KBRecord] { mode == .kills ? kills : losses }
    private var hasMore: Bool { mode == .kills ? killsHasMore : lossesHasMore }

    enum KBMode { case kills, losses }

    var body: some View {
        ZStack {
            Color.eveBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                modePicker
                Color.eveAmber.opacity(0.14).frame(height: 1)
                killList
            }
            if isLoading { ProgressView().tint(Color.eveCyan) }
        }
        .navigationTitle("KILL BOARD")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.eveBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await loadInitial() }
        .alert("Error", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } })
        ) {
            Button("Retry") { Task { await loadInitial() } }
            Button("Dismiss", role: .cancel) {}
        } message: { Text(error?.localizedDescription ?? "") }
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        HStack(spacing: 0) {
            modeTab(label: "KILLS", count: kills.count, active: mode == .kills, color: .eveGreen) {
                withAnimation(.easeInOut(duration: 0.12)) { mode = .kills }
            }
            modeTab(label: "LOSSES", count: losses.count, active: mode == .losses, color: .eveRed) {
                withAnimation(.easeInOut(duration: 0.12)) { mode = .losses }
            }
        }
        .background(Color.eveCard)
    }

    private func modeTab(label: String, count: Int, active: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Rectangle().fill(active ? color : Color.clear).frame(height: 2)
                HStack(spacing: 6) {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(active ? color : Color.eveText.opacity(0.40))
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(active ? Color.eveBackground : color)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(active ? color : color.opacity(0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Kill list

    private var killList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if current.isEmpty && !isLoading {
                    ContentUnavailableView(
                        mode == .kills ? "No Kills" : "No Losses",
                        systemImage: mode == .kills ? "xmark.shield" : "shield.slash",
                        description: Text("Nothing recorded yet.")
                    )
                    .foregroundStyle(Color.eveText)
                    .padding(.top, 60)
                } else {
                    ForEach(current) { record in
                        NavigationLink(value: record) {
                            killRow(record)
                        }
                        .buttonStyle(.plain)
                        Color.white.opacity(0.055).frame(height: 1)
                    }
                    if hasMore && !current.isEmpty {
                        Button { Task { await loadMore() } } label: {
                            HStack(spacing: 8) {
                                if isLoadingMore { ProgressView().tint(Color.eveCyan).scaleEffect(0.8) }
                                Text("LOAD MORE").font(.system(size: 10, weight: .semibold)).tracking(1.6)
                                    .foregroundStyle(Color.eveCyan)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                        }
                        .buttonStyle(.plain).disabled(isLoadingMore)
                    }
                }
            }
            .padding(.bottom, EVELayout.scrollBottomClearance)
        }
        .navigationDestination(for: KBRecord.self) { record in
            KillDetailView(record: record, characterService: characterService)
        }
    }

    private func killRow(_ record: KBRecord) -> some View {
        let isKill = mode == .kills
        let color: Color = isKill ? .eveGreen : .eveRed

        return HStack(spacing: 13) {
            // Ship destroyed
            EVERenderImage(typeId: record.victimShipTypeId, size: 44)
                .clipShape(CutCorner(size: 7))
                .overlay(CutCorner(size: 7).stroke(color.opacity(0.22), lineWidth: 1))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(isKill ? "KILL" : "LOSS")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(color)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .overlay(CutCorner(size: 3).stroke(color.opacity(0.4), lineWidth: 1))
                    if record.solo == true {
                        Text("SOLO").font(.system(size: 8, weight: .bold)).tracking(1.2)
                            .foregroundStyle(Color.eveAmber)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .overlay(CutCorner(size: 3).stroke(Color.eveAmber.opacity(0.4), lineWidth: 1))
                    }
                }
                Text(record.victimShipName ?? "Ship \(record.victimShipTypeId)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.eveText)
                Text(record.time, style: .relative)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.eveText.opacity(0.38))
            }

            Spacer()

            if let isk = record.totalValue, isk > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(iskCompact(isk))
                        .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(color)
                    Text("ISK").font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(Color.eveText.opacity(0.28))
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color.eveBackground)
    }

    // MARK: - Load

    private func loadInitial() async {
        isLoading = true; error = nil; defer { isLoading = false }
        killsPage = 1; lossesPage = 1
        kills = []; losses = []

        await withTaskGroup(of: Void.self) { g in
            g.addTask { await self.fetchKills(page: 1) }
            g.addTask { await self.fetchLosses(page: 1) }
        }
    }

    private func loadMore() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true; defer { isLoadingMore = false }
        if mode == .kills {
            killsPage += 1
            await fetchKills(page: killsPage)
        } else {
            lossesPage += 1
            await fetchLosses(page: lossesPage)
        }
    }

    private func fetchKills(page: Int) async {
        guard let entries = try? await zkb.kills(characterId: charId, page: page) else {
            killsHasMore = false; return
        }
        let records = await resolveRecords(entries)
        if page == 1 { kills = records } else { kills += records }
        killsHasMore = entries.count == 200
    }

    private func fetchLosses(page: Int) async {
        guard let entries = try? await zkb.losses(characterId: charId, page: page) else {
            lossesHasMore = false; return
        }
        let records = await resolveRecords(entries)
        if page == 1 { losses = records } else { losses += records }
        lossesHasMore = entries.count == 200
    }

    private func resolveRecords(_ entries: [ZKBEntry]) async -> [KBRecord] {
        // Limit concurrent ESI killmail requests to avoid rate-limiting.
        let batchSize = 20
        var result: [KBRecord] = []
        for batch in stride(from: 0, to: entries.count, by: batchSize) {
            let slice = Array(entries[batch ..< min(batch + batchSize, entries.count)])
            let records = await withTaskGroup(of: KBRecord?.self) { g in
                for entry in slice {
                    g.addTask {
                        guard let km = try? await self.characterService.killMailDetail(
                            id: entry.killmailId, hash: entry.killmailHash) else { return nil }
                        return KBRecord(
                            id: entry.killmailId,
                            hash: entry.killmailHash,
                            time: km.killmailTime,
                            victimShipTypeId: km.victim.shipTypeId,
                            victimShipName: nil,
                            victimCharId: km.victim.characterId,
                            attackerCount: km.attackers.count,
                            finalBlow: km.attackers.first(where: \.finalBlow),
                            totalValue: entry.zkb.totalValue,
                            solo: entry.zkb.solo,
                            allAttackers: km.attackers
                        )
                    }
                }
                var out: [KBRecord] = []
                for await r in g { if let r { out.append(r) } }
                return out
            }
            result.append(contentsOf: records)
        }
        return result.sorted { $0.time > $1.time }
    }

    private func iskCompact(_ v: Double) -> String {
        if v >= 1_000_000_000 { return String(format: "%.2fB", v / 1_000_000_000) }
        if v >= 1_000_000     { return String(format: "%.2fM", v / 1_000_000) }
        if v >= 1_000         { return String(format: "%.1fK", v / 1_000) }
        return String(format: "%.0f", v)
    }
}

// MARK: - Kill record model

struct KBRecord: Identifiable, Hashable {
    let id: Int
    let hash: String
    let time: Date
    let victimShipTypeId: Int
    let victimShipName: String?
    let victimCharId: Int?
    let attackerCount: Int
    let finalBlow: ESIKillAttacker?
    let totalValue: Double?
    let solo: Bool?
    let allAttackers: [ESIKillAttacker]

    static func == (lhs: KBRecord, rhs: KBRecord) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Kill detail

struct KillDetailView: View {
    let record: KBRecord
    let characterService: CharacterService

    @State private var names: [Int: String] = [:]
    @State private var shipName: String?
    @State private var isLoading = true
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ZStack {
            Color.eveBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    victimHeader(record)
                    Color.eveAmber.opacity(0.14).frame(height: 1)
                    attackersSection(record.allAttackers)
                }
                .padding(.bottom, EVELayout.scrollBottomClearance)
            }
            if isLoading { ProgressView().tint(Color.eveCyan) }
        }
        .navigationTitle("KILL DETAIL")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.eveBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
    }

    private func victimHeader(_ r: KBRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                EVERenderImage(typeId: r.victimShipTypeId, size: 64)
                    .clipShape(CutCorner(size: 10))
                    .overlay(CutCorner(size: 10).stroke(Color.eveRed.opacity(0.35), lineWidth: 1))

                VStack(alignment: .leading, spacing: 5) {
                    Text(shipName ?? "Ship \(r.victimShipTypeId)")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.eveText)
                    if let cid = r.victimCharId {
                        Text(names[cid] ?? "Capsuleer \(cid)")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.eveText.opacity(0.58))
                    }
                    if let v = r.totalValue, v > 0 {
                        Text(iskCompact(v) + " ISK DESTROYED")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(Color.eveRed)
                    }
                }
            }

            HStack(spacing: 20) {
                metaItem(label: "DATE", value: r.time.formatted(date: .abbreviated, time: .shortened))
                metaItem(label: "ATTACKERS", value: "\(r.attackerCount)")
                if r.solo == true { metaItem(label: "TYPE", value: "SOLO") }
            }
        }
        .padding(20)
    }

    private func metaItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).hudLabel()
            Text(value).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Color.eveText)
        }
    }

    private func attackersSection(_ attackers: [ESIKillAttacker]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ATTACKERS · \(attackers.count)").hudLabel()
                .padding(.horizontal, 20).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.eveCard)
            Color.white.opacity(0.06).frame(height: 1)

            let sorted = attackers.sorted { $0.finalBlow && !$1.finalBlow }
            ForEach(Array(sorted.enumerated()), id: \.offset) { _, att in
                attackerRow(att)
                Color.white.opacity(0.04).frame(height: 1)
            }
        }
    }

    private func attackerRow(_ att: ESIKillAttacker) -> some View {
        HStack(spacing: 12) {
            if let sid = att.shipTypeId {
                EVETypeIcon(typeId: sid, size: 36)
                    .clipShape(CutCorner(size: 5))
                    .overlay(CutCorner(size: 5).stroke(Color.white.opacity(0.08), lineWidth: 1))
            } else {
                RoundedRectangle(cornerRadius: 4).fill(Color.eveCard).frame(width: 36, height: 36)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(att.characterId.flatMap { names[$0] } ?? "NPC")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.eveText)
                    if att.finalBlow {
                        Text("FINAL BLOW")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(1.0)
                            .foregroundStyle(Color.eveAmber)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .overlay(CutCorner(size: 2).stroke(Color.eveAmber.opacity(0.4), lineWidth: 1))
                    }
                }
                Text("\(att.damageDone.formatted()) dmg")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.eveText.opacity(0.38))
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 9)
        .background(Color.eveBackground)
    }

    private func load() async {
        isLoading = true; defer { isLoading = false }
        if let repo = env.repository {
            shipName = try? await repo.type(id: record.victimShipTypeId)?.name
        }
        var ids: [Int] = []
        if let cid = record.victimCharId { ids.append(cid) }
        ids += record.allAttackers.compactMap(\.characterId).prefix(20)
        if !ids.isEmpty, let resolved = try? await characterService.resolveNames(ids: Array(Set(ids))) {
            for r in resolved { names[r.id] = r.name }
        }
    }

    private func iskCompact(_ v: Double) -> String {
        if v >= 1_000_000_000 { return String(format: "%.2fB", v / 1_000_000_000) }
        if v >= 1_000_000     { return String(format: "%.2fM", v / 1_000_000) }
        return String(format: "%.0f", v)
    }
}
