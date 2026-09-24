import CryptoKit
import EVEStaticData
import Foundation

struct SDEUpdateManifest: Decodable, Equatable, Sendable {
    let build: String
    let generatedAt: String?
    let schemaVersion: String
    let sqliteURL: URL
    let sha256: String?
    let byteSize: Int64?
}

@Observable
@MainActor
final class SDEUpdateManager {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable
        case downloading
        case installing
        case installed
        case failed(String)
    }

    private let manifestURLKey = "Canopus.SDEManifestURL"

    var manifestURLString: String {
        didSet {
            UserDefaults.standard.set(manifestURLString, forKey: manifestURLKey)
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var localMetadata: SDEDatabase.Metadata?
    private(set) var remoteManifest: SDEUpdateManifest?

    init() {
        manifestURLString = UserDefaults.standard.string(forKey: manifestURLKey) ?? ""
        refreshLocalMetadata()
    }

    func refreshLocalMetadata() {
        localMetadata = try? SDEDatabase.currentMetadata()
    }

    func checkForUpdates() async {
        guard let manifestURL = normalizedManifestURL else {
            phase = .failed("Manifest URL is not configured.")
            return
        }

        phase = .checking

        do {
            let (data, _) = try await URLSession.shared.data(from: manifestURL)
            let manifest = try JSONDecoder().decode(SDEUpdateManifest.self, from: data)
            remoteManifest = manifest
            phase = isRemoteNewer(manifest) ? .updateAvailable : .upToDate
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func installUpdate() async -> Bool {
        if remoteManifest == nil {
            await checkForUpdates()
        }

        guard let manifest = remoteManifest else { return false }

        phase = .downloading

        do {
            let (downloadURL, _) = try await URLSession.shared.download(from: manifest.sqliteURL)
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

    private var normalizedManifestURL: URL? {
        let trimmed = manifestURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
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
    case fileSizeMismatch(expected: Int64, actual: Int64)
    case sha256Mismatch

    var errorDescription: String? {
        switch self {
        case .fileSizeMismatch(let expected, let actual):
            "Downloaded SDE size mismatch. Expected \(expected) bytes, got \(actual) bytes."
        case .sha256Mismatch:
            "Downloaded SDE checksum does not match the manifest."
        }
    }
}
