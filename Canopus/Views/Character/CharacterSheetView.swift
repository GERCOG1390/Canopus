import SwiftUI
import EVEAuth
import EVEStaticData
import Domain

struct CharacterSheetView: View {
    let characterService: CharacterService
    @Environment(AppEnvironment.self) private var env

    @State private var charInfo: ESICharacterInfo?
    @State private var attrs: ESICharacterAttributes?
    @State private var location: ESICharacterLocation?
    @State private var ship: ESICurrentShip?
    @State private var history: [ESIEmploymentHistoryItem] = []

    // Resolved names
    @State private var systemName: String?
    @State private var systemSecurity: Double?
    @State private var stationName: String?
    @State private var shipTypeName: String?
    @State private var corpNames: [Int: String] = [:]
    @State private var corpTickers: [Int: String] = [:]

    @State private var isLoading = true
    @State private var error: Error?

    private var charId: Int { characterService.tokens.characterId }
    private var charName: String { characterService.tokens.characterName }

    var body: some View {
        ZStack {
            Color.eveBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroSection
                    divider

                    if let info = charInfo {
                        identitySection(info)
                        divider
                    }

                    locationSection
                    divider

                    if let a = attrs {
                        attributesSection(a)
                        divider
                    }

                    if !history.isEmpty {
                        employmentSection
                    }
                }
                .padding(.bottom, 40)
            }
            if isLoading { ProgressView().tint(Color.eveCyan) }
        }
        .navigationTitle("CHARACTER")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.eveBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
        .alert("Error", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } })
        ) {
            Button("Retry") { Task { await load() } }
            Button("Dismiss", role: .cancel) {}
        } message: { Text(error?.localizedDescription ?? "") }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Full-width portrait
            EVEHeroPortrait(characterId: charId, height: 200)

            // Gradient fade
            LinearGradient(
                colors: [.clear, Color.eveBackground.opacity(0.98)],
                startPoint: .center, endPoint: .bottom
            )
            .frame(height: 140)

            // Name + security status overlay
            VStack(alignment: .leading, spacing: 5) {
                Text(charName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.eveText)

                if let sec = charInfo?.securityStatus {
                    HStack(spacing: 6) {
                        Text(String(format: "%.1f", sec))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(secColor(sec))
                        Text("SECURITY STATUS")
                            .font(.system(size: 9.5, weight: .semibold))
                            .tracking(1.8)
                            .foregroundStyle(Color.eveText.opacity(0.38))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Identity

    private func identitySection(_ info: ESICharacterInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("IDENTITY").hudLabel().padding(.horizontal, 20)

            VStack(spacing: 0) {
                if let bday = info.birthday {
                    infoRow(label: "BIRTHDAY", value: bday.formatted(date: .abbreviated, time: .omitted))
                    thinDivider
                    infoRow(label: "AGE", value: ageString(from: bday))
                    thinDivider
                }
                if let race = raceName(info.raceId) {
                    infoRow(label: "RACE", value: race)
                    thinDivider
                }
                infoRow(
                    label: "CORP",
                    value: (corpNames[info.corporationId] ?? "Corp \(info.corporationId)")
                        + (corpTickers[info.corporationId].map { " [\($0)]" } ?? "")
                )
            }
            .padding(.horizontal, 20)

            if let desc = info.description, !desc.isEmpty {
                let stripped = desc.strippedEVEHTML
                if !stripped.isEmpty {
                    Text(stripped)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.eveText.opacity(0.55))
                        .lineLimit(6)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 16)
    }

    // MARK: - Location

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CURRENT STATUS").hudLabel().padding(.horizontal, 20)

            VStack(spacing: 0) {
                if let sysName = systemName {
                    HStack {
                        Text("SYSTEM")
                            .font(.system(size: 9.5, weight: .semibold))
                            .tracking(1.8)
                            .foregroundStyle(Color.eveText.opacity(0.38))
                        Spacer()
                        HStack(spacing: 6) {
                            if let sec = systemSecurity {
                                Text(String(format: "%.1f", sec))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(secClass(sec).color)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .overlay(CutCorner(size: 3).stroke(secClass(sec).color.opacity(0.4), lineWidth: 1))
                            }
                            Text(sysName)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.eveText)
                        }
                    }
                    .padding(.vertical, 11)
                    thinDivider
                }

                infoRow(
                    label: "DOCKED AT",
                    value: stationName ?? (location?.stationId == nil ? "In space" : "Station \(location?.stationId ?? 0)")
                )
                thinDivider

                if let s = ship {
                    infoRow(
                        label: "ACTIVE SHIP",
                        value: "\(s.shipName) · \(shipTypeName ?? "Ship \(s.shipTypeId)")"
                    )
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 16)
    }

    // MARK: - Attributes

    private func attributesSection(_ a: ESICharacterAttributes) -> some View {
        let attrList: [(String, Int, Color)] = [
            ("PERCEPTION",   a.perception,   Color(red: 0.40, green: 0.80, blue: 1.00)),
            ("MEMORY",       a.memory,       Color(red: 0.50, green: 1.00, blue: 0.60)),
            ("WILLPOWER",    a.willpower,    Color(red: 1.00, green: 0.50, blue: 0.30)),
            ("INTELLIGENCE", a.intelligence, Color(red: 0.85, green: 0.60, blue: 1.00)),
            ("CHARISMA",     a.charisma,     Color(red: 1.00, green: 0.80, blue: 0.20)),
        ]
        let maxVal = attrList.map(\.1).max() ?? 30

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("BASE ATTRIBUTES").hudLabel()
                Spacer()
                if let remap = a.lastRemapDate {
                    Text("LAST REMAP \(remap.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 8.5))
                        .tracking(1.0)
                        .foregroundStyle(Color.eveText.opacity(0.28))
                }
            }
            .padding(.horizontal, 20)

            VStack(spacing: 9) {
                ForEach(attrList, id: \.0) { name, value, color in
                    attrBar(label: name, value: value, max: maxVal + 4, color: color)
                }
            }
            .padding(.horizontal, 20)

            if let remaps = a.bonusRemaps, remaps > 0 {
                Text("\(remaps) BONUS REMAP\(remaps > 1 ? "S" : "") AVAILABLE")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(Color.eveAmber)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 16)
    }

    private func attrBar(label: String, value: Int, max: Int, color: Color) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Color.eveText.opacity(0.42))
                .frame(width: 90, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.06))
                    Rectangle()
                        .fill(color.opacity(0.85))
                        .frame(width: geo.size.width * CGFloat(value) / CGFloat(max))
                }
            }
            .frame(height: 4)
            .clipShape(Rectangle())

            Text("\(value)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 28, alignment: .trailing)
        }
    }

    // MARK: - Employment history

    private var employmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EMPLOYMENT HISTORY · \(history.count)").hudLabel().padding(.horizontal, 20)

            VStack(spacing: 8) {
                ForEach(history.prefix(15)) { item in
                    HStack(spacing: 12) {
                        EVECorpLogo(corpId: item.corporationId, size: 36)
                            .clipShape(CutCorner(size: 6))
                            .overlay(CutCorner(size: 6).stroke(Color.white.opacity(0.10), lineWidth: 1))

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(corpNames[item.corporationId] ?? "Corp \(item.corporationId)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.eveText)
                                if let ticker = corpTickers[item.corporationId] {
                                    Text("[\(ticker)]")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Color.eveText.opacity(0.38))
                                }
                            }
                            Text(item.startDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 10.5))
                                .tracking(1.0)
                                .foregroundStyle(Color.eveText.opacity(0.38))
                        }

                        Spacer()

                        if item.corporationId == charInfo?.corporationId {
                            Text("CURRENT")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(Color.eveCyan)
                                .padding(.horizontal, 5).padding(.vertical, 3)
                                .overlay(CutCorner(size: 3).stroke(Color.eveCyan.opacity(0.4), lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 16)
        }
        .padding(.top, 16)
    }

    // MARK: - Shared components

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(Color.eveText.opacity(0.38))
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(Color.eveText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
    }

    private var divider: some View {
        Color.eveAmber.opacity(0.14).frame(height: 1)
    }

    private var thinDivider: some View {
        Color.white.opacity(0.06).frame(height: 1)
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            async let ci = characterService.characterInfo()
            async let at = characterService.characterAttributes()
            async let lo = characterService.location()
            async let sh = characterService.currentShip()
            async let eh = characterService.employmentHistory()

            let (info, attributes, loc, shipInfo, hist) =
                try await (ci, at, lo, sh, eh)

            charInfo = info
            attrs = attributes
            location = loc
            ship = shipInfo
            history = hist.sorted { $0.startDate > $1.startDate }

            // Resolve corp for current char
            if let corp = try? await characterService.corporationInfo(corpId: info.corporationId) {
                corpNames[info.corporationId] = corp.name
                corpTickers[info.corporationId] = corp.ticker
            }

            // Resolve location names
            async let sysInfo = characterService.systemInfo(id: loc.solarSystemId)
            if let sys = try? await sysInfo {
                systemName = sys.name
                systemSecurity = sys.securityStatus
            }
            if let stId = loc.stationId,
               let st = try? await characterService.stationInfo(id: stId) {
                stationName = st.name
            } else if let structId = loc.structureId,
                      let st = try? await characterService.structureInfo(id: structId) {
                stationName = st.name
            } else if loc.stationId == nil && loc.structureId == nil {
                stationName = "In space"
            }

            // Resolve ship type name
            if let repo = env.repository {
                shipTypeName = try? await repo.type(id: shipInfo.shipTypeId)?.name
            }

            // Resolve corp names for history (recent 10, skip current corp already resolved)
            let historyCorps = Set(hist.prefix(10).map(\.corporationId))
                .subtracting([info.corporationId])
            for corpId in historyCorps {
                if let corp = try? await characterService.corporationInfo(corpId: corpId) {
                    corpNames[corpId] = corp.name
                    corpTickers[corpId] = corp.ticker
                }
            }
        } catch {
            self.error = error
        }
    }

    // MARK: - Helpers

    private func ageString(from date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month], from: date, to: Date())
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        if y == 0 { return "\(m) months" }
        if m == 0 { return "\(y) years" }
        return "\(y) years \(m) months"
    }

    private func raceName(_ raceId: Int?) -> String? {
        switch raceId {
        case 1:  return "Caldari"
        case 2:  return "Minmatar"
        case 4:  return "Amarr"
        case 8:  return "Gallente"
        case 135: return "Jove"
        default: return nil
        }
    }

    private func secColor(_ sec: Double) -> Color {
        if sec >= 5.0 { return Color(red: 0.30, green: 0.85, blue: 1.00) }
        if sec >= 1.0 { return Color(red: 0.30, green: 0.85, blue: 0.42) }
        if sec >= 0.1 { return Color(red: 0.72, green: 0.88, blue: 0.30) }
        if sec >= 0   { return .secondary }
        if sec >= -5  { return .orange }
        return Color(red: 0.90, green: 0.20, blue: 0.22)
    }

    private struct SecClass { let label: String; let color: Color }
    private func secClass(_ sec: Double) -> SecClass {
        if sec >= 0.5 { return .init(label: "HIGH SEC", color: Color.eveGreen) }
        if sec > 0.0  { return .init(label: "LOW SEC",  color: Color.eveAmber) }
        return              .init(label: "NULL SEC", color: Color.eveRed)
    }
}
