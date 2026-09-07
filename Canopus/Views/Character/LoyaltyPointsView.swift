import SwiftUI
import EVEAuth

struct LoyaltyPointsView: View {
    let characterService: CharacterService
    @State private var points: [ESILoyaltyPoint] = []
    @State private var corpNames: [Int: String] = [:]
    @State private var isLoading = true
    @State private var error: Error?

    private var sorted: [ESILoyaltyPoint] {
        points.sorted { $0.loyaltyPoints > $1.loyaltyPoints }
    }

    private var totalLP: Int { points.reduce(0) { $0 + $1.loyaltyPoints } }

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Total LP", systemImage: "star.circle.fill")
                        .foregroundStyle(.tint)
                    Spacer()
                    Text(totalLP.formatted())
                        .font(.headline.monospacedDigit())
                }
            }

            Section("By Corporation") {
                ForEach(sorted) { lp in
                    HStack(spacing: 12) {
                        EVECorpLogo(corpId: lp.corporationId, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(corpNames[lp.corporationId] ?? "Corp \(lp.corporationId)")
                                .font(.body)
                            Text("\(lp.loyaltyPoints.formatted()) LP")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(lp.loyaltyPoints.formatted())
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.tint)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Loyalty Points")
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if isLoading {
                ProgressView()
            } else if points.isEmpty && error == nil {
                ContentUnavailableView(
                    "No Loyalty Points",
                    systemImage: "star.slash",
                    description: Text("Complete missions to earn LP.")
                )
            }
        }
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
            points = try await characterService.loyaltyPoints()
            for lp in points {
                if let info = try? await characterService.corporationInfo(corpId: lp.corporationId) {
                    corpNames[lp.corporationId] = info.name
                }
            }
        } catch {
            self.error = error
        }
    }
}
