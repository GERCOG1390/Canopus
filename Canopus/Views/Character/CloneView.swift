import SwiftUI
import EVEAuth
import EVEStaticData
import Domain

struct CloneView: View {
    let characterService: CharacterService
    @Environment(AppEnvironment.self) private var env
    @State private var implantTypeIds: [Int] = []
    @State private var implantNames: [Int: String] = [:]
    @State private var homeLocation: ESIHomeLocation?
    @State private var homeName: String?
    @State private var lastChange: Date?
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        List {
            Section("Home Station") {
                if let loc = homeLocation {
                    HStack(spacing: 12) {
                        Image(systemName: loc.locationType == "station" ? "building.2" : "hexagon")
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(homeName ?? "Location \(loc.locationId)")
                                .font(.body)
                            if let changed = lastChange {
                                Text("Last changed: " + changed.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Last changed: Never")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                } else if !isLoading {
                    Text("No home station set").foregroundStyle(.secondary)
                }
            }

            Section(implantTypeIds.isEmpty ? "Implants" : "Implants (\(implantTypeIds.count))") {
                if implantTypeIds.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No Implants",
                        systemImage: "brain.head.profile",
                        description: Text("No implants installed.")
                    )
                } else {
                    ForEach(implantTypeIds, id: \.self) { typeId in
                        HStack(spacing: 12) {
                            EVETypeIcon(typeId: typeId, size: 36)
                            Text(implantNames[typeId] ?? "Implant \(typeId)")
                                .font(.body)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .eveTabBarClearance()
        .navigationTitle("Clone Status")
        .navigationBarTitleDisplayMode(.large)
        .overlay { if isLoading { ProgressView() } }
        .task { await load() }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Retry") { Task { await load() } }
            Button("Dismiss", role: .cancel) {}
        } message: { Text(error?.localizedDescription ?? "") }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            async let imp   = characterService.implants()
            async let clone = characterService.clones()
            let (ids, info) = try await (imp, clone)
            implantTypeIds = ids.sorted()
            homeLocation   = info.homeLocation
            lastChange     = info.lastStationChangeDate

            // Resolve home station name
            if let loc = info.homeLocation {
                if loc.locationType == "station",
                   let st = try? await characterService.stationInfo(id: loc.locationId) {
                    homeName = st.name
                } else if let st = try? await characterService.structureInfo(id: loc.locationId) {
                    homeName = st.name
                }
            }

            // Resolve implant names from SDE
            if let repo = env.repository,
               let map = try? await repo.types(ids: Set(ids)) {
                for (id, t) in map { implantNames[id] = t.name }
            }
        } catch {
            self.error = error
        }
    }
}
