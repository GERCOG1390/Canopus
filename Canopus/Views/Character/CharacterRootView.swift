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

struct CharacterRootView: View {
    var switchToTab: (EVETab) -> Void = { _ in }

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
    @State private var switcherOpen = false
    @State private var error: Error?

    enum Destination: Hashable {
        case characterSheet, wealth, mail, transactions, mining, fittings, activeShipFit, killboard, clone, loyalty, journal, industry, orders, contracts
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
                    sectionsCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, EVELayout.scrollBottomClearance)
            }
            .refreshable { await load() }

            // Character switcher overlay
            if switcherOpen { switcherOverlay }
        }
        .navigationTitle("Character")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .navigationDestination(for: Destination.self) { dest in
            destinationView(for: dest)
        }
        .task(id: env.characterStore.selectedId) { await load() }
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
            case .characterSheet: CharacterSheetView(characterService: s)
            case .wealth:         WealthView(characterService: s)
            case .mail:           MailView(characterService: s)
            case .transactions:   WalletTransactionsView(characterService: s)
            case .mining:         MiningLedgerView(characterService: s)
            case .fittings:       FittingsView(characterService: s)
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
            case .killboard:      KillBoardView(characterService: s)
            case .clone:          CloneView(characterService: s)
            case .loyalty:        LoyaltyPointsView(characterService: s)
            case .journal:        WalletJournalView(characterService: s)
            case .industry:       IndustryView(characterService: s)
            case .orders:         MarketOrdersView(characterService: s)
            case .contracts:      ContractsView(characterService: s)
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
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
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
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
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
            Button { switchToTab(.wallet) } label: {
                StatTile(label: "Wallet", value: walletBalance.map { iskCompact($0) } ?? "—", sub: walletBalance.map { iskFull($0) })
            }
            .buttonStyle(.plain)
            StatTile(label: "Total SP", value: totalSP.map { $0.formatted() } ?? "—", sub: unallocatedSP.map { $0 > 0 ? String(localized: "Unallocated: \($0.formatted())") : nil } ?? nil)
            StatTile(
                label: "Location",
                value: systemName ?? "—",
                sub: shipLocation?.locationName ?? (systemName == nil ? nil : String(localized: "In space")),
                valueColor: systemSec.map { C.sec($0) } ?? C.text
            )
            Button { switchToTab(.skills) } label: {
                StatTile(
                    label: "Skill queue",
                    value: queueEnd.map { durationText(until: $0) } ?? String(localized: "empty"),
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
        if skillQueue.isEmpty, totalSP != nil {
            a.append(.init(title: "The skill queue is empty — the character is not training anything!", subtitle: charName, color: C.warn))
        } else if let end = queueEnd, end.timeIntervalSinceNow < 86_400 {
            a.append(.init(title: "The skill queue ends in less than a day", subtitle: durationText(until: end), color: C.warn))
        }
        return a
    }

    @ViewBuilder
    private var alertsBlock: some View {
        ForEach(Array(computedAlerts.enumerated()), id: \.offset) { _, alert in
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
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
                Button("All") { switchToTab(.skills) }.buttonStyle(.canopusSmall)
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
                            Text(e.finishDate.map { durationText(until: $0) } ?? String(localized: "paused"))
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

    // MARK: - Sections

    private var sectionsCard: some View {
        let links: [(String, String, Destination)] = [
            ("Character Sheet", "person.text.rectangle", .characterSheet),
            ("Wealth Overview", "chart.pie", .wealth),
            ("EVE Mail", "envelope", .mail),
            ("Clone & Implants", "brain.head.profile", .clone),
            ("Fittings", "hexagon", .fittings),
            ("Kill Board", "scope", .killboard),
            ("Wallet Journal", "creditcard", .journal),
            ("Transactions", "arrow.left.arrow.right", .transactions),
            ("Market Orders", "chart.line.uptrend.xyaxis", .orders),
            ("Industry Jobs", "gearshape.2", .industry),
            ("Mining Ledger", "cube", .mining),
            ("Loyalty Points", "seal", .loyalty),
            ("Contracts", "doc.text", .contracts),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Sections")
            VStack(spacing: 0) {
                ForEach(links, id: \.0) { title, icon, dest in
                    NavigationLink(value: dest) {
                        HStack(spacing: 14) {
                            Image(systemName: icon)
                                .font(.system(size: 15))
                                .foregroundStyle(C.accentText)
                                .frame(width: 22)
                            Text(LocalizedStringKey(title))
                                .font(.ui(15))
                                .foregroundStyle(C.text)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(C.faint)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if title != links.last?.0 {
                        Rectangle().fill(C.border).frame(height: 1).padding(.leading, 52)
                    }
                }
            }
            .canopusSurface(padding: nil)
        }
        .padding(.top, 4)
    }

    // MARK: - Character switcher overlay

    private var switcherOverlay: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.012, green: 0.020, blue: 0.027).opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture { withAnimation { switcherOpen = false } }

            VStack(alignment: .leading, spacing: 12) {
                Text("SELECT PILOT")
                    .font(.system(size: 9.5, weight: .semibold))
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
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.eveText)
                                Text(c.characterId == charId ? "ACTIVE" : "TAP TO SWITCH")
                                    .font(.system(size: 10.5))
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
                    Image(systemName: "person.2").foregroundStyle(Color.eveAmber)
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

            let active = skillQueue.first(where: \.isActive)
            saveWidgetData(service: service, activeEntry: active)
            await scheduleSkillNotification(entry: active, characterName: charName)
        } catch {
            self.error = error
        }
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
        guard let entry, let finish = entry.finishDate, finish > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Skill Training Complete"
        content.body = "\(characterName): \(entry.skillName ?? "Skill \(entry.skillId)") \(romanNumeral(entry.finishedLevel)) complete"
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second], from: finish)
        let req = UNNotificationRequest(
            identifier: "canopus.skill.\(entry.skillId).\(entry.finishedLevel)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        try? await center.add(req)
    }

    // MARK: - Formatting

    /// "12.28B ISK" as the desktop's compact ISK.
    private func iskCompact(_ v: Double) -> String {
        let a = abs(v)
        if a >= 1e12 { return String(format: "%.2fT ISK", v / 1e12) }
        if a >= 1e9 { return String(format: "%.2fB ISK", v / 1e9) }
        if a >= 1e6 { return String(format: "%.2fM ISK", v / 1e6) }
        if a >= 1e3 { return String(format: "%.1fK ISK", v / 1e3) }
        return String(format: "%.2f ISK", v)
    }

    private func iskFull(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(2))) + " ISK"
    }

    /// "5д 21ч" / "5d 21h": time left until a date.
    private func durationText(until date: Date) -> String {
        let r = max(0, date.timeIntervalSinceNow)
        let f = DateComponentsFormatter()
        f.allowedUnits = r >= 86_400 ? [.day, .hour] : r >= 3_600 ? [.hour, .minute] : [.minute, .second]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        return f.string(from: r) ?? "—"
    }

    private func romanNumeral(_ n: Int) -> String {
        ["0","I","II","III","IV","V"][max(0, min(5, n))]
    }
}
