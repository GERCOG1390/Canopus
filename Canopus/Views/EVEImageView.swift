import SwiftUI
import ImageIO
import EVEAuth

// MARK: - Shared image cache

fileprivate actor EVEImageLoader {
    static let shared = EVEImageLoader()

    private let session: URLSession
    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 500
        cache.totalCostLimit = 50 * 1024 * 1024
        return cache
    }()

    private struct ImageRequest: Hashable {
        let url: URL
        let maxPixelSize: Int

        var cacheKey: NSString {
            "\(url.absoluteString)#\(maxPixelSize)" as NSString
        }
    }

    // Coalesces concurrent requests for the same URL so N identical icons
    // on screen at once trigger a single network fetch instead of N.
    private var inFlight: [ImageRequest: Task<UIImage, Error>] = [:]

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(
            memoryCapacity: 30 * 1024 * 1024,
            diskCapacity: 100 * 1024 * 1024
        )
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.httpAdditionalHeaders = ["User-Agent": EVEConstants.userAgent]
        session = URLSession(configuration: cfg)
    }

    func image(for url: URL, targetPixelSize: CGFloat?) async throws -> UIImage {
        let request = ImageRequest(url: url, maxPixelSize: max(32, Int((targetPixelSize ?? 128).rounded(.up))))
        let key = request.cacheKey
        if let cached = cache.object(forKey: key) { return cached }

        if let existing = inFlight[request] {
            return try await existing.value
        }

        let task = Task<UIImage, Error> {
            let data = try await Self.data(from: url, session: session)
            guard let img = Self.downsampledImage(from: data, maxPixelSize: request.maxPixelSize) else {
                throw URLError(.badServerResponse)
            }
            let pixelCount = Int(img.size.width * img.scale * img.size.height * img.scale)
            let cost = max(data.count, pixelCount * 4)
            cache.setObject(img, forKey: key, cost: cost)
            return img
        }
        inFlight[request] = task
        defer { inFlight[request] = nil }
        return try await task.value
    }

    fileprivate nonisolated static func data(from url: URL, session: URLSession) async throws -> Data {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                return data
            } catch {
                if Task.isCancelled { throw error }
                lastError = error
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(150_000_000 * (attempt + 1)))
                }
            }
        }
        throw lastError ?? URLError(.badServerResponse)
    }

    private nonisolated static func downsampledImage(from data: Data, maxPixelSize: Int) -> UIImage? {
        if maxPixelSize <= 160 {
            return UIImage(data: data)
        }

        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return UIImage(data: data)
        }
        guard CGImageSourceGetCount(source) > 0 else {
            return UIImage(data: data)
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return UIImage(data: data)
        }

        return UIImage(cgImage: cgImage)
    }
}

private enum EVEImageServer {
    static let modulePreferredVariations = ["icon", "bp", "bpc", "relic", "render"]
    static let renderPreferredVariations = ["render", "icon", "bp", "bpc", "relic"]

    static func supportedSize(for points: CGFloat) -> Int {
        let requested = max(32, Int(points.rounded(.up)))
        for size in [32, 64, 128, 256, 512, 1024] where requested <= size {
            return size
        }
        return 1024
    }

    static func typeURL(typeId: Int, variation: String, displaySize: CGFloat) -> URL {
        let px = supportedSize(for: displaySize * 3)
        return URL(string: "https://images.evetech.net/types/\(typeId)/\(variation)?size=\(px)")!
    }

    static func characterPortraitURL(characterId: Int, displaySize: CGFloat) -> URL {
        let px = supportedSize(for: displaySize * 3)
        return URL(string: "https://images.evetech.net/characters/\(characterId)/portrait?size=\(px)")!
    }

    static func corporationLogoURL(corpId: Int, displaySize: CGFloat) -> URL {
        let px = supportedSize(for: displaySize * 3)
        return URL(string: "https://images.evetech.net/corporations/\(corpId)/logo?size=\(px)")!
    }

    static func allianceLogoURL(allianceId: Int, displaySize: CGFloat) -> URL {
        let px = supportedSize(for: displaySize * 3)
        return URL(string: "https://images.evetech.net/alliances/\(allianceId)/logo?size=\(px)")!
    }
}

