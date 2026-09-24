import Foundation

/// Per-character ESI accessor with automatic token refresh and error-limit tracking.
@MainActor
public final class CharacterService {
    public private(set) var tokens: StoredTokens
    private let authClient: EVEAuthClient
    private let urlSession: URLSession
    private var errorLimitRemaining = 100
    private var errorLimitResetAt: Date?

    // Short-lived cache for endpoints that get re-requested every time a tab
    // is revisited (assets, wallet, skills, queue, location, fittings). ESI
    // data doesn't change fast enough to justify a fresh round-trip on every
    // tab switch, so results are reused within their TTL window.
    private var cacheStore: [String: (value: Any, timestamp: Date)] = [:]
    private var responseCache: [URL: CachedResponse] = [:]

    private struct CachedResponse {
        let data: Data
        let etag: String?
        let expiresAt: Date?
        let response: HTTPURLResponse

        var isFresh: Bool {
            guard let expiresAt else { return false }
            return expiresAt > Date()
        }
    }

    private func cached<T>(_ key: String, ttl: TimeInterval, fetch: () async throws -> T) async throws -> T {
        if let entry = cacheStore[key],
           Date().timeIntervalSince(entry.timestamp) < ttl,
           let value = entry.value as? T {
            return value
        }
        let value = try await fetch()
        cacheStore[key] = (value, Date())
        return value
    }

    public init(tokens: StoredTokens, authClient: EVEAuthClient, urlSession: URLSession = .shared) {
        self.tokens = tokens
        self.authClient = authClient
        self.urlSession = urlSession
    }

    // MARK: - ESI endpoints

    public func characterInfo() async throws -> ESICharacterInfo {
        try await cached("characterInfo", ttl: 300) {
            try await esiGet("/characters/\(tokens.characterId)/", as: ESICharacterInfo.self)
        }
    }

    public func skillQueue() async throws -> [ESISkillQueueItem] {
        try await cached("skillQueue", ttl: 30) {
            try await esiGet("/characters/\(tokens.characterId)/skillqueue/", as: [ESISkillQueueItem].self)
        }
    }

    public func skills() async throws -> ESISkillsResponse {
        try await cached("skills", ttl: 60) {
            try await esiGet("/characters/\(tokens.characterId)/skills/", as: ESISkillsResponse.self)
        }
    }

    public func wallet() async throws -> Double {
        try await cached("wallet", ttl: 30) {
            try await esiGet("/characters/\(tokens.characterId)/wallet/", as: Double.self)
        }
    }

    public func corporationInfo(corpId: Int) async throws -> ESICorporationInfo {
        try await cached("corporationInfo:\(corpId)", ttl: 3_600) {
            try await esiGetPublic("/corporations/\(corpId)/", as: ESICorporationInfo.self)
        }
    }

    // MARK: - Clones, Implants, Loyalty, Wallet Journal

    public func implants() async throws -> [Int] {
        try await cached("implants", ttl: 300) {
            try await esiGet("/characters/\(tokens.characterId)/implants/", as: [Int].self)
        }
    }

    public func clones() async throws -> ESIClonesInfo {
        try await cached("clones", ttl: 300) {
            try await esiGet("/characters/\(tokens.characterId)/clones/", as: ESIClonesInfo.self)
        }
    }

    public func loyaltyPoints() async throws -> [ESILoyaltyPoint] {
        try await cached("loyaltyPoints", ttl: 300) {
            try await esiGet("/characters/\(tokens.characterId)/loyalty/points/", as: [ESILoyaltyPoint].self)
        }
    }

    public func loyaltyStoreOffers(corpId: Int) async throws -> [ESILoyaltyStoreOffer] {
        try await cached("loyaltyStoreOffers:\(corpId)", ttl: 3_600) {
            try await esiGetPublic("/loyalty/stores/\(corpId)/offers/", as: [ESILoyaltyStoreOffer].self)
        }
    }

    public func walletJournal() async throws -> [ESIWalletEntry] {
        try await cached("walletJournal", ttl: 60) {
            try await esiGetPaginated("/characters/\(tokens.characterId)/wallet/journal/", as: ESIWalletEntry.self)
        }
    }

