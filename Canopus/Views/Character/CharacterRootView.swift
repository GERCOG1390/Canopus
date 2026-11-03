import SwiftUI
import EVEAuth
import EVEStaticData
import Domain
import UserNotifications

private struct ShipLocationSummary: Hashable {
    let locationName: String?
    let systemName: String?
    let locationKind: String

    var displayText: String {
        switch (locationName, systemName) {
        case let (.some(location), .some(system)):
            "\(location) · \(system)"
        case let (.some(location), .none):
            location
        case let (.none, .some(system)):
            "\(locationKind) · \(system)"
        case (.none, .none):
            locationKind
        }
    }
}

/// The character overview (the desktop's Overview.tsx): who, where and in what, wallet / SP / location /
/// queue, the training queue, attributes with implant bonuses, active implants, corporation history.
struct CharacterRootView: View {
    var openTab: (CharacterTab) -> Void = { _ in }

    @Environment(AppEnvironment.self) private var env
    @State private var skillQueue: [SkillQueueEntry] = []
    @State private var walletBalance: Double?
    @State private var totalSP: Int?
    @State private var charInfo: ESICharacterInfo?
    @State private var corpInfo: ESICorporationInfo?
    @State private var allianceInfo: ESIAllianceInfo?
    @State private var unallocatedSP: Int?
    @State private var systemName: String?
    @State private var systemSec: Double?
    @State private var ship: ESICurrentShip?
    @State private var shipTypeName: String?
    @State private var shipLocation: ShipLocationSummary?
    @State private var serverStatus: ESIServerStatus?
    @State private var online: ESIOnlineStatus?
    @State private var attributes: PilotAttributes?
    @State private var implants: [Int] = []
    @State private var typeNames: [Int: String] = [:]
    @State private var history: [ESIEmploymentHistoryItem] = []
    @State private var corpNames: [Int: String] = [:]
    @State private var switcherOpen = false
    @State private var error: Error?
    /// Debug builds: `-openActiveShip YES` opens the current ship's fit once the ship is known.
    @State private var debugActiveShip = false

    enum Destination: Hashable {
        case activeShipFit
    }

    private var svc: CharacterService? { env.characterStore.selectedService }
    private var charId: Int { svc?.tokens.characterId ?? 0 }
    private var charName: String { svc?.tokens.characterName ?? "" }
    private var activeEntry: SkillQueueEntry? { skillQueue.first(where: \.isActive) }

    var body: some View {
        ZStack {
            C.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    heroCard
                    statGrid
                    alertsBlock
                    queueCard
                    attributesCard
                    implantsCard
                    historyCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, EVELayout.scrollBottomClearance)
            }
            .refreshable { await load() }

