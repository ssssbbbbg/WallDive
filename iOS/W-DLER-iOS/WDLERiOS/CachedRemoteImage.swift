import ImageIO
import SwiftUI
import UIKit

struct IOSCachedRemoteImage<Placeholder: View>: View {
    let url: URL?
    let contentMode: ContentMode
    let maxPixelSize: CGFloat
    @ViewBuilder let placeholder: () -> Placeholder

    @StateObject private var loader = IOSRemoteImageLoader()

    private var cacheID: String {
        "\(url?.absoluteString ?? "nil")#\(Int(maxPixelSize))"
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
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

struct IOSZoomableRemoteImage: View {
    let url: URL?
    let maxPixelSize: CGFloat
    let onSingleTap: () -> Void

    @StateObject private var loader = IOSRemoteImageLoader()

    private var cacheID: String {
        "\(url?.absoluteString ?? "nil")#\(Int(maxPixelSize))"
    }

    var body: some View {
        Group {
            if let image = loader.image {
                IOSNativeZoomableImage(image: image, onSingleTap: onSingleTap)
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: cacheID, priority: .userInitiated) {
            await loader.load(url: url, maxPixelSize: maxPixelSize)
        }
    }
}

private struct IOSNativeZoomableImage: UIViewRepresentable {
    let image: UIImage
    let onSingleTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSingleTap: onSingleTap)
    }

    func makeUIView(context: Context) -> IOSImageZoomScrollView {
        let scrollView = IOSImageZoomScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.decelerationRate = .fast
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .black

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap))
        tap.numberOfTapsRequired = 1
        tap.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(tap)
        scrollView.setImage(image)
        return scrollView
    }

    func updateUIView(_ scrollView: IOSImageZoomScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        if scrollView.imageView.image !== image {
            scrollView.setImage(image)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var onSingleTap: () -> Void

        init(onSingleTap: @escaping () -> Void) {
            self.onSingleTap = onSingleTap
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? IOSImageZoomScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? IOSImageZoomScrollView)?.centerImage()
        }

        @objc func handleSingleTap() {
            onSingleTap()
        }
    }
}

private final class IOSImageZoomScrollView: UIScrollView {
    let imageView = UIImageView()
    private var lastBoundsSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if bounds.size != lastBoundsSize {
            lastBoundsSize = bounds.size
            setZoomScale(minimumZoomScale, animated: false)
            layoutImageAtMinimumZoom()
        }
        centerImage()
    }

    func setImage(_ image: UIImage) {
        imageView.image = image
        setZoomScale(minimumZoomScale, animated: false)
        layoutImageAtMinimumZoom()
        setContentOffset(.zero, animated: false)
    }

    func centerImage() {
        let horizontalInset = max((bounds.width - contentSize.width) / 2, 0)
        let verticalInset = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }

    private func layoutImageAtMinimumZoom() {
        guard let image = imageView.image, bounds.width > 0, bounds.height > 0 else { return }
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let fitScale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let fittedSize = CGSize(
            width: max(1, imageSize.width * fitScale),
            height: max(1, imageSize.height * fitScale)
        )
        imageView.frame = CGRect(origin: .zero, size: fittedSize)
        contentSize = fittedSize
        centerImage()
    }
}

@MainActor
private final class IOSRemoteImageLoader: ObservableObject {
    @Published var image: UIImage?
    private var currentKey: String?

    func load(url: URL?, maxPixelSize: CGFloat) async {
        guard let url else {
            image = nil
            currentKey = nil
            return
        }

        let key = IOSRemoteImageCache.key(url: url, maxPixelSize: maxPixelSize)
        currentKey = key

        if let cached = IOSRemoteImageCache.shared.image(forKey: key) {
            image = cached
            return
        }

        image = nil

        do {
            let data: Data
            if url.isFileURL {
                data = try Data(contentsOf: url)
            } else {
                var request = URLRequest(url: url)
                request.timeoutInterval = 24
                request.cachePolicy = .returnCacheDataElseLoad
                request.setValue("WallDive iOS/3.1.1", forHTTPHeaderField: "User-Agent")
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
                let image = UIImage(cgImage: decodedCGImage)
                IOSRemoteImageCache.shared.setImage(
                    image,
                    forKey: key,
                    cost: decodedCGImage.bytesPerRow * decodedCGImage.height
                )
                self.image = image
            }
        } catch {
            guard currentKey == key else { return }
            image = nil
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
    }
}

private final class IOSRemoteImageCache: NSObject, NSCacheDelegate {
    static let shared = IOSRemoteImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    private var totalCost = 0
    private var costByKey: [String: Int] = [:]
    private var objectIDByKey: [String: ObjectIdentifier] = [:]
    private var keyByObjectID: [ObjectIdentifier: String] = [:]

    private override init() {
        super.init()
        cache.delegate = self
        cache.countLimit = 360
        cache.totalCostLimit = 160 * 1024 * 1024
    }

    static func key(url: URL, maxPixelSize: CGFloat) -> String {
        "\(url.absoluteString)#\(Int(maxPixelSize))"
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: UIImage, forKey key: String, cost: Int) {
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

    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        guard let image = obj as? UIImage else { return }
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

func IOSClearImageCache() {
    IOSRemoteImageCache.shared.removeAll()
    URLCache.shared.removeAllCachedResponses()
}

func IOSImageCacheByteCount() -> Int64 {
    let memoryImageBytes = IOSRemoteImageCache.shared.byteCount()
    let urlCacheBytes = URLCache.shared.currentDiskUsage + URLCache.shared.currentMemoryUsage
    return Int64(memoryImageBytes + urlCacheBytes)
}

func IOSFormattedCacheSize() -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: IOSImageCacheByteCount())
}