    // MARK: - M3 Endpoints

    public func assets() async throws -> [ESIAsset] {
        try await cached("assets", ttl: 60) {
            try await esiGetPaginated("/characters/\(tokens.characterId)/assets/", as: ESIAsset.self)
        }
    }

    public func industryJobs() async throws -> [ESIIndustryJob] {
        try await cached("industryJobs", ttl: 120) {
            try await esiGet("/characters/\(tokens.characterId)/industry/jobs/", as: [ESIIndustryJob].self)
        }
    }

    public func marketOrders() async throws -> [ESIMarketOrder] {
        try await cached("marketOrders", ttl: 120) {
            try await esiGet("/characters/\(tokens.characterId)/orders/", as: [ESIMarketOrder].self)
        }
    }

    public func contracts() async throws -> [ESIContract] {
        try await cached("contracts", ttl: 120) {
            try await esiGetPaginated("/characters/\(tokens.characterId)/contracts/", as: ESIContract.self)
        }
    }

    public func currentShip() async throws -> ESICurrentShip {
        try await cached("currentShip", ttl: 15) {
            try await esiGet("/characters/\(tokens.characterId)/ship/", as: ESICurrentShip.self)
        }
    }

    public func location() async throws -> ESICharacterLocation {
        try await cached("location", ttl: 15) {
            try await esiGet("/characters/\(tokens.characterId)/location/", as: ESICharacterLocation.self)
        }
    }

    public func characterAttributes() async throws -> ESICharacterAttributes {
        try await cached("characterAttributes", ttl: 300) {
            try await esiGet("/characters/\(tokens.characterId)/attributes/", as: ESICharacterAttributes.self)
        }
    }

    public func employmentHistory() async throws -> [ESIEmploymentHistoryItem] {
        try await cached("employmentHistory", ttl: 3_600) {
            try await esiGetPublic("/characters/\(tokens.characterId)/corporationhistory/", as: [ESIEmploymentHistoryItem].self)
        }
    }

    // MARK: - Fittings

    public func fittings() async throws -> [ESIFitting] {
        try await cached("fittings", ttl: 60) {
            try await esiGet("/characters/\(tokens.characterId)/fittings/", as: [ESIFitting].self)
        }
    }

    public func createFitting(_ fitting: ESICreateFitting) async throws -> ESICreateFittingResponse {
        let data = try JSONEncoder().encode(fitting)
        let result = try await esiPost("/characters/\(tokens.characterId)/fittings/", body: data, as: ESICreateFittingResponse.self)
        cacheStore["fittings"] = nil
        return result
    }

    // MARK: - Kill Mails (public endpoint)

    public func killMailDetail(id: Int, hash: String) async throws -> ESIKillMail {
        try await esiGetPublic("/killmails/\(id)/\(hash)/", as: ESIKillMail.self)
    }

    // MARK: - Market Transactions & Mining

    public func walletTransactions(fromId: Int? = nil) async throws -> [ESIWalletTransaction] {
        var items: [URLQueryItem] = []
        if let from = fromId { items.append(.init(name: "from_id", value: "\(from)")) }
        return try await cached("walletTransactions:\(fromId.map(String.init) ?? "latest")", ttl: 60) {
            try await esiGet("/characters/\(tokens.characterId)/wallet/transactions/",
                             queryItems: items, as: [ESIWalletTransaction].self)
        }
    }

    public func miningLedger() async throws -> [ESIMiningEntry] {
        try await cached("miningLedger", ttl: 300) {
            try await esiGetPaginated("/characters/\(tokens.characterId)/mining/", as: ESIMiningEntry.self)
        }
    }

    // MARK: - EVE Mail

    public func mailHeaders(lastMailId: Int? = nil, labels: [Int]? = nil) async throws -> [ESIMailHeader] {
        var items: [URLQueryItem] = []
        if let last = lastMailId { items.append(.init(name: "last_mail_id", value: "\(last)")) }
        if let labs = labels, !labs.isEmpty {
            for l in labs { items.append(.init(name: "labels[]", value: "\(l)")) }
        }
        let labelKey = labels?.map(String.init).joined(separator: ",") ?? "all"
        return try await cached("mailHeaders:\(lastMailId.map(String.init) ?? "latest"):\(labelKey)", ttl: 30) {
            try await esiGet("/characters/\(tokens.characterId)/mail/", queryItems: items, as: [ESIMailHeader].self)
        }
    }