            // Character switcher overlay
            if switcherOpen { switcherOverlay }
        }
        .toolbar { toolbarContent }
        .navigationDestination(for: Destination.self) { dest in
            destinationView(for: dest)
        }
        .navigationDestination(isPresented: $debugActiveShip) { destinationView(for: .activeShipFit) }
        #if DEBUG
        .onChange(of: ship?.shipItemId) { _, id in
            if id != nil, UserDefaults.standard.bool(forKey: "openActiveShip") { debugActiveShip = true }
        }
        #endif
        .task(id: env.dataKey) { await load() }
        .alert("Error", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } })
        ) {
            Button("Retry") { Task { await load() } }
            Button("Dismiss", role: .cancel) {}
        } message: { Text(error?.localizedDescription ?? "") }
    }

    // MARK: - Destination

    @ViewBuilder
    private func destinationView(for dest: Destination) -> some View {
        if let s = svc {
            switch dest {
            case .activeShipFit:
                if let ship {
                    FitDetailView(
                        fit: ESIFitting(
                            fittingId: -ship.shipItemId,
                            name: ship.shipName,
                            description: "Current active ship",
                            shipTypeId: ship.shipTypeId,
                            items: []
                        ),
                        typeNames: [ship.shipTypeId: shipTypeName ?? "Ship"],
                        characterService: s
                    )
                }
            }
        }
    }

    // MARK: - Hero (desktop .hero card)

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                EVECharacterPortrait(characterId: charId, size: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(C.lineStrong, lineWidth: 1))

                VStack(alignment: .leading, spacing: 5) {
                    Button {
                        if env.characterStore.characters.count > 1 { withAnimation(.easeInOut(duration: 0.2)) { switcherOpen.toggle() } }
                    } label: {
                        HStack(spacing: 6) {
                            Text(charName)
                                .font(.display(21))
                                .foregroundStyle(C.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            if env.characterStore.characters.count > 1 {
                                Glyph(name: .chevron, size: 14)
                                    .rotationEffect(.degrees(90))
                                    .foregroundStyle(C.accentText)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if let info = charInfo {
                        HStack(spacing: 6) {
                            EVECorpLogo(corpId: info.corporationId, size: 18)
                            Text(corpInfo?.name ?? "")
                                .lineLimit(1)
                            if let a = info.allianceId {
                                Text("·").foregroundStyle(C.faint)
                                EVEAllianceLogo(allianceId: a, size: 18)
                                Text(allianceInfo?.name ?? "")
                                    .lineLimit(1)
                            }
                        }
                        .font(.ui(13))
                        .foregroundStyle(C.text2)
                    }

                    HStack(spacing: 6) {
                        if let sec = charInfo?.securityStatus {
                            Text("Security status")
                            Text(String(format: "%.2f", sec))
                                .monospacedDigit()
                                .foregroundStyle(sec < 0 ? C.bad : C.text2)
                        }
                        if let s = serverStatus {
                            Text("·").foregroundStyle(C.faint)
                            Circle().fill(C.good).frame(width: 6, height: 6)
                            Text(s.players.formatted()).monospacedDigit()
                        } else {
                            Text("·").foregroundStyle(C.faint)
                            Circle().fill(C.bad).frame(width: 6, height: 6)
                            Text("Server offline").foregroundStyle(C.bad)
                        }
                    }
                    .font(.ui(12))
                    .foregroundStyle(C.muted)

                    HStack(spacing: 6) {
                        if let online {
                            if online.online {
                                Text("● in game").foregroundStyle(C.good)
                            } else {
                                Text("Last login: \(online.lastLogin.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")")
                            }
                        }
                        if let born = charInfo?.birthday {
                            Text("· Created \(born.formatted(date: .abbreviated, time: .omitted))")
                        }
                        if let n = online?.logins, n > 0 { Text("· logins: \(n.formatted())") }
                    }
                    .font(.ui(12))
                    .foregroundStyle(C.muted)
                    .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            if let ship {
                NavigationLink(value: Destination.activeShipFit) {
                    HStack(spacing: 12) {
                        EVERenderImage(typeId: ship.shipTypeId, size: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(shipTypeName ?? "Ship")
                                .font(.ui(15, .medium))
                                .foregroundStyle(C.accentText)
                            Text(ship.shipName)
                                .font(.ui(13))
                                .foregroundStyle(C.muted)
                                .lineLimit(1)
                        }
                        Spacer()
                        Glyph(name: .chevron, size: 14)
                            .foregroundStyle(C.faint)
                    }
                    .padding(10)
                    .background(C.card, in: EVECut(cut: 8))
                    .overlay(EVECut(cut: 8).strokeBorder(C.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [C.accent.opacity(0.10), C.panel], startPoint: .topLeading, endPoint: UnitPoint(x: 0.6, y: 0.6)),
            in: EVECut()
        )
        .background(C.panel, in: EVECut())
        .overlay(EVECut().strokeBorder(C.border, lineWidth: 1))
    }

    // MARK: - Stats (desktop .stats-row)

    private var queueEnd: Date? { skillQueue.compactMap(\.finishDate).max() }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            Button { openTab(.wallet) } label: {
                StatTile(label: "Wallet", value: walletBalance.map { Fmt.isk($0) } ?? "—", sub: walletBalance.map { Fmt.isk($0, compact: false) })
            }
            .buttonStyle(.plain)
            StatTile(label: "Total SP", value: totalSP.map { $0.formatted() } ?? "—", sub: unallocatedSP.map { $0 > 0 ? String(localized: "Unallocated: \($0.formatted())") : nil } ?? nil)
            StatTile(
                label: "Location",
                value: systemName ?? "—",
                sub: shipLocation?.locationName ?? (systemName == nil ? nil : String(localized: "In space")),
                valueColor: systemSec.map { C.sec($0) } ?? C.text
            )
            Button { openTab(.skills) } label: {
                StatTile(
                    label: "Skill queue",
                    value: queueEnd.map { Fmt.duration(until: $0) } ?? String(localized: "empty"),
                    sub: String(localized: "\(skillQueue.count) in queue"),
                    valueColor: skillQueue.isEmpty ? C.warn : C.text
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Alerts

    private struct EVEAlert {
        let title: LocalizedStringKey
        let subtitle: String
        let color: Color
    }

    private var computedAlerts: [EVEAlert] {
        var a: [EVEAlert] = []
        if let missing = svc?.tokens.missingScopes, !missing.isEmpty {
            a.append(.init(title: "New features need more permissions: sign in again with this character in Settings", subtitle: charName, color: C.warn))
        }
        if skillQueue.isEmpty, totalSP != nil {
            a.append(.init(title: "The skill queue is empty — the character is not training anything!", subtitle: charName, color: C.warn))
        } else if let end = queueEnd, end.timeIntervalSinceNow < 86_400 {
            a.append(.init(title: "The skill queue ends in less than a day", subtitle: Fmt.duration(until: end), color: C.warn))
        }
        return a
    }

    @ViewBuilder
    private var alertsBlock: some View {
        ForEach(Array(computedAlerts.enumerated()), id: \.offset) { _, alert in
            HStack(alignment: .top, spacing: 10) {
                Glyph(name: .alert, size: 20)
                    .foregroundStyle(alert.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title).font(.ui(14, .medium)).foregroundStyle(C.text)
                    Text(alert.subtitle).font(.ui(12)).foregroundStyle(C.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(alert.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(alert.color.opacity(0.45), lineWidth: 1))
        }
    }

    // MARK: - Training queue (desktop "Очередь обучения")

    private var queueCard: some View {
        Card(title: "Training queue", actions: {
            if !skillQueue.isEmpty {
                Button("All") { openTab(.skills) }.buttonStyle(.canopusSmall)
            }
        }) {
            if skillQueue.isEmpty {
                Text("The queue is empty.")
                    .font(.ui(14))
                    .foregroundStyle(C.muted)
            }
            VStack(spacing: 10) {
                ForEach(Array(skillQueue.prefix(6).enumerated()), id: \.element.id) { i, e in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(e.skillName ?? "#\(e.skillId)")
                                .font(.ui(14))
                                .foregroundStyle(C.accentText)
                                .lineLimit(1)
                            Text(romanNumeral(e.finishedLevel))
                                .font(.ui(14, .bold))
                                .foregroundStyle(C.text)
                            Spacer()
                            Text(e.finishDate.map { Fmt.duration(until: $0) } ?? String(localized: "paused"))
                                .font(.ui(13))
                                .monospacedDigit()
                                .foregroundStyle(C.muted)
                        }
                        if i == 0, e.isActive {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(C.panel2)
                                    Capsule().fill(C.accent).frame(width: geo.size.width * e.progress)
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
                if skillQueue.count > 6 {
                    Text("+\(skillQueue.count - 6)")
                        .font(.ui(12))
                        .foregroundStyle(C.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Attributes, implants, corporation history

    /// Perception, memory, willpower, intelligence, charisma (character attribute ids).
    private static let attributeRows: [(LocalizedStringKey, Int)] = [
        ("Perception", 167), ("Memory", 166), ("Willpower", 168), ("Intelligence", 165), ("Charisma", 164),
    ]

    private var attributesCard: some View {
        Card(String(localized: "Attributes")) {
            if let attributes {
                VStack(spacing: 8) {
                    ForEach(Self.attributeRows, id: \.1) { name, attr in
                        let bonus = attributes.implantBonus[attr] ?? 0
                        HStack {
                            Text(name).font(.ui(14)).foregroundStyle(C.text)
                            Spacer()
                            Text(verbatim: "\(attributes.effective[attr] ?? 0)").font(.mono(14, medium: true)).foregroundStyle(C.text)
                            if bonus > 0 {
                                Text("(+\(bonus) implants)").font(.ui(12)).foregroundStyle(C.good)
                            }
                        }
                    }
                }
            } else {
                Text("No data").font(.ui(13)).foregroundStyle(C.muted)
            }
        }
    }

    private var implantsCard: some View {
        Card(String(localized: "Active implants")) {
            if implants.isEmpty {
                Text("No implants").font(.ui(13)).foregroundStyle(C.muted)
            }
            ForEach(implants, id: \.self) { id in
                NavigationLink { TypeDetailView(typeId: id, typeName: typeNames[id] ?? "") } label: {
                    HStack(spacing: 8) {
                        EVETypeIcon(typeId: id, size: 24)
                        Text(verbatim: typeNames[id] ?? "#\(id)").font(.ui(13)).foregroundStyle(C.accentText).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var historyCard: some View {
        if !history.isEmpty {
            Card(String(localized: "Corporation history")) {
                ForEach(Array(history.enumerated()), id: \.element.id) { i, h in
                    HStack(spacing: 8) {
                        EVECorpLogo(corpId: h.corporationId, size: 20)
                        Text(verbatim: corpNames[h.corporationId] ?? "#\(h.corporationId)").font(.ui(13)).foregroundStyle(C.text).lineLimit(1)
                        Spacer(minLength: 6)
                        let until = i == 0 ? String(localized: "now") : history[i - 1].startDate.formatted(.iso8601.year().month().day())
                        Text(verbatim: "\(h.startDate.formatted(.iso8601.year().month().day())) — \(until)")
                            .font(.mono(11)).foregroundStyle(C.muted)
                    }
                }
            }
        }
    }

    // MARK: - Character switcher overlay

    private var switcherOverlay: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.012, green: 0.020, blue: 0.027).opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture { withAnimation { switcherOpen = false } }

            VStack(alignment: .leading, spacing: 12) {
                Text("SELECT PILOT")
                    .font(.ui(11, .semibold))
                    .tracking(2.2)
                    .foregroundStyle(Color.eveAmber)
                    .padding(.top, 120)
                    .padding(.horizontal, 20)

                ForEach(env.characterStore.characters) { c in
                    Button {
                        withAnimation { switcherOpen = false }
                        env.characterStore.selectedId = c.characterId
                    } label: {
                        HStack(spacing: 12) {
                            EVECharacterPortrait(characterId: c.characterId, size: 40)
                                .clipShape(CutCorner(size: 7))
                                .overlay(CutCorner(size: 7).stroke(
                                    c.characterId == charId
                                        ? Color.eveAmber.opacity(0.5)
                                        : Color.white.opacity(0.10),
                                    lineWidth: 1))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(c.characterName)
                                    .font(.ui(15, .medium))
                                    .foregroundStyle(Color.eveText)
                                Text(c.characterId == charId ? "ACTIVE" : "TAP TO SWITCH")
                                    .font(.ui(11.5))
                                    .tracking(1.0)
                                    .foregroundStyle(c.characterId == charId
                                                     ? Color.eveCyan : Color.eveText.opacity(0.42))
                            }
                            Spacer()
                        }
                        .padding(12)
                        .eveCard(border: c.characterId == charId
                                     ? Color.eveAmber.opacity(0.4)
                                     : Color.white.opacity(0.08))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if env.characterStore.characters.count > 1 {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { withAnimation { switcherOpen.toggle() } } label: {
                    Glyph(name: .user, size: 20).foregroundStyle(C.accentText)
                }
            }
        }
    }

    // MARK: - Load

    private func load() async {
        guard let service = svc else { return }
        error = nil

        async let ss = MarketService().serverStatus()
        serverStatus = try? await ss

        do {
            async let qi = service.skillQueue()
            async let wi = service.wallet()
            async let ci = service.characterInfo()
            async let si = service.skills()
            async let sh = service.currentShip()

            let (rawQueue, balance, info, skillsResp, shipInfo) =
                try await (qi, wi, ci, si, sh)

            charInfo = info
            walletBalance = balance
            totalSP = skillsResp.totalSp
            unallocatedSP = skillsResp.unallocatedSp
            ship = shipInfo
            corpInfo = try? await service.corporationInfo(corpId: info.corporationId)
            allianceInfo = nil
            if let a = info.allianceId { allianceInfo = try? await service.allianceInfo(allianceId: a) }
            shipLocation = nil

            if let repo = env.repository {
                skillQueue = try await resolveQueueNames(rawQueue, repo: repo)
                shipTypeName = try? await repo.type(id: shipInfo.shipTypeId)?.name
            } else {
                skillQueue = rawQueue.map { makeEntry($0) }
            }

            if let location = try? await service.location() {
                shipLocation = await resolveShipLocation(location, service: service)
                let sys = try? await service.systemInfo(id: location.solarSystemId)
                systemName = sys?.name
                systemSec = sys?.securityStatus
            }

            await loadDetails(service)

            let active = skillQueue.first(where: \.isActive)
            saveWidgetData(service: service, activeEntry: active)
            await scheduleSkillNotification(entry: active, characterName: charName)
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }

    /// Online status, attributes, implants (with their attribute bonuses) and the corporation history.
    private func loadDetails(_ service: CharacterService) async {
        async let o = try? service.online()
        async let a = PilotAttributes.load(service: service, repository: env.repository)
        async let imp = try? service.implants()
        async let h = try? service.employmentHistory()
        online = await o
        attributes = await a
        implants = await imp ?? []
        let hist = (await h ?? []).sorted { $0.startDate > $1.startDate }
        if let repo = env.repository, !implants.isEmpty {
            typeNames = ((try? await repo.types(ids: Set(implants))) ?? [:]).mapValues(\.name)
        }
        let ids = Array(Set(hist.map(\.corporationId)))
        if let resolved = try? await service.resolveNames(ids: ids) {
            corpNames = Dictionary(resolved.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        }
        history = hist
    }

    private func resolveShipLocation(
        _ location: ESICharacterLocation,
        service: CharacterService
    ) async -> ShipLocationSummary {
        let systemName = try? await service.systemInfo(id: location.solarSystemId).name

        if let stationId = location.stationId,
           let station = try? await service.stationInfo(id: stationId) {
            var stationSystemName = systemName
            if stationSystemName == nil {
                stationSystemName = try? await service.systemInfo(id: station.systemId).name
            }
            return ShipLocationSummary(
                locationName: station.name,
                systemName: stationSystemName,
                locationKind: "Station"
            )
        }

        if let structureId = location.structureId,
           let structure = try? await service.structureInfo(id: structureId) {
            var structureSystemName = systemName
            if structureSystemName == nil {
                structureSystemName = try? await service.systemInfo(id: structure.solarSystemId).name
            }
            return ShipLocationSummary(
                locationName: structure.name,
                systemName: structureSystemName,
                locationKind: "Structure"
            )
        }

        return ShipLocationSummary(
            locationName: nil,
            systemName: systemName,
            locationKind: "In Space"
        )
    }

    private func makeEntry(_ item: ESISkillQueueItem, skillName: String? = nil) -> SkillQueueEntry {
        SkillQueueEntry(
            queuePosition: item.queuePosition, skillId: item.skillId,
            finishedLevel: item.finishedLevel, startDate: item.startDate,
            finishDate: item.finishDate, trainingStartSP: item.trainingStartSp ?? 0,
            levelStartSP: item.levelStartSp ?? 0, levelEndSP: item.levelEndSp ?? 0,
            skillName: skillName
        )
    }

    private func resolveQueueNames(_ items: [ESISkillQueueItem], repo: SDERepository) async throws -> [SkillQueueEntry] {
        let ids = Set(items.map(\.skillId))
        var names: [Int: String] = [:]
        for id in ids { if let t = try? await repo.type(id: id) { names[id] = t.name } }
        return items.map { makeEntry($0, skillName: names[$0.skillId]) }
    }

    // MARK: - Widget + Notifications

    private func saveWidgetData(service: CharacterService, activeEntry: SkillQueueEntry?) {
        WidgetData(
            characterId: service.tokens.characterId,
            characterName: service.tokens.characterName,
            activeSkillName: activeEntry?.skillName,
            activeSkillLevel: activeEntry?.finishedLevel,
            activeSkillFinishDate: activeEntry?.finishDate,
            queueCount: skillQueue.count,
            updatedAt: Date()
        ).save()
    }

    private func scheduleSkillNotification(entry: SkillQueueEntry?, characterName: String) async {
        let center = UNUserNotificationCenter.current()
        let toRemove = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix("canopus.skill.") }
            .map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: toRemove)
        // Only when the pilot turned it on (Settings → Notifications) and iOS allows it.
        guard NotificationSettings.shared.skillDone,
              await center.notificationSettings().authorizationStatus == .authorized else { return }
        guard let entry, let finish = entry.finishDate, finish > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Skill training complete")
        content.body = String(localized: "\(characterName): \(entry.skillName ?? "Skill \(entry.skillId)") \(romanNumeral(entry.finishedLevel)) complete")
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second], from: finish)
        let req = UNNotificationRequest(
            identifier: "canopus.skill.\(entry.skillId).\(entry.finishedLevel)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        try? await center.add(req)
    }

    // MARK: - Formatting

    private func romanNumeral(_ n: Int) -> String {
        ["0","I","II","III","IV","V"][max(0, min(5, n))]
    }
}
