// Game UI icons (importer 4), as the desktop's icons.ts finds them: the SDE names a client resource
// (res:/ui/texture/icons/…), the client's resfileindex maps it to a file on CCP's resource CDN. The
// app then loads https://resources.eveonline.com/<path> directly, with no third-party icon service.

import Foundation
import GRDB

extension SDEImporter {
    func importIcons() async throws -> String {
        guard let url = findFile("icons.yaml") else { return "icons.yaml not found, skipped" }
        let icons = try parseYAMLNodeMap(url).compactMap { row in row.mapping["iconFile"]?.string.map { (row.id, $0.lowercased()) } }
        let index: [String: String]
        do {
            index = try await Self.resourceIndex()
        } catch {
            return "resource index unavailable (\(error)), skipped"
        }
        let found = try await db.write { db in
            var found = 0
            for (id, res) in icons {
                guard let path = index[res] else { continue }
                try db.execute(sql: "INSERT OR REPLACE INTO icons (id, path) VALUES (?, ?)", arguments: [id, path])
                found += 1
            }
            return found
        }
        return "\(found) of \(icons.count) icons"
    }

    /// res:/ui/texture/… (lower-cased) → CDN path, for the live client build.
    private static func resourceIndex() async throws -> [String: String] {
        let binaries = "https://binaries.eveonline.com"
        struct Client: Decodable { let build: String }
        let client = try JSONDecoder().decode(Client.self, from: try await get("\(binaries)/eveclient_TQ.json"))
        let app = String(decoding: try await get("\(binaries)/eveonline_\(client.build).txt"), as: UTF8.self)
        guard let entry = app.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("app:/resfileindex.txt,") }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let text = String(decoding: try await get("\(binaries)/\(entry.split(separator: ",")[1])"), as: UTF8.self)
        var map: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("res:/ui/texture/") {
            let parts = line.split(separator: ",")
            if parts.count > 1 { map[parts[0].lowercased()] = String(parts[1]) }
        }
        return map
    }

    private static func get(_ url: String) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: URL(string: url)!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        guard data.starts(with: [0x1F, 0x8B]) else { return data }
        // CCP's files are gzip; the header that would make URLSession unpack them is not always honoured.
        let gz = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString + ".gz")
        try data.write(to: gz)
        defer { try? FileManager.default.removeItem(at: gz) }
        let gunzip = Process()
        gunzip.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        gunzip.arguments = ["-c", gz.path]
        let out = Pipe()
        gunzip.standardOutput = out
        try gunzip.run()
        let unpacked = out.fileHandleForReading.readDataToEndOfFile()
        gunzip.waitUntilExit()
        return unpacked
    }
}
