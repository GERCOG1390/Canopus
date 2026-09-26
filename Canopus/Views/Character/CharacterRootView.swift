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
            Color.eveBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerRow
                    if let e = activeEntry { trainingCard(e) }
                    statRow
                    alertsBlock
                    hangarBlock
                    commandBlock
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, EVELayout.scrollBottomClearance)
            }

            // Character switcher overlay
            if switcherOpen { switcherOverlay }
        }
        .navigationTitle("")
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

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 13) {
            // Portrait
            EVECharacterPortrait(characterId: charId, size: 46)
                .clipShape(CutCorner(size: 9))
                .overlay(CutCorner(size: 9).stroke(Color.white.opacity(0.14), lineWidth: 1))

            // Name + corp
            Button { withAnimation(.easeInOut(duration: 0.2)) { switcherOpen.toggle() } } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(charName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.eveText)
                        Text("▾")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.eveAmber)
                    }
                    Text(corpInfo?.name ?? "")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.eveText.opacity(0.45))
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(alignment: .trailing, spacing: 7) {
                // Clone type badge
                Text(charInfo?.securityStatus != nil ? "OMEGA" : "CAPSULEER")
                    .font(.system(size: 7.5, weight: .bold))
                    .tracking(1.4)
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .foregroundStyle(Color.eveAmber)
                    .overlay(CutCorner(size: 3).stroke(Color.eveAmber.opacity(0.5), lineWidth: 1))

                // Server status
                if let s = serverStatus {
                    HStack(spacing: 4) {
                        Circle().fill(Color.eveGreen).frame(width: 5, height: 5)
                        Text(s.players.formatted())
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color.eveText.opacity(0.38))
                    }
                } else {
                    HStack(spacing: 4) {
                        Circle().fill(Color.eveRed).frame(width: 5, height: 5)
                        Text("OFFLINE")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1.0)
                            .foregroundStyle(Color.eveRed.opacity(0.8))
                    }
                }
            }
        }
        .padding(.bottom, 2)
        .overlay(alignment: .bottom) {
            Color.eveAmber.opacity(0.16).frame(height: 1)
        }
        .padding(.bottom, 14)
    }

    // MARK: - Training card

    private func trainingCard(_ entry: SkillQueueEntry) -> some View {
        Button { switchToTab(.skills) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("NOW TRAINING")
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(2.2)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.eveCyan)
                    Spacer()
                    Text("\(skillQueue.count) IN QUEUE")
                        .font(.system(size: 9.5, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(Color.eveText.opacity(0.38))
                }

                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(entry.skillName ?? "Skill \(entry.skillId)")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.eveText)
                    Text(romanNumeral(entry.finishedLevel))
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.eveAmber)
                }
                .padding(.top, 11)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 5)
                        Rectangle().fill(Color.eveCyan).frame(width: geo.size.width * entry.progress, height: 5)
                    }
                }
                .frame(height: 5)
                .padding(.top, 13)

                HStack {
                    Text(entry.remainingText)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.eveText)
                    Spacer()
                    Text(String(format: "%.0f%%", entry.progress * 100))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.eveText.opacity(0.38))
                }
                .padding(.top, 9)
            }
            .padding(14)
            .eveCard(cut: 12, border: Color.eveCyan.opacity(0.28))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stat tiles

    private var statRow: some View {
        HStack(spacing: 10) {
            Button { switchToTab(.wallet) } label: {
                statTile(
                    label: "WALLET",
                    value: walletBalance.map(iskFormatted) ?? "—",
                    sub: nil
                )
            }
            .buttonStyle(.plain)

            statTile(
                label: "SKILL POINTS",
                value: totalSP.map(spFormatted) ?? "—",
                sub: skillQueue.isEmpty ? "Queue empty" : "\(skillQueue.count) in queue"
            )
        }
    }

    private func statTile(label: String, value: String, sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).hudLabel()
            Text(value)
                .font(.system(size: 17, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.eveText)
                .padding(.top, 8)
            if let sub {
                Text(sub)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(sub.lowercased().contains("empty")
                                     ? Color.eveAmber.opacity(0.8)
                                     : Color.eveText.opacity(0.38))
                    .padding(.top, 5)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eveCard()
    }

    // MARK: - Alerts

    private struct EVEAlert {
        let title: String
        let subtitle: String
        let value: String
        let color: Color
    }

    private var computedAlerts: [EVEAlert] {
        var a: [EVEAlert] = []
        if skillQueue.isEmpty {
            a.append(.init(title: "Skill queue empty",
                           subtitle: charName, value: "NOW", color: .eveAmber))
        } else if skillQueue.count == 1,
                  let e = skillQueue.first, let f = e.finishDate,
                  f.timeIntervalSinceNow < 86400 {
            a.append(.init(title: "Queue ends soon",
                           subtitle: e.skillName ?? "Last skill",
                           value: e.remainingText, color: .eveCyan))
        }
        if serverStatus == nil {
            a.append(.init(title: "Server offline",
                           subtitle: "Tranquility", value: "OFFLINE", color: .eveRed))
        }
        return a
    }

    @ViewBuilder
    private var alertsBlock: some View {
        let alerts = computedAlerts
        if !alerts.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("ALERTS").hudLabel()
                    Spacer()
                    Text("\(alerts.count) ACTIVE")
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.eveAmber)
                }
                ForEach(Array(alerts.enumerated()), id: \.offset) { _, alert in
                    alertRow(alert)
                }
            }
        }
    }

    private func alertRow(_ alert: EVEAlert) -> some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text(alert.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.eveText)
                Text(alert.subtitle)
                    .font(.system(size: 10.5))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.eveText.opacity(0.42))
            }
            Spacer()
            Text(alert.value)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundStyle(alert.color)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Color.eveCard)
        .overlay(alignment: .leading) {
            Rectangle().fill(alert.color).frame(width: 2)
        }
        .overlay(Rectangle().stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    // MARK: - Hangar

    @ViewBuilder
    private var hangarBlock: some View {
        if let ship {
            VStack(alignment: .leading, spacing: 9) {
                Text("HANGAR").hudLabel()
                NavigationLink(value: Destination.activeShipFit) {
                    HStack(spacing: 13) {
                        EVERenderImage(typeId: ship.shipTypeId, size: 44)
                            .clipShape(CutCorner(size: 7))
                            .overlay(CutCorner(size: 7).stroke(Color.white.opacity(0.10), lineWidth: 1))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(ship.shipName)
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(Color.eveText)
                                .lineLimit(1)
                            Text((shipTypeName ?? "Ship") + " · Active ship")
                                .font(.system(size: 10.5))
                                .tracking(1.0)
                                .textCase(.uppercase)
                                .foregroundStyle(Color.eveGreen)
                                .lineLimit(1)
                            if let shipLocation {
                                Text(shipLocation.displayText)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Color.eveText.opacity(0.42))
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text("›")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.eveText.opacity(0.3))
                    }
                    .padding(13)
                    .eveCard()
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Command links

    private var commandBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("COMMAND").hudLabel()

            let links: [(String, String, Destination)] = [
                ("Character Sheet",  "person.text.rectangle.fill",   .characterSheet),
                ("Wealth Overview",  "chart.pie.fill",                .wealth),
                ("EVE Mail",          "envelope.fill",                 .mail),
                ("Transactions",      "arrow.left.arrow.right",        .transactions),
                ("Mining Ledger",     "cube.fill",                     .mining),
                ("Fittings",          "wrench.and.screwdriver.fill",   .fittings),
                ("Kill Board",        "xmark.shield.fill",             .killboard),
                ("Clone & Implants",  "brain.head.profile",            .clone),
                ("Loyalty Points",   "star.circle.fill",              .loyalty),
                ("Wallet Journal",   "creditcard.and.123",            .journal),
                ("Industry Jobs",    "hammer.fill",                   .industry),
                ("Market Orders",    "chart.line.uptrend.xyaxis",     .orders),
                ("Contracts",        "doc.richtext.fill",             .contracts),
            ]

            ForEach(links, id: \.0) { title, icon, dest in
                NavigationLink(value: dest) {
                    HStack(spacing: 12) {
                        Image(systemName: icon)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.eveAmber)
                            .frame(width: 20)
                        Text(title)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Color.eveText)
                        Spacer()
                        Text("›")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.eveText.opacity(0.28))
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .eveCard()
                }
                .buttonStyle(.plain)
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
            ship = shipInfo
            corpInfo = try? await service.corporationInfo(corpId: info.corporationId)
            shipLocation = nil

            if let repo = env.repository {
                skillQueue = try await resolveQueueNames(rawQueue, repo: repo)
                shipTypeName = try? await repo.type(id: shipInfo.shipTypeId)?.name
            } else {
                skillQueue = rawQueue.map { makeEntry($0) }
            }

            if let location = try? await service.location() {
                shipLocation = await resolveShipLocation(location, service: service)
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

    private func iskFormatted(_ v: Double) -> String {
        if v >= 1_000_000_000 { return String(format: "%.2f B", v / 1_000_000_000) }
        if v >= 1_000_000     { return String(format: "%.2f M", v / 1_000_000) }
        return String(format: "%.0f", v)
    }

    private func spFormatted(_ v: Int) -> String {
        if v >= 1_000_000 { return String(format: "%.1f M", Double(v) / 1_000_000) }
        if v >= 1_000     { return String(format: "%.0f K", Double(v) / 1_000) }
        return "\(v)"
    }

    private func romanNumeral(_ n: Int) -> String {
        ["0","I","II","III","IV","V"][max(0, min(5, n))]
    }
}