private actor EVETypeVariationResolver {
    static let shared = EVETypeVariationResolver()

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 20 * 1024 * 1024)
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.httpAdditionalHeaders = ["User-Agent": EVEConstants.userAgent]
        return URLSession(configuration: cfg)
    }()

    private var cache: [Int: [String]] = [:]
    private var inFlight: [Int: Task<[String], Error>] = [:]

    func variations(for typeId: Int) async -> [String] {
        if let cached = cache[typeId] { return cached }
        if let existing = inFlight[typeId], let value = try? await existing.value {
            return value
        }

        let task = Task<[String], Error> {
            let url = URL(string: "https://images.evetech.net/types/\(typeId)")!
            let data = try await EVEImageLoader.data(from: url, session: session)
            let variations = try JSONDecoder().decode([String].self, from: data)
            return variations
        }
        inFlight[typeId] = task
        defer { inFlight[typeId] = nil }

        do {
            let variations = try await task.value
            cache[typeId] = variations
            return variations
        } catch {
            return []
        }
    }
}

private actor EVEIconFileResolver {
    static let shared = EVEIconFileResolver()

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(memoryCapacity: 5 * 1024 * 1024, diskCapacity: 25 * 1024 * 1024)
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.httpAdditionalHeaders = ["User-Agent": EVEConstants.userAgent]
        return URLSession(configuration: cfg)
    }()

    private struct IconRecord: Decodable {
        let iconFile: String

        enum CodingKeys: String, CodingKey {
            case iconFile = "icon_file"
        }
    }

    private var cache: [Int: URL] = [:]

    func url(for iconId: Int) async -> URL? {
        if let cached = cache[iconId] { return cached }
        guard let metadataURL = URL(string: "https://ref-data.everef.net/icons/\(iconId)") else { return nil }

        do {
            let data = try await EVEImageLoader.data(from: metadataURL, session: session)
            let record = try JSONDecoder().decode(IconRecord.self, from: data)
            guard let fileName = record.iconFile.split(separator: "/").last else { return nil }
            let url = URL(string: "https://iec.jita.space/items/\(fileName)")!
            cache[iconId] = url
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Reusable image view

private struct EVERemoteImage: View {
    let url: URL
    var fallbackURLs: [URL] = []
    var contentMode: ContentMode = .fit
    var placeholderSystemName: String? = "photo"
    var showsLoadingIndicator = true
    var targetPixelSize: CGFloat? = nil

    @State private var image: UIImage?
    @State private var loading = true

    private struct TaskID: Hashable {
        let urls: [URL]
        let targetPixelSize: Int
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if loading && showsLoadingIndicator {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let placeholderSystemName {
                Image(systemName: placeholderSystemName)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.quaternary)
                    .padding(8)
            } else {
                Color.clear
            }
        }
        .task(id: TaskID(urls: [url] + fallbackURLs, targetPixelSize: Int((targetPixelSize ?? 128).rounded(.up)))) {
            loading = true
            image = nil
            for candidate in [url] + fallbackURLs {
                if let loaded = try? await EVEImageLoader.shared.image(for: candidate, targetPixelSize: targetPixelSize) {
                    image = loaded
                    break
                }
            }
            loading = false
        }
    }
}

private struct EVETypeRemoteImage: View {
    let typeId: Int
    let preferredVariations: [String]
    var contentMode: ContentMode = .fit
    var placeholderSystemName: String? = "photo"
    var showsLoadingIndicator = true
    var targetPixelSize: CGFloat? = nil
    var displaySize: CGFloat

    @State private var urls: [URL] = []

    private struct TaskID: Hashable {
        let typeId: Int
        let preferredVariations: [String]
        let displaySize: Int
    }

    var body: some View {
        Group {
            if let first = urls.first {
                EVERemoteImage(
                    url: first,
                    fallbackURLs: Array(urls.dropFirst()),
                    contentMode: contentMode,
                    placeholderSystemName: placeholderSystemName,
                    showsLoadingIndicator: showsLoadingIndicator,
                    targetPixelSize: targetPixelSize
                )
            } else if showsLoadingIndicator {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let placeholderSystemName {
                Image(systemName: placeholderSystemName)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.quaternary)
                    .padding(8)
            } else {
                Color.clear
            }
        }
        .task(id: TaskID(typeId: typeId, preferredVariations: preferredVariations, displaySize: Int(displaySize.rounded(.up)))) {
            let available = await EVETypeVariationResolver.shared.variations(for: typeId)
            let orderedVariations: [String]
            if available.isEmpty {
                orderedVariations = preferredVariations
            } else {
                let availableSet = Set(available)
                orderedVariations = preferredVariations.filter { availableSet.contains($0) }
            }
            urls = orderedVariations.map {
                EVEImageServer.typeURL(typeId: typeId, variation: $0, displaySize: displaySize)
            }
        }
    }
}

// MARK: - Public views

struct EVETypeIcon: View {
    let typeId: Int
    var size: CGFloat = 32

    var body: some View {
        EVETypeRemoteImage(
            typeId: typeId,
            preferredVariations: EVEImageServer.modulePreferredVariations,
            targetPixelSize: size * 3,
            displaySize: size
        )
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
    }
}

struct EVEIconImage: View {
    let iconId: Int
    var size: CGFloat = 24
    @State private var resolvedURL: URL?

    var body: some View {
        Group {
            if let resolvedURL {
                EVERemoteImage(url: resolvedURL, placeholderSystemName: nil, showsLoadingIndicator: false, targetPixelSize: size * 3)
            } else {
                Image(systemName: "cube")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary.opacity(0.45))
                    .padding(size * 0.18)
            }
        }
        .frame(width: size, height: size)
        .task(id: iconId) {
            resolvedURL = nil
            resolvedURL = await EVEIconFileResolver.shared.url(for: iconId)
        }
    }
}

