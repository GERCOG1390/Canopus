import GRDB
import Foundation

/// Resolves and opens the bundled SDE SQLite database.
///
/// Lookup order:
/// 1. Application Support / sde.sqlite copied from the current app bundle
/// 2. Bundle / sde.sqlite as a fallback when Application Support is unavailable
///
/// ZSTD decompression (.sqlite.zst) is intentionally omitted for M0.
/// It will be added before App Store release when the bundle size matters.
public enum SDEDatabase {
    public enum Error: Swift.Error, LocalizedError {
        case notFound
        case applicationSupportUnavailable
        case invalidDatabase(String)
        case unsupportedSchema(String)

        public var errorDescription: String? {
            switch self {
            case .notFound:
                "SDE database not found. Run sde-import, then add sde.sqlite to the Canopus target in Xcode."
            case .applicationSupportUnavailable:
                "Application Support directory is unavailable for the SDE database."
            case .invalidDatabase(let reason):
                "SDE database is invalid: \(reason)"
            case .unsupportedSchema(let version):
                "Unsupported SDE database schema version: \(version)"
            }
        }
    }

    public enum Source: String, Sendable {
        case bundled
        case installed
    }

    public struct Metadata: Sendable, Equatable {
        public let build: String?
        public let generatedAt: String?
        public let schemaVersion: String?
        public let source: Source
        public let fileSize: UInt64
        public let url: URL
    }

    /// Opens a read-only DatabasePool pointing at the SDE SQLite file.
    /// The database is never written to after install, so a pool of
    /// concurrent readers avoids serializing reads behind a single connection.
    /// Call from a background context — opening the file is synchronous I/O.
    public static func openBundled() throws -> DatabasePool {
        let url = try resolvedURL()
        var config = Configuration()
        config.readonly = true
        return try DatabasePool(path: url.path, configuration: config)
    }

    public static func currentMetadata() throws -> Metadata {
        let url = try resolvedURL()
        return try metadata(at: url, source: source(for: url))
    }

    public static func bundledMetadata() throws -> Metadata? {
        guard let url = Bundle.main.url(forResource: "sde", withExtension: "sqlite") else { return nil }
        return try metadata(at: url, source: .bundled)
    }

    public static func installedMetadata() throws -> Metadata? {
        let url = try installedURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try metadata(at: url, source: .installed)
    }

    public static func installedURL() throws -> URL {
        guard let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { throw Error.applicationSupportUnavailable }
        return directory.appendingPathComponent("sde.sqlite")
    }

    @discardableResult
    public static func installDatabase(from sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let targetURL = try installedURL()
        let directory = targetURL.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent("sde.sqlite.installing")
        let backupURL = directory.appendingPathComponent("sde.sqlite.backup")

        if fileManager.fileExists(atPath: temporaryURL.path) {
            try fileManager.removeItem(at: temporaryURL)
        }
        try fileManager.copyItem(at: sourceURL, to: temporaryURL)
        try validateDatabase(at: temporaryURL)

        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }

        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.moveItem(at: targetURL, to: backupURL)
        }

        do {
            try fileManager.moveItem(at: temporaryURL, to: targetURL)
            if fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.removeItem(at: backupURL)
            }
            return targetURL
        } catch {
            if fileManager.fileExists(atPath: backupURL.path),
               !fileManager.fileExists(atPath: targetURL.path) {
                try? fileManager.moveItem(at: backupURL, to: targetURL)
            }
            throw error
        }
    }

    // MARK: - Private

    private static func resolvedURL() throws -> URL {
        if let installed = try? installedURL(),
           FileManager.default.fileExists(atPath: installed.path),
           (try? validateDatabase(at: installed)) != nil {
            return installed
        }

        if let bundled = Bundle.main.url(forResource: "sde", withExtension: "sqlite") {
            return try installedWritableCopy(from: bundled)
        }

        throw Error.notFound
    }

    private static func installedWritableCopy(from bundledURL: URL) throws -> URL {
        guard let targetURL = try? installedURL() else {
            return bundledURL
        }

        let fileManager = FileManager.default
        let bundledSignature = try fileSignature(at: bundledURL)
        let targetSignature = try? fileSignature(at: targetURL)

        if let targetSignature,
           (try? validateDatabase(at: targetURL)) != nil,
           targetSignature.size == bundledSignature.size,
           targetSignature.modificationDate >= bundledSignature.modificationDate {
            return targetURL
        }

        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }

        try fileManager.copyItem(at: bundledURL, to: targetURL)
        try? fileManager.setAttributes(
            [.modificationDate: bundledSignature.modificationDate],
            ofItemAtPath: targetURL.path
        )
        return targetURL
    }

    private static func source(for url: URL) -> Source {
        guard let installed = try? installedURL() else { return .bundled }
        return installed.standardizedFileURL.path == url.standardizedFileURL.path ? .installed : .bundled
    }

    private static func metadata(at url: URL, source: Source) throws -> Metadata {
        try validateDatabase(at: url)

        var config = Configuration()
        config.readonly = true
        let queue = try DatabaseQueue(path: url.path, configuration: config)
        let values = try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT key, value FROM meta").reduce(into: [String: String]()) { result, row in
                result[row["key"]] = row["value"]
            }
        }
        let signature = try fileSignature(at: url)

        return Metadata(
            build: values["build"],
            generatedAt: values["generated_at"],
            schemaVersion: values["schema_version"],
            source: source,
            fileSize: signature.size,
            url: url
        )
    }

    private static func validateDatabase(at url: URL) throws {
        var config = Configuration()
        config.readonly = true
        let queue = try DatabaseQueue(path: url.path, configuration: config)

        try queue.read { db in
            for table in ["meta", "categories", "groups", "types", "market_groups"] {
                let count = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
                    arguments: [table]
                ) ?? 0
                guard count == 1 else { throw Error.invalidDatabase("missing table \(table)") }
            }

            let schemaVersion = try String.fetchOne(
                db,
                sql: "SELECT value FROM meta WHERE key = 'schema_version'"
            )
            guard schemaVersion == "1" else {
                throw Error.unsupportedSchema(schemaVersion ?? "unknown")
            }
        }
    }

    private static func fileSignature(at url: URL) throws -> (size: UInt64, modificationDate: Date) {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return (
            size: UInt64(values.fileSize ?? 0),
            modificationDate: values.contentModificationDate ?? .distantPast
        )
    }
}
