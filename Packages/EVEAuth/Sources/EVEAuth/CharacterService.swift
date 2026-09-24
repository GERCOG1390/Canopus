import Foundation

/// Per-character ESI accessor with automatic token refresh and error-limit tracking.
@MainActor
public final class CharacterService {
    public private(set) var tokens: StoredTokens
    private let authClient: EVEAuthClient
    private let urlSession: URLSession
    private var errorLimitRemaining = 100

    public init(tokens: StoredTokens, authClient: EVEAuthClient, urlSession: URLSession = .shared) {
        self.tokens = tokens
        self.authClient = authClient
        self.urlSession = urlSession
    }

    // MARK: - ESI endpoints

    public func characterInfo() async throws -> ESICharacterInfo {
        try await esiGet("/characters/\(tokens.characterId)/", as: ESICharacterInfo.self)
    }

    public func skillQueue() async throws -> [ESISkillQueueItem] {
        try await esiGet("/characters/\(tokens.characterId)/skillqueue/", as: [ESISkillQueueItem].self)
    }

    public func skills() async throws -> ESISkillsResponse {
        try await esiGet("/characters/\(tokens.characterId)/skills/", as: ESISkillsResponse.self)
    }

    public func wallet() async throws -> Double {
        try await esiGet("/characters/\(tokens.characterId)/wallet/", as: Double.self)
    }

    public func corporationInfo(corpId: Int) async throws -> ESICorporationInfo {
        try await esiGetPublic("/corporations/\(corpId)/", as: ESICorporationInfo.self)
    }

    // MARK: - Clones, Implants, Loyalty, Wallet Journal

    public func implants() async throws -> [Int] {
        try await esiGet("/characters/\(tokens.characterId)/implants/", as: [Int].self)
    }

    public func clones() async throws -> ESIClonesInfo {
        try await esiGet("/characters/\(tokens.characterId)/clones/", as: ESIClonesInfo.self)
    }

    public func loyaltyPoints() async throws -> [ESILoyaltyPoint] {
        try await esiGet("/characters/\(tokens.characterId)/loyalty/points/", as: [ESILoyaltyPoint].self)
    }

    public func walletJournal() async throws -> [ESIWalletEntry] {
        try await esiGetPaginated("/characters/\(tokens.characterId)/wallet/journal/", as: ESIWalletEntry.self)
    }

    // MARK: - M3 Endpoints

    public func assets() async throws -> [ESIAsset] {
        try await esiGetPaginated("/characters/\(tokens.characterId)/assets/", as: ESIAsset.self)
    }

    public func industryJobs() async throws -> [ESIIndustryJob] {
        try await esiGet("/characters/\(tokens.characterId)/industry/jobs/", as: [ESIIndustryJob].self)
    }

    public func marketOrders() async throws -> [ESIMarketOrder] {
        try await esiGet("/characters/\(tokens.characterId)/orders/", as: [ESIMarketOrder].self)
    }

    public func contracts() async throws -> [ESIContract] {
        try await esiGetPaginated("/characters/\(tokens.characterId)/contracts/", as: ESIContract.self)
    }

    public func currentShip() async throws -> ESICurrentShip {
        try await esiGet("/characters/\(tokens.characterId)/ship/", as: ESICurrentShip.self)
    }

    public func location() async throws -> ESICharacterLocation {
        try await esiGet("/characters/\(tokens.characterId)/location/", as: ESICharacterLocation.self)
    }

    public func characterAttributes() async throws -> ESICharacterAttributes {
        try await esiGet("/characters/\(tokens.characterId)/attributes/", as: ESICharacterAttributes.self)
    }

    public func employmentHistory() async throws -> [ESIEmploymentHistoryItem] {
        try await esiGetPublic("/characters/\(tokens.characterId)/corporationhistory/", as: [ESIEmploymentHistoryItem].self)
    }

    // MARK: - Fittings

    public func fittings() async throws -> [ESIFitting] {
        try await esiGet("/characters/\(tokens.characterId)/fittings/", as: [ESIFitting].self)
    }

    // MARK: - Kill Mails (public endpoint)

    public func killMailDetail(id: Int, hash: String) async throws -> ESIKillMail {
        try await esiGetPublic("/killmails/\(id)/\(hash)/", as: ESIKillMail.self)
    }

    // MARK: - Market Transactions & Mining

    public func walletTransactions(fromId: Int? = nil) async throws -> [ESIWalletTransaction] {
        var items: [URLQueryItem] = []
        if let from = fromId { items.append(.init(name: "from_id", value: "\(from)")) }
        return try await esiGet("/characters/\(tokens.characterId)/wallet/transactions/",
                                queryItems: items, as: [ESIWalletTransaction].self)
    }

    public func miningLedger() async throws -> [ESIMiningEntry] {
        try await esiGetPaginated("/characters/\(tokens.characterId)/mining/", as: ESIMiningEntry.self)
    }

    // MARK: - EVE Mail