struct EVERenderImage: View {
    let typeId: Int
    var size: CGFloat = 256

    var body: some View {
        EVETypeRemoteImage(
            typeId: typeId,
            preferredVariations: EVEImageServer.renderPreferredVariations,
            targetPixelSize: size * 3,
            displaySize: size
        )
            .frame(width: size, height: size)
    }
}

struct EVECorpLogo: View {
    let corpId: Int
    var size: CGFloat = 32

    var body: some View {
        EVERemoteImage(url: logoURL, targetPixelSize: size * 3)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
    }

    private var logoURL: URL {
        EVEImageServer.corporationLogoURL(corpId: corpId, displaySize: size)
    }
}

struct EVEAllianceLogo: View {
    let allianceId: Int
    var size: CGFloat = 32

    var body: some View {
        EVERemoteImage(url: logoURL, targetPixelSize: size * 3)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
    }

    private var logoURL: URL {
        EVEImageServer.allianceLogoURL(allianceId: allianceId, displaySize: size)
    }
}

struct EVECharacterPortrait: View {
    let characterId: Int
    var size: CGFloat = 64
    var contentMode: ContentMode = .fit

    var body: some View {
        EVERemoteImage(url: portraitURL, contentMode: contentMode, targetPixelSize: size * 3)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.15))
    }

    private var portraitURL: URL {
        EVEImageServer.characterPortraitURL(characterId: characterId, displaySize: size)
    }
}

/// Full-width hero portrait for character cards. Fills proposed width, fixed height.
struct EVEHeroPortrait: View {
    let characterId: Int
    var height: CGFloat = 240

    var body: some View {
        EVERemoteImage(
            url: EVEImageServer.characterPortraitURL(characterId: characterId, displaySize: height),
            contentMode: .fill,
            targetPixelSize: height * 3
        )
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
    }
}

/// Gold ISK currency badge.
struct ISKIcon: View {
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.90, green: 0.75, blue: 0.22),
                            Color(red: 0.68, green: 0.52, blue: 0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("ISK")
                .font(.system(size: size * 0.30, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .tracking(-0.5)
        }
        .frame(width: size, height: size)
    }
}
