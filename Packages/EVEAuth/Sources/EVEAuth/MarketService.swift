import Foundation

// MARK: - Regions

public enum EVERegion: Int, CaseIterable, Sendable {
    case theForge   = 10000002
    case domain     = 10000043
    case heimatar   = 10000030
    case metropolis = 10000042
    case sinqLaison = 10000032

    public var displayName: String {
        switch self {
        case .theForge:   return "The Forge"
        case .domain:     return "Domain"
        case .heimatar:   return "Heimatar"
        case .metropolis: return "Metropolis"
        case .sinqLaison: return "Sinq Laison"
        }
    }

    public var hubName: String {
        switch self {
        case .theForge:   return "Jita"
        case .domain:     return "Amarr"
        case .heimatar:   return "Rens"
        case .metropolis: return "Hek"
        case .sinqLaison: return "Dodixie"
        }
    }
}

// MARK: - Service

/// Unauthenticated ESI market data client.
@MainActor
public final class MarketService {
    private let urlSession: URLSession
    private var errorLimitRemaining = 100
    private var errorLimitResetAt: Date?
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

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func serverStatus() async throws -> ESIServerStatus {
        try await get(path: "/status/", as: ESIServerStatus.self)
    }

    public func marketPrices() async throws -> [ESIMarketPrice] {
        try await get(path: "/markets/prices/", as: [ESIMarketPrice].self)
    }

    public func history(regionId: Int, typeId: Int) async throws -> [ESIMarketHistory] {
        try await get(
            path: "/markets/\(regionId)/history/",
            queryItems: [.init(name: "type_id", value: "\(typeId)")],
            as: [ESIMarketHistory].self
        )
    }

    public func orders(regionId: Int, typeId: Int) async throws -> [ESIRegionalOrder] {
        try await getPaginated(
            path: "/markets/\(regionId)/orders/",
            queryItems: [
                .init(name: "type_id",    value: "\(typeId)"),
                .init(name: "order_type", value: "all"),
            ],
            as: ESIRegionalOrder.self
        )
    }

    // MARK: - Private

    private func get<T: Decodable & Sendable>(path: String, queryItems: [URLQueryItem] = [], as type: T.Type) async throws -> T {
        guard let req = makeRequest(path: path, queryItems: queryItems) else {
            throw URLError(.badURL)
        }
        try ensureErrorBudget()
        let (data, response) = try await data(for: req, allowsCaching: true)
        if let http = response as? HTTPURLResponse {
            updateErrorLimit(from: http)
            if !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
        }
        return try JSONDecoder.esi.decode(T.self, from: data)
    }

    private func getPaginated<T: Decodable & Sendable>(path: String, queryItems: [URLQueryItem], as type: T.Type) async throws -> [T] {
        var result: [T] = []
        var page = 1
        var totalPages = 1
        repeat {
            guard let req = makeRequest(path: path, queryItems: queryItems, page: page) else {
                throw URLError(.badURL)
            }
            try ensureErrorBudget()
            let (data, response) = try await urlSession.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            updateErrorLimit(from: http)
            if page == 1 {
                totalPages = http.value(forHTTPHeaderField: "X-Pages").flatMap(Int.init) ?? 1
            }
            guard (200..<300).contains(http.statusCode) else {
                throw AuthError.httpError(http.statusCode, String(data: data, encoding: .utf8))
            }
            result += try JSONDecoder.esi.decode([T].self, from: data)
            page += 1
        } while page <= totalPages
        return result
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem] = [], page: Int = 1) -> URLRequest? {
        let base = EVEConstants.esiBase.appending(path: path)
        guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        var items = queryItems
        if page > 1 { items.append(.init(name: "page", value: "\(page)")) }
        if !items.isEmpty { comps.queryItems = items }
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue(EVEConstants.userAgent, forHTTPHeaderField: "User-Agent")
        return req
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
}