    public func mailHeaders(lastMailId: Int? = nil, labels: [Int]? = nil) async throws -> [ESIMailHeader] {
        var items: [URLQueryItem] = []
        if let last = lastMailId { items.append(.init(name: "last_mail_id", value: "\(last)")) }
        if let labs = labels, !labs.isEmpty {
            for l in labs { items.append(.init(name: "labels[]", value: "\(l)")) }
        }
        return try await esiGet("/characters/\(tokens.characterId)/mail/", queryItems: items, as: [ESIMailHeader].self)
    }

    public func mailBody(mailId: Int) async throws -> ESIMailBody {
        try await esiGet("/characters/\(tokens.characterId)/mail/\(mailId)/", as: ESIMailBody.self)
    }

    public func mailLabels() async throws -> ESIMailLabelsResponse {
        try await esiGet("/characters/\(tokens.characterId)/mail/labels/", as: ESIMailLabelsResponse.self)
    }

    public func markMailRead(mailId: Int, preserving labels: [Int]? = nil) async throws {
        let currentLabels: [Int]
        if let labels {
            currentLabels = labels
        } else {
            currentLabels = try await mailBody(mailId: mailId).labels ?? []
        }
        struct Update: Encodable { let read: Bool; let labels: [Int] }
        let data = try JSONEncoder().encode(Update(read: true, labels: currentLabels))
        _ = try await esiPut("/characters/\(tokens.characterId)/mail/\(mailId)/", body: data)
    }

    // MARK: - Universe name resolution

    public func resolveNames(ids: [Int]) async throws -> [ESINameResult] {
        guard !ids.isEmpty else { return [] }
        let chunks = stride(from: 0, to: ids.count, by: 1000).map { Array(ids[$0..<min($0+1000, ids.count)]) }
        var results: [ESINameResult] = []
        for chunk in chunks {
            let data = try JSONEncoder().encode(chunk)
            let batch = try await esiPostPublic("/universe/names/", body: data, as: [ESINameResult].self)
            results += batch
        }
        return results
    }

    // MARK: - Universe location resolution

    public func stationInfo(id: Int) async throws -> ESIStationInfo {
        try await esiGetPublic("/universe/stations/\(id)/", as: ESIStationInfo.self)
    }

    public func systemInfo(id: Int) async throws -> ESISystemInfo {
        try await esiGetPublic("/universe/systems/\(id)/", as: ESISystemInfo.self)
    }

    public func structureInfo(id: Int) async throws -> ESIStructureInfo {
        try await esiGet("/universe/structures/\(id)/", as: ESIStructureInfo.self)
    }

    // MARK: - Authenticated GET (with optional query items)

    private func esiGet<T: Decodable & Sendable>(_ path: String, queryItems: [URLQueryItem], as type: T.Type) async throws -> T {
        if !tokens.isAccessTokenValid { tokens = try await authClient.refresh(tokens) }
        guard errorLimitRemaining > 10 else { throw AuthError.httpError(420, "error limit reached") }
        var req = makeRequestWithQuery(path: path, queryItems: queryItems)
        req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await urlSession.data(for: req)
        if let http = response as? HTTPURLResponse {
            if let remain = http.value(forHTTPHeaderField: "X-ESI-Error-Limit-Remain").flatMap(Int.init) {
                errorLimitRemaining = remain
            }
            if http.statusCode == 401 {
                tokens = try await authClient.refresh(tokens)
                req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
                let (data2, resp2) = try await urlSession.data(for: req)
                if let http2 = resp2 as? HTTPURLResponse, !(200..<300).contains(http2.statusCode) {
                    throw AuthError.httpError(http2.statusCode, String(data: data2, encoding: .utf8))
                }
                return try JSONDecoder.esi.decode(T.self, from: data2)
            }
            guard (200..<300).contains(http.statusCode) else {
                throw AuthError.httpError(http.statusCode, String(data: data, encoding: .utf8))
            }
        }
        return try JSONDecoder.esi.decode(T.self, from: data)
    }

    // MARK: - Authenticated PUT

