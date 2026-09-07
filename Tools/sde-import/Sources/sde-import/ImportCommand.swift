import ArgumentParser
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
              1. Download the latest SDE JSONL zip from:
                 https://developers.eveonline.com/static-data/tranquility/eve-online-static-data-latest-jsonl.zip
              2. Unzip to a directory (e.g. ~/sde-latest/).
              3. Run this tool pointing --input at that directory.
              4. Copy the generated sde.sqlite into Canopus/Resources/ in Xcode.

            The tool looks for JSONL files in <input>/ and <input>/fsd/.
            """
    )

    @Option(name: .shortAndLong, help: "Root directory of the extracted SDE JSONL archive.")
    var input: String

    @Option(name: .shortAndLong, help: "Output SQLite file path (will be overwritten).")
    var output: String = "sde.sqlite"

    @Flag(name: .long, help: "Skip integrity checks (faster, not recommended for releases).")
    var skipChecks: Bool = false

    func run() async throws {
        let inputURL = URL(fileURLWithPath: input).standardized
        let outputURL = URL(fileURLWithPath: output).standardized

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
            try db.execute(sql: "INSERT OR REPLACE INTO meta VALUES ('generated_at', ?)", arguments: [ISO8601DateFormatter().string(from: Date())])
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
        try await dbQueue.write { db in
            try db.execute(sql: "PRAGMA journal_mode = DELETE")
        }

        // File size
        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = (attrs[.size] as? Int ?? 0) / 1_048_576
        print("")
        print("✓ Done — \(outputURL.lastPathComponent) (\(size) MB)")
        print("")
        print("Next step: add sde.sqlite to Canopus/Resources/ in Xcode.")
    }

    private func buildNumberFromDirectory(_ url: URL) -> String {
        // Try to extract a build number from the directory name, e.g.
        // eve-online-static-data-20240101-001.0 → 20240101
        let name = url.lastPathComponent
        let parts = name.split(separator: "-")
        return parts.first(where: { $0.count == 8 && $0.allSatisfy(\.isNumber) })
            .map(String.init) ?? "unknown"
    }
}
