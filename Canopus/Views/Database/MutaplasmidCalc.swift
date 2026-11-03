// Mutaplasmid calculator (importer 7): pick a module and a mutaplasmid, see each attribute's range — the
// module's own value times the mutaplasmid's min…max — and set where each roll landed to get the abyssal
// module's numbers, better or worse than the original.

import SwiftUI
import Domain
import EVEStaticData

struct MutaplasmidCalc: View {
    @Environment(AppEnvironment.self) private var env
    @State private var mutable: Set<Int>?
    @State private var query = ""
    @State private var hits: [ItemType] = []
    @State private var module: ItemType?
    @State private var options: [MutaplasmidOption] = []
    @State private var chosen: MutaplasmidOption?
    @State private var ranges: [MutaplasmidRange] = []
    @State private var base: [Int: Double] = [:]
    /// Where each attribute's roll landed, 0 = min … 1 = max of the multiplier
    @State private var rolls: [Int: Double] = [:]
    @State private var resultName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let mutable, mutable.isEmpty {
                Card { Text("The SDE database has no mutaplasmids yet. Update the database in Settings.").font(.ui(13)).foregroundStyle(C.muted) }
            } else {
                Card(String(localized: "Mutaplasmids")) {
                    Text("Module").font(.ui(11)).foregroundStyle(C.muted)
                    TextField("e.g. 10MN Afterburner II, Large Shield Extender II", text: $query)
                        .font(.ui(14)).autocorrectionDisabled().textInputAutocapitalization(.never)
                        .padding(.horizontal, 10).frame(minHeight: 38)
                        .background(C.panel2, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(C.border))
                    ForEach(hits) { t in
                        Button { pick(t) } label: { MarketTypeRow(type: t) }.buttonStyle(.plain)
                    }
                    if module != nil {
                        if options.isEmpty {
                            Text("No mutaplasmid applies to this module.").font(.ui(12)).foregroundStyle(C.muted)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(options) { o in
                                        Button(o.name.replacingOccurrences(of: " Mutaplasmid", with: "")) { Task { await choose(o) } }
                                            .buttonStyle(CanopusButtonStyle(kind: chosen?.id == o.id ? .primary : .ghost, small: true))
                                    }
                                }
                            }
                        }
                    }
                }
                if let chosen, !ranges.isEmpty { result(chosen) }
                Text("Each attribute rolls independently between the mutaplasmid's minimum and maximum multiplier of the module's own value. Set the slider to where your roll landed — or check what a perfect or a bad roll gives.")
                    .font(.ui(11)).foregroundStyle(C.faint)
            }
        }
        .task(id: env.repositoryVersion) {
            mutable = (try? await env.repository?.mutableTypeIds()) ?? []
            #if DEBUG
            // Debug builds: `-mutaModule 3841` picks a module (screenshots).
            let id = UserDefaults.standard.integer(forKey: "mutaModule")
            if id > 0, module == nil, let t = try? await env.repository?.types(ids: [id])[id] { pick(t) }
            #endif
        }
        .task(id: query) { await search() }
    }

    @ViewBuilder private func result(_ o: MutaplasmidOption) -> some View {
        Card {
            HStack(spacing: 8) {
                EVETypeIcon(typeId: o.resultTypeId, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: o.name).font(.ui(13, .semibold)).foregroundStyle(C.text)
                    Text(verbatim: "\(module?.name ?? "") → \(resultName)").font(.ui(11)).foregroundStyle(C.muted)
                }
                Spacer(minLength: 4)
            }
            HStack(spacing: 6) {
                Button("Worst") { setAll(good: false) }.buttonStyle(.canopusSmall)
                Button("Average") { rolls = Dictionary(uniqueKeysWithValues: ranges.map { ($0.attributeId, 0.5) }) }.buttonStyle(.canopusSmall)
                Button("Best") { setAll(good: true) }.buttonStyle(.canopusSmall)
            }
            ForEach(ranges) { r in row(r) }
        }
    }

    private func row(_ r: MutaplasmidRange) -> some View {
        let b = base[r.attributeId] ?? 0
        let roll = rolls[r.attributeId] ?? 0.5
        let mult = r.min + (r.max - r.min) * roll
        let value = b * mult
        // Better when the value moves the way the attribute wants.
        let better = r.highIsGood ? value > b : value < b
        let change = b != 0 ? (value / b - 1) * 100 : 0
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(verbatim: r.name).font(.ui(12, .medium)).foregroundStyle(C.text).lineLimit(1)
                Spacer(minLength: 4)
                Text(verbatim: formatValue(value, unit: r.unitId, unitName: r.unitName)).font(.mono(12, medium: true))
                    .foregroundStyle(abs(change) < 0.05 ? C.text : better ? C.good : C.bad)
                Text(verbatim: String(format: "%+.1f%%", change)).font(.mono(10)).foregroundStyle(C.muted).frame(width: 52, alignment: .trailing)
            }
            Slider(value: Binding(get: { roll }, set: { rolls[r.attributeId] = $0 }), in: 0...1).tint(C.accent)
            HStack {
                Text(verbatim: formatValue(b * r.min, unit: r.unitId, unitName: r.unitName))
                Spacer()
                Text("base \(formatValue(b, unit: r.unitId, unitName: r.unitName))")
                Spacer()
                Text(verbatim: formatValue(b * r.max, unit: r.unitId, unitName: r.unitName))
            }
            .font(.mono(10)).foregroundStyle(C.faint)
        }
        .padding(.vertical, 3)
    }

    /// Every roll at the best (or worst) end for its attribute.
    private func setAll(good: Bool) {
        rolls = Dictionary(uniqueKeysWithValues: ranges.map { r in
            let b = base[r.attributeId] ?? 0
            // Which end raises the value depends on the sign of the base value too.
            let maxRaises = b >= 0
            let wantRaise = r.highIsGood == good
            return (r.attributeId, wantRaise == maxRaises ? 1.0 : 0.0)
        })
    }

    private func pick(_ t: ItemType) {
        module = t
        query = t.name
        hits = []
        Task {
            options = (try? await env.repository?.mutaplasmids(forModule: t.id)) ?? []
            base = (try? await env.repository?.typeAttributeMaps(typeIds: [t.id])[t.id]) ?? [:]
            if let first = options.first { await choose(first) } else { chosen = nil; ranges = [] }
        }
    }

    private func choose(_ o: MutaplasmidOption) async {
        chosen = o
        resultName = (try? await env.repository?.types(ids: [o.resultTypeId])[o.resultTypeId]?.name) ?? ""
        ranges = ((try? await env.repository?.mutaplasmidRanges(o.id)) ?? []).filter { base[$0.attributeId] != nil }
        rolls = Dictionary(uniqueKeysWithValues: ranges.map { ($0.attributeId, 0.5) })
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, q != module?.name, let repo = env.repository, let mutable else { hits = []; return }
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }
        hits = Array(((try? await repo.search(q)) ?? []).filter { mutable.contains($0.id) }.prefix(8))
    }
}
