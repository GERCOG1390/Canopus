import GRDB
import Foundation

/// Resolves and opens the bundled SDE SQLite database.
///
/// Lookup order:
/// 1. Application Support / sde.sqlite  (cached from a previous session)
/// 2. Bundle / sde.sqlite               (development: uncompressed file added to Xcode target)
///
/// ZSTD decompression (.sqlite.zst) is intentionally omitted for M0.
/// It will be added before App Store release when the bundle size matters.
public enum SDEDatabase {
    public enum Error: Swift.Error, LocalizedError {
        case notFound

        public var errorDescription: String? {
            "SDE database not found. Run sde-import, then add sde.sqlite to the Canopus target in Xcode."
        }
    }

    /// Opens a read-only DatabaseQueue pointing at the SDE SQLite file.
    /// Call from a background context — opening the file is synchronous I/O.
    public static func openBundled() throws -> DatabaseQueue {
        let url = try resolvedURL()
        var config = Configuration()
        config.readonly = true
        return try DatabaseQueue(path: url.path, configuration: config)
    }

    // MARK: - Private

    private static func resolvedURL() throws -> URL {
        // 1. Previously opened and cached in Application Support
        if let cached = cachedURL(), FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        // 2. Uncompressed file bundled in the app (dev / M0 workflow)
        if let bundled = Bundle.main.url(forResource: "sde", withExtension: "sqlite") {
            return bundled
        }

        throw Error.notFound
    }

    private static func cachedURL() -> URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).appending(component: "sde.sqlite")
    }
}
