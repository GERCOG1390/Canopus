import SwiftUI
import EVEAuth
import EVEStaticData
import Domain

/// Clones and implants as on the desktop: jump clones and the clone-jump cooldown, free remaps, the home
/// station, attributes (base and implant bonuses), the active clone's implants by slot, and each jump clone.
struct CloneView: View {
    let characterService: CharacterService
    @Environment(AppEnvironment.self) private var env
    @State private var clones: ESIClonesInfo?
    @State private var implants: [Int] = []
    @State private var attrs: ESICharacterAttributes?
    @State private var infomorphSync = 0
    @State private var names: [Int: String] = [:]
    @State private var slots: [Int: Int] = [:]
    @State private var bonuses: [Int: [Int: Double]] = [:]
    @State private var locations: [Int: String] = [:]
    @State private var isLoading = true
    @State private var error: Error?

    /// Attribute → the implant attribute that raises it (charisma … willpower).
    private static let attributes: [(id: Int, bonus: Int, name: LocalizedStringKey)] = [
        (165, 176, "Intelligence"),
        (166, 177, "Memory"),
        (167, 178, "Perception"),
        (168, 179, "Willpower"),
        (164, 175, "Charisma"),
    ]
    private static let infomorphSynchronizing = 33399
    private static let implantSlotAttr = 331

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                stats
                attributesCard
                Card(title: "Active clone: implants", actions: { EmptyView() }) {
                    if implants.isEmpty && !isLoading {
                        Text("No implants").font(.ui(14)).foregroundStyle(C.muted)
                    }
                    implantList(implants)
                }
                jumpClonesCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, EVELayout.scrollBottomClearance)
        }
        .background(C.bg)
        .overlay { if isLoading && clones == nil { ProgressView() } }
        .refreshable { await load() }
        .navigationTitle("Clones & implants")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: env.repositoryVersion) { await load() }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Retry") { Task { await load() } }
            Button("Dismiss", role: .cancel) {}
        } message: { Text(error?.localizedDescription ?? "") }
    }

    // MARK: - Stats

    private var nextJump: Date? {
        guard let last = clones?.lastCloneJumpDate else { return nil }
        let next = last.addingTimeInterval(Double(24 - infomorphSync) * 3_600)
        return next > Date() ? next : nil
    }

    private var stats: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            StatTile(label: "Jump clones", value: clones.map { "\($0.jumpClones?.count ?? 0)" } ?? "—")
            StatTile(
                label: "Clone jump",
                value: clones == nil ? "—" : nextJump.map { Fmt.duration(until: $0) } ?? String(localized: "available"),
                sub: clones?.lastCloneJumpDate.map { String(localized: "last: \($0.formatted(date: .abbreviated, time: .omitted))") },
                valueColor: nextJump == nil && clones != nil ? C.good : C.text
            )
            StatTile(
                label: "Free remaps",
                value: attrs.map { "\($0.bonusRemaps ?? 0)" } ?? "—",
                sub: attrs?.accruedRemapCooldownDate.flatMap { $0 > Date() ? String(localized: "next: \($0.formatted(date: .abbreviated, time: .omitted))") : nil }
            )
            StatTile(
                label: "Home station",
                value: clones?.homeLocation.flatMap { locations[$0.locationId] } ?? "—",
                sub: clones?.lastStationChangeDate.map { String(localized: "changed: \($0.formatted(date: .abbreviated, time: .omitted))") }
            )
        }
    }

    // MARK: - Attributes

    /// Implant bonus per attribute for the active clone.
    private var implantBonus: [Int: Int] {
        var out: [Int: Int] = [:]
        for imp in implants {
            for a in Self.attributes { out[a.id, default: 0] += Int(bonuses[imp]?[a.bonus] ?? 0) }
        }
        return out
    }

    /// ESI's attribute numbers: whether they already include implants isn't documented. A character's own
    /// attributes always add up to 99 (5 × 17 + 14), so a larger sum means the implants are in (the desktop
    /// checks it against the skill in training; the sum is enough here).
    private func baseAndTotal(_ esi: Int, _ attrId: Int, _ a: ESICharacterAttributes) -> (base: Int, total: Int) {
        let sum = a.charisma + a.intelligence + a.memory + a.perception + a.willpower
        let bonusSum = implantBonus.values.reduce(0, +)
        let included = bonusSum > 0 && sum >= 99 + bonusSum
        let bonus = implantBonus[attrId] ?? 0
        return included ? (esi - bonus, esi) : (esi, esi + bonus)
    }

    private func esiValue(_ id: Int, _ a: ESICharacterAttributes) -> Int {
        switch id {
        case 164: a.charisma
        case 165: a.intelligence
        case 166: a.memory
        case 167: a.perception
        default: a.willpower
        }
    }

    private var attributesCard: some View {
        Card("Attributes") {
            if let a = attrs {
                VStack(spacing: 0) {
                    HStack {
                        Text("Attribute")
                        Spacer()
                        Text("Base").frame(width: 50, alignment: .trailing)
                        Text("Implants").frame(width: 72, alignment: .trailing)
                        Text("Total").frame(width: 50, alignment: .trailing)
                    }
                    .font(.ui(11, .medium))
                    .textCase(.uppercase)
                    .foregroundStyle(C.muted)
                    .padding(.bottom, 6)
                    ForEach(Self.attributes, id: \.id) { attr in
                        let v = baseAndTotal(esiValue(attr.id, a), attr.id, a)
                        Rectangle().fill(C.border).frame(height: 1)
                        HStack {
                            GameIcon.attribute(attr.id, size: 22)
                            Text(attr.name).foregroundStyle(C.text)
                            Spacer()
                            Text("\(v.base)").frame(width: 50, alignment: .trailing).foregroundStyle(C.text2)
                            Text(v.total > v.base ? "+\(v.total - v.base)" : "").frame(width: 72, alignment: .trailing).foregroundStyle(C.good)
                            Text("\(v.total)").font(.ui(14, .bold)).frame(width: 50, alignment: .trailing).foregroundStyle(C.text)
                        }
                        .font(.ui(14))
                        .monospacedDigit()
                        .padding(.vertical, 8)
                    }
                }
                if let last = a.lastRemapDate {
                    Text("Last remap: \(last.formatted(date: .abbreviated, time: .omitted))")
                        .font(.ui(12))
                        .foregroundStyle(C.muted)
                }
            } else if !isLoading {
                Text("No attribute data").font(.ui(14)).foregroundStyle(C.muted)
            }
        }
    }

    // MARK: - Implants and jump clones

    private func implantList(_ list: [Int]) -> some View {
        VStack(spacing: 8) {
            ForEach(list.sorted { (slots[$0] ?? 0) < (slots[$1] ?? 0) }, id: \.self) { imp in
                HStack(spacing: 10) {
                    Text(slots[imp].map { "\($0)" } ?? "—")
                        .font(.ui(12, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(C.muted)
                        .frame(width: 20)
                    EVETypeIcon(typeId: imp, size: 26)
                    Text(names[imp] ?? "#\(imp)")
                        .font(.ui(14))
                        .foregroundStyle(C.accentText)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private var jumpClonesCard: some View {
        let list = clones?.jumpClones ?? []
        Card("Jump clones") {
            if list.isEmpty && !isLoading {
                Text("No jump clones").font(.ui(14)).foregroundStyle(C.muted)
            }
            ForEach(list) { c in
                VStack(alignment: .leading, spacing: 8) {
                    Text(c.name?.isEmpty == false ? c.name! : locations[c.locationId] ?? String(localized: "Location \(c.locationId)"))
                        .font(.ui(15, .medium))
                        .foregroundStyle(C.text)
                    if c.name?.isEmpty == false, let loc = locations[c.locationId] {
                        Text(loc).font(.ui(12)).foregroundStyle(C.muted)
                    }
                    if c.implants.isEmpty {
                        Text("no implants").font(.ui(12)).foregroundStyle(C.faint)
                    } else {
                        implantList(c.implants)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .canopusSurface(nested: true, padding: 12)
            }
        }
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            async let imp = characterService.implants()
            async let cl = characterService.clones()
            async let at = characterService.characterAttributes()
            async let sk = characterService.skills()
            let (ids, info) = try await (imp, cl)
            implants = ids
            clones = info
            attrs = try? await at
            infomorphSync = (try? await sk)?.skills.first { $0.skillId == Self.infomorphSynchronizing }?.activeSkillLevel ?? 0

            let allImplants = Set(ids + (info.jumpClones ?? []).flatMap(\.implants))
            if let repo = env.repository {
                if let map = try? await repo.types(ids: allImplants) { names = map.mapValues(\.name) }
                if let attrMap = try? await repo.typeAttributeMaps(typeIds: allImplants) {
                    bonuses = attrMap
                    slots = attrMap.compactMapValues { $0[Self.implantSlotAttr].map { Int($0) } }
                }
            }

            var locIds = (info.jumpClones ?? []).map { ($0.locationId, $0.locationType) }
            if let h = info.homeLocation { locIds.append((h.locationId, h.locationType)) }
            for (id, kind) in locIds where locations[id] == nil {
                if kind == "station", let st = try? await characterService.stationInfo(id: id) {
                    locations[id] = st.name
                } else if let st = try? await characterService.structureInfo(id: id) {
                    locations[id] = st.name
                }
            }
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }
}
