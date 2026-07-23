import AppKit
import ImageIO
import SwiftUI

struct CachedRemoteImage<Placeholder: View>: View {
    let url: URL?
    let contentMode: ContentMode
    let maxPixelSize: CGFloat
    @ViewBuilder let placeholder: () -> Placeholder

    @StateObject private var loader = RemoteImageLoader()

    private var cacheID: String {
        "\(url?.absoluteString ?? "nil")#\(Int(maxPixelSize))"
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: cacheID, priority: .utility) {
            await loader.load(url: url, maxPixelSize: maxPixelSize)
        }
    }
}

@MainActor
private final class RemoteImageLoader: ObservableObject {
    @Published var image: NSImage?
    @Published var isLoading = false

    private var currentKey: String?

    func load(url: URL?, maxPixelSize: CGFloat) async {
        guard let url else {
            image = nil
            isLoading = false
            currentKey = nil
            return
        }

        let key = RemoteImageCache.key(url: url, maxPixelSize: maxPixelSize)
        currentKey = key

        if let cached = RemoteImageCache.shared.image(forKey: key) {
            image = cached
            isLoading = false
            return
        }

        image = nil
        isLoading = true

        do {
            let data: Data
            if url.isFileURL {
                data = try Data(contentsOf: url)
            } else {
                var request = URLRequest(url: url)
                request.timeoutInterval = 24
                request.cachePolicy = .returnCacheDataElseLoad
                request.setValue("WallDive macOS/3.1.1", forHTTPHeaderField: "User-Agent")
                request.setValue("image/avif,image/webp,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

                let (remoteData, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else { return }
                if let http = response as? HTTPURLResponse, !(200..<300 ~= http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                data = remoteData
            }

            let decodedCGImage = await Task.detached(priority: .utility) {
                Self.decodeImage(data: data, maxPixelSize: maxPixelSize)
            }.value

            guard currentKey == key else { return }
            if let decodedCGImage {
                let decodedImage = NSImage(
                    cgImage: decodedCGImage,
                    size: NSSize(width: decodedCGImage.width, height: decodedCGImage.height)
                )
                RemoteImageCache.shared.setImage(
                    decodedImage,
                    forKey: key,
                    cost: decodedCGImage.bytesPerRow * decodedCGImage.height
                )
                image = decodedImage
            }
            isLoading = false
        } catch {
            guard currentKey == key else { return }
            image = nil
            isLoading = false
        }
    }

    nonisolated private static func decodeImage(data: Data, maxPixelSize: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, Int(maxPixelSize))
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            )
    }
}

private final class RemoteImageCache: NSObject, NSCacheDelegate {
    static let shared = RemoteImageCache()

    private let cache = NSCache<NSString, NSImage>()
    private let lock = NSLock()
    private var totalCost = 0
    private var costByKey: [String: Int] = [:]
    private var objectIDByKey: [String: ObjectIdentifier] = [:]
    private var keyByObjectID: [ObjectIdentifier: String] = [:]

    private override init() {
        super.init()
        cache.delegate = self
        cache.countLimit = 420
        cache.totalCostLimit = 220 * 1024 * 1024
    }

    static func key(url: URL, maxPixelSize: CGFloat) -> String {
        "\(url.absoluteString)#\(Int(maxPixelSize))"
    }

    func image(forKey key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: NSImage, forKey key: String, cost: Int) {
        lock.lock()
        if let oldCost = costByKey[key] {
            totalCost -= oldCost
        }
        if let oldObjectID = objectIDByKey[key] {
            keyByObjectID.removeValue(forKey: oldObjectID)
        }
        let objectID = ObjectIdentifier(image)
        costByKey[key] = cost
        objectIDByKey[key] = objectID
        keyByObjectID[objectID] = key
        totalCost += cost
        lock.unlock()

        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func removeAll() {
        lock.lock()
        totalCost = 0
        costByKey.removeAll()
        objectIDByKey.removeAll()
        keyByObjectID.removeAll()
        lock.unlock()
        cache.removeAllObjects()
    }

    func byteCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return totalCost
    }

    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject object: Any) {
        guard let image = object as? NSImage else { return }
        let objectID = ObjectIdentifier(image)

        lock.lock()
        if let key = keyByObjectID.removeValue(forKey: objectID) {
            objectIDByKey.removeValue(forKey: key)
            if let cost = costByKey.removeValue(forKey: key) {
                totalCost -= cost
            }
        }
        lock.unlock()
    }
}

func clearImageCache() {
    RemoteImageCache.shared.removeAll()
    URLCache.shared.removeAllCachedResponses()
}

func imageCacheByteCount() -> Int64 {
    let memoryBytes = RemoteImageCache.shared.byteCount()
    let urlCacheBytes = URLCache.shared.currentDiskUsage + URLCache.shared.currentMemoryUsage
    return Int64(memoryBytes + urlCacheBytes)
}

func formattedImageCacheSize() -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: imageCacheByteCount())
}
