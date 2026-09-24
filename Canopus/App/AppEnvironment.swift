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

    var showSDEUpdateSheet: Bool = false

    let characterStore: CharacterStore
    let sdeUpdates: SDEUpdateManager

    init() {
        let authClient = EVEAuthClient()
        characterStore = CharacterStore(authClient: authClient)
        sdeUpdates = SDEUpdateManager()
    }

    func loadIfNeeded() {
        guard case .idle = loadState else { return }
        loadState = .loading
        Task {
            do {
                let repo = try await SDERepository.openBundled()
                repository = repo
                loadState = .ready

                // Check for SDE updates in background automatically
                Task {
                    await sdeUpdates.performStartupCheckAndAutoUpdate { [weak self] in
                        await self?.reloadRepository()
                    }
                }
            } catch {
                loadState = .failed(error)
            }
        }
    }

    func reloadRepository() async {
        loadState = .loading
        do {
            await SDERepository.clearSharedCache()
            let repo = try await SDERepository.openBundled()
            repository = repo
            sdeUpdates.refreshLocalMetadata()
            loadState = .ready
        } catch {
            loadState = .failed(error)
        }
    }
}