    public func mailBody(mailId: Int) async throws -> ESIMailBody {
        try await esiGet("/characters/\(tokens.characterId)/mail/\(mailId)/", as: ESIMailBody.self)
    }

    public func mailLabels() async throws -> ESIMailLabelsResponse {
        try await cached("mailLabels", ttl: 60) {
            try await esiGet("/characters/\(tokens.characterId)/mail/labels/", as: ESIMailLabelsResponse.self)
        }
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
        try await cached("stationInfo:\(id)", ttl: 86_400) {
            try await esiGetPublic("/universe/stations/\(id)/", as: ESIStationInfo.self)
        }
    }

    public func systemInfo(id: Int) async throws -> ESISystemInfo {
        try await cached("systemInfo:\(id)", ttl: 86_400) {
            try await esiGetPublic("/universe/systems/\(id)/", as: ESISystemInfo.self)
        }
    }

    public func structureInfo(id: Int) async throws -> ESIStructureInfo {
        try await cached("structureInfo:\(id)", ttl: 3_600) {
            try await esiGet("/universe/structures/\(id)/", as: ESIStructureInfo.self)
        }
    }

    // MARK: - Authenticated GET (with optional query items)

    private func esiGet<T: Decodable & Sendable>(_ path: String, queryItems: [URLQueryItem], as type: T.Type) async throws -> T {
        if !tokens.isAccessTokenValid { tokens = try await authClient.refresh(tokens) }
        try ensureErrorBudget()
        var req = makeRequestWithQuery(path: path, queryItems: queryItems)
        req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await self.data(for: req, allowsCaching: true)
        if let http = response as? HTTPURLResponse {
            updateErrorLimit(from: http)
            if http.statusCode == 401 {
                tokens = try await authClient.refresh(tokens)
                req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
                let (data2, resp2) = try await self.data(for: req, allowsCaching: false)
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
        try ensureErrorBudget()
        var req = makeRequest(path: path)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = body
        let (data, response) = try await urlSession.data(for: req)
        if let http = response as? HTTPURLResponse {
            updateErrorLimit(from: http)
            if http.statusCode == 401 {
                tokens = try await authClient.refresh(tokens)
                req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
                let (data2, resp2) = try await urlSession.data(for: req)
                if let http2 = resp2 as? HTTPURLResponse {
                    updateErrorLimit(from: http2)
                }
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
        if let http = response as? HTTPURLResponse {
            updateErrorLimit(from: http)
            if !(200..<300).contains(http.statusCode) {
                throw AuthError.httpError(http.statusCode, String(data: data, encoding: .utf8))
            }
        }
        return try JSONDecoder.esi.decode(T.self, from: data)
    }

    // MARK: - Authenticated POST

    private func esiPost<T: Decodable & Sendable>(_ path: String, body: Data, as type: T.Type) async throws -> T {
        if !tokens.isAccessTokenValid { tokens = try await authClient.refresh(tokens) }
        try ensureErrorBudget()

        var req = makeRequest(path: path)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = body
        let (data, response) = try await urlSession.data(for: req)
        if let http = response as? HTTPURLResponse {
            updateErrorLimit(from: http)
            if http.statusCode == 401 {
                tokens = try await authClient.refresh(tokens)
                req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
                let (data2, resp2) = try await urlSession.data(for: req)
                if let http2 = resp2 as? HTTPURLResponse {
                    updateErrorLimit(from: http2)
                }
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

        try ensureErrorBudget()

        var req = makeRequest(path: path)
        req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await self.data(for: req, allowsCaching: true)

        if let http = response as? HTTPURLResponse {
            updateErrorLimit(from: http)
            if http.statusCode == 401 {
                // One retry after forced refresh.
                tokens = try await authClient.refresh(tokens)
                req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
                let (data2, resp2) = try await self.data(for: req, allowsCaching: false)
                if let http2 = resp2 as? HTTPURLResponse {
                    updateErrorLimit(from: http2)
                }
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
        let (data, response) = try await self.data(for: makeRequest(path: path), allowsCaching: true)
        if let http = response as? HTTPURLResponse {
            updateErrorLimit(from: http)
            if !(200..<300).contains(http.statusCode) {
                throw AuthError.httpError(http.statusCode, String(data: data, encoding: .utf8))
            }
        }
        return try JSONDecoder.esi.decode(T.self, from: data)
    }

    private func makeRequest(path: String) -> URLRequest {
        var req = URLRequest(url: EVEConstants.esiBase.appending(path: path))
        req.setValue(EVEConstants.userAgent, forHTTPHeaderField: "User-Agent")
        return req
    }

    // MARK: - Paginated fetch

    private func esiGetPaginated<T: Decodable & Sendable>(_ path: String, as type: T.Type) async throws -> [T] {
        let (firstData, response) = try await esiRawRequest(path: path, page: 1)
        let firstPage = try JSONDecoder.esi.decode([T].self, from: firstData)
        let totalPages = response.value(forHTTPHeaderField: "X-Pages").flatMap(Int.init) ?? 1
        guard totalPages > 1 else { return firstPage }

        var pages: [[T]?] = Array(repeating: nil, count: totalPages + 1)
        pages[1] = firstPage

        try await withThrowingTaskGroup(of: (Int, [T]).self) { group in
            for page in 2...totalPages {
                group.addTask {
                    let (data, _) = try await self.esiRawRequest(path: path, page: page)
                    return (page, try JSONDecoder.esi.decode([T].self, from: data))
                }
            }

            for try await (page, pageItems) in group {
                pages[page] = pageItems
            }
        }

        return pages.compactMap { $0 }.flatMap { $0 }
    }

    private func esiRawRequest(path: String, page: Int = 1) async throws -> (Data, HTTPURLResponse) {
        if !tokens.isAccessTokenValid {
            tokens = try await authClient.refresh(tokens)
        }
        try ensureErrorBudget()

        var req = pagedURLRequest(path: path, page: page)
        req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        updateErrorLimit(from: http)

        if http.statusCode == 401 {
            tokens = try await authClient.refresh(tokens)
            req.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
            let (data2, resp2) = try await urlSession.data(for: req)
            if let http2 = resp2 as? HTTPURLResponse {
                updateErrorLimit(from: http2)
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

    private func data(for request: URLRequest, allowsCaching: Bool) async throws -> (Data, URLResponse) {
        guard allowsCaching,
              request.httpMethod == nil || request.httpMethod == "GET",
              let url = request.url else {
            return try await urlSession.data(for: request)
        }

        if let cached = responseCache[url], cached.isFresh {
            return (cached.data, cached.response)
        }

        var req = request
        if let etag = responseCache[url]?.etag {
            req.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await urlSession.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            return (data, response)
        }

        if http.statusCode == 304, let cached = responseCache[url] {
            return (cached.data, http)
        }

        if (200..<300).contains(http.statusCode) {
            let etag = http.value(forHTTPHeaderField: "ETag")
            let expiresAt = http.value(forHTTPHeaderField: "Expires").flatMap(httpDate)
            if etag != nil || expiresAt != nil {
                responseCache[url] = CachedResponse(data: data, etag: etag, expiresAt: expiresAt, response: http)
            }
        }

        return (data, http)
    }

    private func ensureErrorBudget() throws {
        guard errorLimitRemaining > 10 else {
            let resetText = errorLimitResetAt.map { "reset at \($0)" } ?? "reset pending"
            throw AuthError.httpError(420, "ESI error limit reached, \(resetText)")
        }
    }

    private func updateErrorLimit(from response: HTTPURLResponse) {
        if let remain = response.value(forHTTPHeaderField: "X-ESI-Error-Limit-Remain").flatMap(Int.init) {
            errorLimitRemaining = remain
        }
        if let reset = response.value(forHTTPHeaderField: "X-ESI-Error-Limit-Reset").flatMap(Double.init) {
            errorLimitResetAt = Date().addingTimeInterval(reset)
        }
    }

    private func httpDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value)
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