    private func esiPut(_ path: String, body: Data) async throws -> Data {
        if !tokens.isAccessTokenValid { tokens = try await authClient.refresh(tokens) }
        guard errorLimitRemaining > 10 else { throw AuthError.httpError(420, "error limit reached") }
        var req = makeRequest(path: path)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = body
        let (data, response) = try await urlSession.data(for: req)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                tokens = try await authClient.refresh(tokens)
                req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
                let (data2, resp2) = try await urlSession.data(for: req)
                if let http2 = resp2 as? HTTPURLResponse, !(200..<300).contains(http2.statusCode) {
                    throw AuthError.httpError(http2.statusCode, String(data: data2, encoding: .utf8))
                }
                return data2
            }
            guard (200..<300).contains(http.statusCode) else {
                throw AuthError.httpError(http.statusCode, String(data: data, encoding: .utf8))
            }
        }
        return data
    }

    // MARK: - Public POST

    private func esiPostPublic<T: Decodable & Sendable>(_ path: String, body: Data, as type: T.Type) async throws -> T {
        var req = makeRequest(path: path)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, response) = try await urlSession.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AuthError.httpError(http.statusCode, String(data: data, encoding: .utf8))
        }
        return try JSONDecoder.esi.decode(T.self, from: data)
    }

    private func makeRequestWithQuery(path: String, queryItems: [URLQueryItem]) -> URLRequest {
        let base = EVEConstants.esiBase.appending(path: path)
        if queryItems.isEmpty { return makeRequest(path: path) }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()
        comps.queryItems = queryItems
        var req = URLRequest(url: comps.url ?? base)
        req.setValue(EVEConstants.userAgent, forHTTPHeaderField: "User-Agent")
        return req
    }

    // MARK: - Authenticated GET

    private func esiGet<T: Decodable & Sendable>(_ path: String, as type: T.Type) async throws -> T {
        if !tokens.isAccessTokenValid {
            tokens = try await authClient.refresh(tokens)
        }

        guard errorLimitRemaining > 10 else { throw AuthError.httpError(420, "error limit reached") }

        var req = makeRequest(path: path)
        req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: req)

        if let http = response as? HTTPURLResponse {
            if let remain = http.value(forHTTPHeaderField: "X-ESI-Error-Limit-Remain").flatMap(Int.init) {
                errorLimitRemaining = remain
            }
            if http.statusCode == 401 {
                // One retry after forced refresh.
                tokens = try await authClient.refresh(tokens)
                req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
                let (data2, resp2) = try await urlSession.data(for: req)
                if let http2 = resp2 as? HTTPURLResponse, !(200..<300).contains(http2.statusCode) {
                    throw AuthError.httpError(http2.statusCode, String(data: data2, encoding: .utf8))
                }
                return try JSONDecoder.esi.decode(T.self, from: data2)
            }
            guard (200..<300).contains(http.statusCode) else {
                throw AuthError.httpError(http.statusCode, String(data: data, encoding: .utf8))
            }
        }

        return try JSONDecoder.esi.decode(T.self, from: data)
    }

    // MARK: - Public GET (no auth)

    private func esiGetPublic<T: Decodable & Sendable>(_ path: String, as type: T.Type) async throws -> T {
        let (data, response) = try await urlSession.data(for: makeRequest(path: path))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AuthError.httpError(http.statusCode, String(data: data, encoding: .utf8))
        }
        return try JSONDecoder.esi.decode(T.self, from: data)
    }

    private func makeRequest(path: String) -> URLRequest {
        var req = URLRequest(url: EVEConstants.esiBase.appending(path: path))
        req.setValue(EVEConstants.userAgent, forHTTPHeaderField: "User-Agent")
        return req
    }

    // MARK: - Paginated fetch (sequential pages, reads X-Pages header)

    private func esiGetPaginated<T: Decodable & Sendable>(_ path: String, as type: T.Type) async throws -> [T] {
        var result: [T] = []
        var page = 1
        var totalPages = 1
        repeat {
            let (data, response) = try await esiRawRequest(path: path, page: page)
            result += try JSONDecoder.esi.decode([T].self, from: data)
            if page == 1 {
                totalPages = response.value(forHTTPHeaderField: "X-Pages").flatMap(Int.init) ?? 1
            }
            page += 1
        } while page <= totalPages
        return result
    }

    private func esiRawRequest(path: String, page: Int = 1) async throws -> (Data, HTTPURLResponse) {
        if !tokens.isAccessTokenValid {
            tokens = try await authClient.refresh(tokens)
        }
        guard errorLimitRemaining > 10 else { throw AuthError.httpError(420, "error limit reached") }

        var req = pagedURLRequest(path: path, page: page)
        req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        if let remain = http.value(forHTTPHeaderField: "X-ESI-Error-Limit-Remain").flatMap(Int.init) {
            errorLimitRemaining = remain
        }

        if http.statusCode == 401 {
            tokens = try await authClient.refresh(tokens)
            req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
            let (data2, resp2) = try await urlSession.data(for: req)
            if let http2 = resp2 as? HTTPURLResponse {
                guard (200..<300).contains(http2.statusCode) else {
                    throw AuthError.httpError(http2.statusCode, String(data: data2, encoding: .utf8))
                }
                return (data2, http2)
            }
            throw URLError(.badServerResponse)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw AuthError.httpError(http.statusCode, String(data: data, encoding: .utf8))
        }
        return (data, http)
    }

    private func pagedURLRequest(path: String, page: Int) -> URLRequest {
        let base = EVEConstants.esiBase.appending(path: path)
        var req: URLRequest
        if page > 1, var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) {
            comps.queryItems = (comps.queryItems ?? []) + [.init(name: "page", value: "\(page)")]
            req = URLRequest(url: comps.url ?? base)
        } else {
            req = URLRequest(url: base)
        }
        req.setValue(EVEConstants.userAgent, forHTTPHeaderField: "User-Agent")
        return req
    }
}
