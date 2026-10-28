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
    private(set) var repository: SDERepository? {
        didSet { repositoryVersion += 1 }
    }
    /// Changes whenever the SDE database opens or is replaced (after an update).
    private(set) var repositoryVersion = 0

    /// Task id for screens that read the active character and the SDE: they reload when either changes,
    /// including when the database finishes opening after the screen appeared.
    var dataKey: String { "\(characterStore.selectedId ?? 0)-\(repositoryVersion)" }

    /// The desktop's dogma engine (JavaScriptCore) over the current SDE; recreated when the SDE changes.
    private var dogmaJS: (version: Int, engine: DogmaJS)?

    var dogma: DogmaJS? {
        if let d = dogmaJS, d.version == repositoryVersion { return d.engine }
        guard let repository, let engine = try? DogmaJS(repository: repository) else { return nil }
        dogmaJS = (repositoryVersion, engine)
        return engine
    }

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
