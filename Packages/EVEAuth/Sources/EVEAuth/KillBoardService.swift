import Foundation

public struct ZKBEntry: Decodable, Sendable, Identifiable {
    public var id: Int { killmailId }
    public let killmailId: Int
    public let killmailHash: String
    public let zkb: ZKBData
}

public struct ZKBData: Decodable, Sendable {
    public let totalValue: Double?
    public let points: Int?
    public let npc: Bool?
    public let solo: Bool?
    public let locationId: Int?
}

@MainActor
public final class KillBoardService {
    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func kills(characterId: Int, page: Int = 1) async throws -> [ZKBEntry] {
        try await fetch("https://zkillboard.com/api/kills/characterID/\(characterId)/page/\(page)/")
    }

    public func losses(characterId: Int, page: Int = 1) async throws -> [ZKBEntry] {
        try await fetch("https://zkillboard.com/api/losses/characterID/\(characterId)/page/\(page)/")
    }

    private func fetch(_ urlString: String) async throws -> [ZKBEntry] {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue(EVEConstants.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await urlSession.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder.esi.decode([ZKBEntry].self, from: data)
    }
}
