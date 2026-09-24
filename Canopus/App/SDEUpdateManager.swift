import CryptoKit
import EVEStaticData
import Foundation
import Observation

public struct SDEUpdateManifest: Decodable, Equatable, Sendable {
    public let build: String
    public let generatedAt: String?
    public let schemaVersion: String
    public let sqliteURL: URL
    public let sha256: String?
    public let byteSize: Int64?
    public let iconVersion: String?

    enum CodingKeys: String, CodingKey {
        case build
        case generatedAt = "generated_at"
        case schemaVersion = "schema_version"
        case sqliteURL = "sqlite_url"
        case sha256
        case byteSize = "byte_size"
        case iconVersion = "icon_version"
    }
}

@Observable
@MainActor
public final class SDEUpdateManager {
    public enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable
        case downloading(progress: Double)
        case installing
        case installed
        case failed(String)
    }

    // Must match where .github/workflows/sde-update.yml actually publishes the
    // manifest: a GitHub Release asset (tag "sde-latest"), not a committed file
    // on `main` — raw.githubusercontent.com/.../main/... would 404 forever.
    public static let defaultManifestURLString = "https://github.com/GERCOG1390/Canopus/releases/download/sde-latest/canopus-sde-manifest.json"
    private let manifestURLKey = "Canopus.SDEManifestURL"
    private let autoUpdateKey = "Canopus.SDEAutoUpdateEnabled"

    public var manifestURLString: String {
        didSet {
            UserDefaults.standard.set(manifestURLString, forKey: manifestURLKey)
        }
    }

    public var autoUpdateEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoUpdateEnabled, forKey: autoUpdateKey)
        }
    }

    public private(set) var phase: Phase = .idle
    public private(set) var localMetadata: SDEDatabase.Metadata?
    public private(set) var remoteManifest: SDEUpdateManifest?

    public init() {
        let savedURL = UserDefaults.standard.string(forKey: manifestURLKey)
        if let savedURL, !savedURL.isEmpty {
            self.manifestURLString = savedURL
        } else {
            self.manifestURLString = Self.defaultManifestURLString
        }

        if UserDefaults.standard.object(forKey: autoUpdateKey) != nil {
            self.autoUpdateEnabled = UserDefaults.standard.bool(forKey: autoUpdateKey)
        } else {
            self.autoUpdateEnabled = true
        }

        refreshLocalMetadata()
    }

    public func resetToDefaultManifestURL() {
        manifestURLString = Self.defaultManifestURLString
    }

    public func refreshLocalMetadata() {
        localMetadata = try? SDEDatabase.currentMetadata()
    }

    public func checkForUpdates() async {
        guard let manifestURL = normalizedManifestURL else {
            phase = .failed("Manifest URL is not configured.")
            return
        }

        phase = .checking

        do {
            let (data, response) = try await URLSession.shared.data(from: manifestURL)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                throw SDEUpdateError.httpError(statusCode: httpResponse.statusCode)
            }

            do {
                let manifest = try JSONDecoder().decode(SDEUpdateManifest.self, from: data)
                remoteManifest = manifest
                phase = isRemoteNewer(manifest) ? .updateAvailable : .upToDate
            } catch {
                if manifestURLString.contains("developers.eveonline.com") {
                    throw SDEUpdateError.developersSiteEntered
                }
                throw SDEUpdateError.invalidManifestJSON
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    public func performStartupCheckAndAutoUpdate(reloadHandler: @escaping () async -> Void) async {
        await checkForUpdates()

        if isUpdateAvailable && autoUpdateEnabled {
            let success = await installUpdate()
            if success {
                await reloadHandler()
            }
        }
    }

    public func installUpdate() async -> Bool {
        if remoteManifest == nil {
            await checkForUpdates()
        }

        guard let manifest = remoteManifest else { return false }

        phase = .downloading(progress: 0.1)

        do {
            let (downloadURL, response) = try await URLSession.shared.download(from: manifest.sqliteURL)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                throw SDEUpdateError.httpError(statusCode: httpResponse.statusCode)
            }
            phase = .downloading(progress: 0.9)
            try verifyDownloadedFile(at: downloadURL, manifest: manifest)

            phase = .installing
            try SDEDatabase.installDatabase(from: downloadURL)
            await SDERepository.clearSharedCache()
            refreshLocalMetadata()
            phase = .installed
            return true
        } catch {
            phase = .failed(error.localizedDescription)
            return false
        }
    }

    public var normalizedManifestURL: URL? {
        let trimmed = manifestURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    public var isUpdateAvailable: Bool {
        guard let manifest = remoteManifest else { return false }
        return isRemoteNewer(manifest)
    }

    private func isRemoteNewer(_ manifest: SDEUpdateManifest) -> Bool {
        guard let localBuild = localMetadata?.build else { return true }
        return buildNumber(manifest.build) > buildNumber(localBuild)
    }

    private func buildNumber(_ value: String) -> Int {
        Int(value.filter(\.isNumber)) ?? 0
    }

    private func verifyDownloadedFile(at url: URL, manifest: SDEUpdateManifest) throws {
        if let expectedSize = manifest.byteSize {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            let actualSize = Int64(values.fileSize ?? 0)
            guard actualSize == expectedSize else {
                throw SDEUpdateError.fileSizeMismatch(expected: expectedSize, actual: actualSize)
            }
        }

        if let expectedHash = manifest.sha256?.lowercased(), !expectedHash.isEmpty {
            let actualHash = try sha256HexDigest(for: url)
            guard actualHash == expectedHash else {
                throw SDEUpdateError.sha256Mismatch
            }
        }
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

private enum SDEUpdateError: LocalizedError {
    case httpError(statusCode: Int)
    case fileSizeMismatch(expected: Int64, actual: Int64)
    case sha256Mismatch
    case developersSiteEntered
    case invalidManifestJSON

    var errorDescription: String? {
        switch self {
        case .httpError(let statusCode):
            "Failed to fetch manifest (HTTP status \(statusCode))."
        case .fileSizeMismatch(let expected, let actual):
            "Downloaded SDE size mismatch. Expected \(expected) bytes, got \(actual) bytes."
        case .sha256Mismatch:
            "Downloaded SDE checksum does not match the manifest."
        case .developersSiteEntered:
            "https://developers.eveonline.com is a web page, not a manifest JSON file. Tap Reset to restore default manifest."
        case .invalidManifestJSON:
            "Manifest file format is invalid. Tap Reset to restore default manifest URL."
        }
    }
}
