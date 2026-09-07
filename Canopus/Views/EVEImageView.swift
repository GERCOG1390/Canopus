import SwiftUI

// MARK: - Shared image cache

private final class EVEImageLoader: @unchecked Sendable {
    static let shared = EVEImageLoader()

    private let session: URLSession
    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(
            memoryCapacity: 30 * 1024 * 1024,
            diskCapacity: 100 * 1024 * 1024
        )
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.httpAdditionalHeaders = ["User-Agent": "Canopus/1.0 (gercogunlimited@gmail.com)"]
        session = URLSession(configuration: cfg)
    }

    func image(for url: URL) async throws -> UIImage {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) { return cached }
        let (data, _) = try await session.data(from: url)
        guard let img = UIImage(data: data) else { throw URLError(.badServerResponse) }
        cache.setObject(img, forKey: key)
        return img
    }
}

// MARK: - Reusable image view

private struct EVERemoteImage: View {
    let url: URL
    var contentMode: ContentMode = .fit

    @State private var image: UIImage?
    @State private var loading = true

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if loading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.quaternary)
                    .padding(8)
            }
        }
        .task(id: url) {
            loading = true
            image = try? await EVEImageLoader.shared.image(for: url)
            loading = false
        }
    }
}

// MARK: - Public views

struct EVETypeIcon: View {
    let typeId: Int
    var size: CGFloat = 32

    var body: some View {
        EVERemoteImage(url: iconURL)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
    }

    private var iconURL: URL {
        let px = size <= 32 ? 32 : size <= 64 ? 64 : 128
        return URL(string: "https://images.evetech.net/types/\(typeId)/icon?size=\(px)")!
    }
}

struct EVERenderImage: View {
    let typeId: Int
    var size: CGFloat = 256

    var body: some View {
        EVERemoteImage(url: renderURL)
            .frame(width: size, height: size)
    }

    private var renderURL: URL {
        URL(string: "https://images.evetech.net/types/\(typeId)/render?size=256")!
    }
}

struct EVECorpLogo: View {
    let corpId: Int
    var size: CGFloat = 32

    var body: some View {
        EVERemoteImage(url: logoURL)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
    }

    private var logoURL: URL {
        URL(string: "https://images.evetech.net/corporations/\(corpId)/logo?size=64")!
    }
}

struct EVECharacterPortrait: View {
    let characterId: Int
    var size: CGFloat = 64
    var contentMode: ContentMode = .fit

    var body: some View {
        EVERemoteImage(url: portraitURL, contentMode: contentMode)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.15))
    }

    private var portraitURL: URL {
        let px = size <= 64 ? 64 : size <= 128 ? 128 : 256
        return URL(string: "https://images.evetech.net/characters/\(characterId)/portrait?size=\(px)")!
    }
}

/// Full-width hero portrait for character cards. Fills proposed width, fixed height.
struct EVEHeroPortrait: View {
    let characterId: Int
    var height: CGFloat = 240

    var body: some View {
        EVERemoteImage(
            url: URL(string: "https://images.evetech.net/characters/\(characterId)/portrait?size=512")!,
            contentMode: .fill
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
