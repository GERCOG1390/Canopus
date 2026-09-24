import SwiftUI
import EVEStaticData
import EVEAuth

@Observable
@MainActor
final class AppEnvironment {
    enum LoadState {
        case idle, loading, ready, failed(Error)
    }

    private(set) var loadState: LoadState = .idle
    private(set) var repository: SDERepository?

    let characterStore: CharacterStore

    init() {
        let authClient = EVEAuthClient()
        characterStore = CharacterStore(authClient: authClient)
    }

    func loadIfNeeded() {
        guard case .idle = loadState else { return }
        loadState = .loading
        Task {
            do {
                let repo = try await SDERepository.openBundled()
                repository = repo
                loadState = .ready
            } catch {
                loadState = .failed(error)
            }
        }
    }
}
