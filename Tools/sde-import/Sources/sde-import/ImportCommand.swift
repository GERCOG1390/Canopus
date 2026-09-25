import ArgumentParser
import CryptoKit
import GRDB
import Foundation

@main
struct ImportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sde-import",
        abstract: "Converts CCP's SDE JSONL export into an app-ready SQLite database.",
        discussion: """
            USAGE
              sde-import --input /path/to/extracted-sde/ --output /path/to/sde.sqlite

            WORKFLOW
              1. Download the latest SDE zip from CCP's official mirror:
                 https://eve-static-data-export.s3-eu-west-1.amazonaws.com/tranquility/sde.zip
              2. Unzip to a directory (e.g. ~/sde-latest/).
              3. Run this tool pointing --input at that directory.
              4. Copy the generated sde.sqlite into Canopus/Resources/ in Xcode.

            The tool looks for fsd/*.yaml files under <input>/fsd/.
            """
    )

    @Option(name: .shortAndLong, help: "Root directory of the extracted SDE JSONL archive.")
    var input: String

    @Option(name: .shortAndLong, help: "Output SQLite file path (will be overwritten).")
    var output: String = "sde.sqlite"

    @Flag(name: .long, help: "Skip integrity checks (faster, not recommended for releases).")
    var skipChecks: Bool = false

    @Option(name: .long, help: "Public HTTPS URL where the generated sde.sqlite will be hosted. Enables manifest generation.")
    var packageURL: String?

    @Option(name: .long, help: "Output manifest JSON path. Defaults to canopus-sde-manifest.json next to the SQLite output.")
    var manifest: String?

    func run() async throws {
        let inputURL = URL(fileURLWithPath: input).standardized
        let outputURL = URL(fileURLWithPath: output).standardized
        let generatedAt = ISO8601DateFormatter().string(from: Date())

        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw ValidationError("Input directory not found: \(inputURL.path)")
        }

        // Remove existing output so we start fresh
        try? FileManager.default.removeItem(at: outputURL)

        print("EVE SDE Import")
        print("  Input:  \(inputURL.path)")
        print("  Output: \(outputURL.path)")
        print("")

        // Open (or create) the database
        var config = Configuration()
        config.foreignKeysEnabled = false  // bulk import; IntegrityChecker validates after
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }
        let dbQueue = try DatabaseQueue(path: outputURL.path, configuration: config)

        // Create schema
        print("→ Creating schema…")
        try await dbQueue.write { db in
            try SchemaCreator.createSchema(in: db)
        }

        // Record build metadata
        let buildNumber = buildNumberFromDirectory(inputURL)
        try await dbQueue.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO meta VALUES ('build', ?)", arguments: [buildNumber])
            try db.execute(sql: "INSERT OR REPLACE INTO meta VALUES ('generated_at', ?)", arguments: [generatedAt])
            try db.execute(sql: "INSERT OR REPLACE INTO meta VALUES ('schema_version', '1')")
        }

        // Import data
        let importer = SDEImporter(sdeRoot: inputURL, db: dbQueue)
        try await importer.importAll()

        // Integrity checks
        if !skipChecks {
            print("")
            print("→ Running integrity checks…")
            let checker = IntegrityChecker(db: dbQueue)
            let report = try await checker.check()

            for p in report.passed { print("  ✓ \(p)") }
            for f in report.failed { print("  ✗ \(f)") }

            if !report.isOK {
                print("\nIntegrity checks failed. Database may be incomplete.")
                print("Use --skip-checks to suppress (not recommended for releases).")
                throw ExitCode.failure
            }
        }

        // Switch to DELETE journal mode before bundling — WAL cannot be opened
        // from a read-only iOS app bundle (no -wal/-shm files can be created there).
        try await dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA journal_mode = DELETE")
        }

        // File size
        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = (attrs[.size] as? Int ?? 0) / 1_048_576
        print("")
        print("✓ Done — \(outputURL.lastPathComponent) (\(size) MB)")

        if let packageURL {
            let manifestURL = URL(fileURLWithPath: manifest ?? outputURL
                .deletingLastPathComponent()
                .appendingPathComponent("canopus-sde-manifest.json")
                .path)
                .standardized
            try writeManifest(
                sqliteURL: outputURL,
                manifestURL: manifestURL,
                publicPackageURL: packageURL,
                build: buildNumber,
                generatedAt: generatedAt
            )
            print("✓ Manifest — \(manifestURL.path)")
        } else {
            print("Manifest skipped. Pass --package-url https://.../sde.sqlite to generate canopus-sde-manifest.json.")
        }

        print("")
        print("Next step: add sde.sqlite to Canopus/Resources/ in Xcode.")
    }

    private func buildNumberFromDirectory(_ url: URL) -> String {
        // CCP's official fsd/ export doesn't embed a build number anywhere in the
        // zip or its file names, unlike some older SDE distributions. Try the
        // directory-name heuristic first (in case a differently-packaged input is
        // used), then fall back to today's date — monotonically increasing, so
        // SDEUpdateManager's numeric "is remote newer" comparison still works.
        let name = url.lastPathComponent
        let parts = name.split(separator: "-")
        if let dated = parts.first(where: { $0.count == 8 && $0.allSatisfy(\.isNumber) }) {
            return String(dated)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }

    private func writeManifest(
        sqliteURL: URL,
        manifestURL: URL,
        publicPackageURL: String,
        build: String,
        generatedAt: String
    ) throws {
        guard URL(string: publicPackageURL)?.scheme?.hasPrefix("http") == true else {
            throw ValidationError("--package-url must be an absolute HTTP(S) URL.")
        }

        let values = try sqliteURL.resourceValues(forKeys: [.fileSizeKey])
        let byteSize = values.fileSize ?? 0
        let manifest = SDEPackageManifest(
            build: build,
            generatedAt: generatedAt,
            schemaVersion: "1",
            sqliteURL: publicPackageURL,
            sha256: try sha256HexDigest(for: sqliteURL),
            byteSize: byteSize
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    private func sha256HexDigest(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private struct SDEPackageManifest: Encodable {
    let build: String
    let generatedAt: String
    let schemaVersion: String
    let sqliteURL: String
    let sha256: String
    let byteSize: Int

    enum CodingKeys: String, CodingKey {
        case build
        case generatedAt = "generated_at"
        case schemaVersion = "schema_version"
        case sqliteURL = "sqlite_url"
        case sha256
        case byteSize = "byte_size"
    }
}
