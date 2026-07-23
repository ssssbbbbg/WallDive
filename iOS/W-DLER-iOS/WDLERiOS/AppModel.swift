import Foundation
import Combine
import SwiftUI
import UIKit

@MainActor
final class IOSAppModel: ObservableObject {
    @Published var filters = IOSSearchFilters()
    @Published var galleryMode: IOSGalleryMode = .discover
    @Published private(set) var wallpapers: [IOSWallpaper] = []
    @Published private(set) var meta: IOSSearchMeta?
    @Published var selectedWallpaper: IOSWallpaper?
    @Published var errorMessage: String?
    @Published var networkUnavailable = false
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var isHeaderCollapsed = false
    @Published var headerCollapseProgress: CGFloat = 0
    @Published var isHomeGalleryScrolling = false
    @Published private(set) var homeRefreshAnimationToken = 0
    @Published private(set) var homeRefreshFeedback: IOSHomeRefreshFeedback?
    private(set) var homeScrollOffsetY: CGFloat = 0
    @Published var isMultiSelecting = false
    @Published private(set) var selectedWallpaperIDs: Set<String> = []
    @Published private(set) var selectedWallpapersByID: [String: IOSWallpaper] = [:]
    @Published private(set) var favoriteWallpapers: [String: IOSWallpaper] = [:]
    @Published private(set) var localUploadedWallpapers: [IOSWallpaper] = []
    @Published private(set) var subscribedUsers: [IOSSubscribedUser] = []
    @Published private(set) var followedTags: [IOSFollowedTag] = []
    @Published var avatarImageData: Data?
    @Published var displayName: String {
        didSet {
            UserDefaults.standard.set(displayName, forKey: Defaults.displayName)
        }
    }
    @Published var avatarURLString: String {
        didSet {
            UserDefaults.standard.set(avatarURLString, forKey: Defaults.avatarURLString)
        }
    }
    @Published var themeMode: IOSThemeMode {
        didSet {
            UserDefaults.standard.set(themeMode.rawValue, forKey: Defaults.themeMode)
        }
    }
    @Published var languageMode: IOSAppLanguage {
        didSet {
            UserDefaults.standard.set(languageMode.rawValue, forKey: Defaults.languageMode)
            downloads.language = languageMode
        }
    }
    @Published var apiKey: String {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: Defaults.apiKey)
        }
    }
    @Published var includeAdultContent: Bool {
        didSet {
            UserDefaults.standard.set(includeAdultContent, forKey: Defaults.includeAdultContent)
        }
    }

    let downloads = IOSDownloadManager()

    private let api = IOSWallhavenAPI()
    private var loadTask: Task<Void, Never>?
    private var activeLoadID: UUID?
    private var refreshFeedbackTask: Task<Void, Never>?
#if DEBUG
    private var fixtureQueuedWallpapers: [IOSWallpaper] = []
#endif
    private var didInitialLoad = false
    private var downloadsCancellable: AnyCancellable?

    init() {
        let defaults = UserDefaults.standard
        let storedDisplayName = defaults.string(forKey: Defaults.displayName)
        let usesLegacyDisplayName = storedDisplayName.map { ["W-DLER", "W-DLER iOS"].contains($0) } ?? false
        let migratedDisplayName = usesLegacyDisplayName ? "WallDive" : storedDisplayName

        apiKey = defaults.string(forKey: Defaults.apiKey) ?? ""
        includeAdultContent = defaults.bool(forKey: Defaults.includeAdultContent)
        displayName = migratedDisplayName ?? "WallDive"
        avatarURLString = defaults.string(forKey: Defaults.avatarURLString) ?? ""
        themeMode = IOSThemeMode(rawValue: defaults.string(forKey: Defaults.themeMode) ?? "") ?? .system
        languageMode = IOSAppLanguage(rawValue: defaults.string(forKey: Defaults.languageMode) ?? "") ?? .zhHans
        if migratedDisplayName != storedDisplayName {
            defaults.set(migratedDisplayName, forKey: Defaults.displayName)
        }
        avatarImageData = try? Data(contentsOf: Self.avatarFileURL)
        favoriteWallpapers = Self.loadCodable([String: IOSWallpaper].self, forKey: Defaults.favorites) ?? [:]
        localUploadedWallpapers = Self.loadCodable([IOSWallpaper].self, forKey: Defaults.localUploads) ?? []
        subscribedUsers = Self.loadCodable([IOSSubscribedUser].self, forKey: Defaults.subscribedUsers) ?? []
        followedTags = Self.loadCodable([IOSFollowedTag].self, forKey: Defaults.followedTags) ?? []
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-debugHomeOffset"),
           arguments.indices.contains(index + 1),
           let offset = Double(arguments[index + 1]) {
            homeScrollOffsetY = CGFloat(offset)
        }
        if arguments.contains("-forceHomeRefreshIcon") {
            isHomeGalleryScrolling = true
        }
#endif
        downloads.language = languageMode
        downloadsCancellable = downloads.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.objectWillChange.send()
            }
        }

        Task { @MainActor [weak self] in
            self?.initialLoad()
        }
    }

    var title: String {
        title(for: galleryMode)
    }

    var subtitle: String {
        if galleryMode == .favorites {
            return String(format: t("wallpaper_count"), "\(visibleWallpapers.count)")
        }
        if let meta {
            return String(format: t("wallpaper_count"), "\(wallpapers.count) / \(meta.total)")
        }
        return "WallDive iOS"
    }

    func t(_ key: String) -> String {
        IOSL10n.t(key, languageMode)
    }

    func title(for mode: IOSGalleryMode) -> String {
        switch mode {
        case .discover:
            return t("discover_wallpapers")
        case .favorites:
            return t("favorites")
        case .userUploads(let username):
            return languageMode == .en ? "\(username)'s Uploads" : "\(username) 的上传"
        case .tag(let tagName):
            return "#\(tagName)"
        }
    }

    var canLoadMore: Bool {
        guard galleryMode != .favorites else { return false }
        guard let meta else { return false }
        return meta.currentPage < meta.lastPage
    }

    var canUseNSFW: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var effectiveAdultContentEnabled: Bool {
        includeAdultContent && canUseNSFW
    }

    var avatarURL: URL? {
        URL.wallhavenSafeURL(from: avatarURLString)
    }

    var visibleWallpapers: [IOSWallpaper] {
        if galleryMode == .favorites {
            return favoriteWallpapers.values.sorted { $0.createdAt > $1.createdAt }
        }
        return wallpapers
    }

    var selectedLoadedWallpapers: [IOSWallpaper] {
        selectedWallpaperIDs.compactMap { selectedWallpapersByID[$0] }
    }

    func initialLoad() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-useFixtureWallpapers") || arguments.contains("-usePagedFixtureWallpapers") {
            loadFixtureWallpapers()
            return
        }
#endif
        let canRetryEmptyState = wallpapers.isEmpty && !isLoading && !isLoadingMore
        guard !didInitialLoad || canRetryEmptyState else { return }
        didInitialLoad = true
        submitSearch()
    }

    func runSearch(reset: Bool) {
        search(reset: reset, mode: galleryMode)
    }

    func refreshCurrentSearch(showFeedback: Bool = false) {
        homeRefreshAnimationToken &+= 1
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-useFixtureWallpapers") || arguments.contains("-usePagedFixtureWallpapers") {
            if showFeedback {
                beginHomeRefreshFeedback()
                let visibleCount = visibleWallpapers.count
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 520_000_000)
                    self?.finishHomeRefreshFeedback(.success(visibleCount))
                }
            }
            return
        }
#endif
        if galleryMode == .favorites {
            errorMessage = nil
            if showFeedback {
                beginHomeRefreshFeedback()
                finishHomeRefreshFeedback(.success(visibleWallpapers.count))
            }
            return
        }
        search(reset: true, mode: galleryMode, showRefreshFeedback: showFeedback)
    }

    func submitSearch() {
        galleryMode = .discover
        search(reset: true, mode: .discover)
    }

    private func search(reset: Bool, mode: IOSGalleryMode, showRefreshFeedback: Bool = false) {
        applyHiddenDefaultFilters()

        guard filters.hasEnabledCategory else {
            errorMessage = t("at_least_one_category")
            return
        }

        guard filters.hasEnabledPurity else {
            errorMessage = t("at_least_one_purity")
            return
        }

        if !canUseNSFW, filters.nsfw {
            filters.nsfw = false
        }

        galleryMode = mode
        let page = reset ? 1 : (meta?.currentPage ?? 0) + 1
        let requestFilters = filters
        let requestAPIKey = apiKeyForSearch(filters: requestFilters)
        let requestSeed = reset ? nil : meta?.seed

        fetch(page: page, reset: reset, showRefreshFeedback: showRefreshFeedback) { [api] in
            try await api.searchWithFallback(
                filters: requestFilters,
                page: page,
                apiKey: requestAPIKey,
                seed: requestSeed
            )
        }
    }

    private func applyHiddenDefaultFilters() {
        let adult = effectiveAdultContentEnabled
        filters.sfw = true
        filters.sketchy = adult
        filters.nsfw = adult
    }

    private func apiKeyForSearch(filters: IOSSearchFilters) -> String? {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return (filters.sketchy || filters.nsfw) ? key : nil
    }

    func loadMore() {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-usePagedFixtureWallpapers") {
            loadMoreFixtureWallpapers()
            return
        }
#endif
        runSearch(reset: false)
    }

    func setOrientationFilters(landscape: Bool, portrait: Bool) {
        guard landscape || portrait else { return }
        guard filters.landscape != landscape || filters.portrait != portrait else { return }
        filters.landscape = landscape
        filters.portrait = portrait
        refreshCurrentSearch()
    }

    func setContentCategoryFilters(anime: Bool, photos: Bool) {
        guard anime || photos else { return }
        guard filters.anime != anime || filters.general != photos || filters.people != photos else { return }
        filters.anime = anime
        filters.general = photos
        filters.people = photos
        refreshCurrentSearch()
    }

    func setFeedSorting(_ sorting: IOSWallhavenSorting) {
        guard sorting == .dateAdded || sorting == .toplist || sorting == .random else { return }
        guard filters.sorting != sorting else { return }
        filters.sorting = sorting
        filters.order = .desc
        refreshCurrentSearch()
    }

    func openTag(_ tag: IOSWallpaperTag) {
        openTag(named: tag.name)
    }

    func openTag(named tagName: String) {
        let trimmed = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        filters.query = trimmed
        filters.sorting = .dateAdded
        filters.order = .desc
        search(reset: true, mode: .tag(trimmed))
    }

    func openUserUploads(username: String) {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        filters.query = "@\(trimmed)"
        filters.sorting = .dateAdded
        filters.order = .desc
        search(reset: true, mode: .userUploads(trimmed))
    }

    func openMyUploads() {
        openUserUploads(username: displayName)
    }

    func openFavorites() {
        loadTask?.cancel()
        galleryMode = .favorites
        errorMessage = nil
        isLoading = false
        isLoadingMore = false
        selectedWallpaper = nil
        selectedWallpaperIDs.removeAll()
        selectedWallpapersByID.removeAll()
    }

    func select(_ wallpaper: IOSWallpaper) {
        if selectedWallpaper?.id == wallpaper.id {
            selectedWallpaper = nil
            Task { @MainActor in
                await Task.yield()
                self.presentAndLoad(wallpaper)
            }
            return
        }

        presentAndLoad(wallpaper)
    }

    private func presentAndLoad(_ wallpaper: IOSWallpaper) {
        selectedWallpaper = wallpaper

        Task {
            if let detailed = await loadDetail(for: wallpaper) {
                await MainActor.run {
                    if self.selectedWallpaper?.id == wallpaper.id {
                        self.selectedWallpaper = detailed
                    }
                }
            }
        }
    }

    func loadDetail(for wallpaper: IOSWallpaper) async -> IOSWallpaper? {
        if wallpaper.isLocalUpload {
            return wallpaper
        }

        do {
            let detailed = try await api.wallpaper(id: wallpaper.id, apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
            networkUnavailable = false
            return detailed
        } catch {
            networkUnavailable = IOSIsNetworkUnavailable(error)
            errorMessage = IOSDisplayMessage(for: error, language: languageMode)
            return nil
        }
    }

    func isFavorite(_ wallpaper: IOSWallpaper) -> Bool {
        favoriteWallpapers[wallpaper.id] != nil
    }

    func toggleFavorite(_ wallpaper: IOSWallpaper) {
        if favoriteWallpapers[wallpaper.id] == nil {
            favoriteWallpapers[wallpaper.id] = wallpaper
        } else {
            favoriteWallpapers.removeValue(forKey: wallpaper.id)
        }
        saveCodable(favoriteWallpapers, forKey: Defaults.favorites)
    }

    func beginMultiSelection(with wallpaper: IOSWallpaper) {
        withAnimation(IOSMotion.selection) {
            isMultiSelecting = true
            selectedWallpaperIDs.insert(wallpaper.id)
            selectedWallpapersByID[wallpaper.id] = wallpaper
        }
    }

    func toggleWallpaperSelection(_ wallpaper: IOSWallpaper) {
        if selectedWallpaperIDs.contains(wallpaper.id) {
            selectedWallpaperIDs.remove(wallpaper.id)
            selectedWallpapersByID.removeValue(forKey: wallpaper.id)
        } else {
            selectedWallpaperIDs.insert(wallpaper.id)
            selectedWallpapersByID[wallpaper.id] = wallpaper
        }
    }

    func selectAllLoadedWallpapers() {
        isMultiSelecting = true
        selectedWallpaperIDs = Set(visibleWallpapers.map(\.id))
        selectedWallpapersByID = Dictionary(uniqueKeysWithValues: visibleWallpapers.map { ($0.id, $0) })
    }

    func clearWallpaperSelection() {
        selectedWallpaperIDs.removeAll()
        selectedWallpapersByID.removeAll()
    }

    func exitMultiSelection() {
        withAnimation(IOSMotion.selection) {
            isMultiSelecting = false
            selectedWallpaperIDs.removeAll()
            selectedWallpapersByID.removeAll()
        }
    }

    func download(_ wallpaper: IOSWallpaper) {
        downloads.download(wallpaper)
    }

    func downloadVisible() {
        downloads.downloadAll(visibleWallpapers)
    }

    func downloadSelected() {
        downloads.downloadAll(selectedLoadedWallpapers)
    }

    func saveUploadedImage(_ data: Data) {
        guard let image = UIImage(data: data) else { return }
        let id = "local-\(UUID().uuidString.lowercased())"
        let fileURL = Self.uploadsDirectory.appendingPathComponent("\(id).jpg")
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = image.scale
        let rendered = UIGraphicsImageRenderer(size: image.size, format: rendererFormat).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        guard let jpeg = rendered.jpegData(compressionQuality: 0.92) else { return }

        do {
            try FileManager.default.createDirectory(at: Self.uploadsDirectory, withIntermediateDirectories: true)
            try jpeg.write(to: fileURL, options: .atomic)
        } catch {
            return
        }

        let width = max(1, Int(image.size.width * image.scale))
        let height = max(1, Int(image.size.height * image.scale))
        let wallpaper = IOSWallpaper(
            id: id,
            url: fileURL,
            shortURL: nil,
            views: 0,
            favorites: 0,
            source: nil,
            purity: "sfw",
            category: "general",
            dimensionX: width,
            dimensionY: height,
            resolution: "\(width)x\(height)",
            ratio: "",
            fileSize: jpeg.count,
            fileType: "image/jpeg",
            createdAt: Self.localUploadDateFormatter.string(from: Date()),
            colors: [],
            path: fileURL,
            thumbs: IOSWallpaperThumbs(large: fileURL, original: fileURL, small: fileURL),
            uploader: nil,
            tags: []
        )

        localUploadedWallpapers.insert(wallpaper, at: 0)
        saveCodable(localUploadedWallpapers, forKey: Defaults.localUploads)
    }

    func updateHeaderCollapse(offset: CGFloat) {
        let shouldCollapse = isHeaderCollapsed ? offset < -34 : offset < -82
        setHeaderCollapsed(shouldCollapse)
    }

    func setHeaderCollapsed(_ collapsed: Bool) {
        setHeaderCollapseProgress(collapsed ? 1 : 0, animated: true)
    }

    func setHeaderCollapseProgress(_ progress: CGFloat, animated: Bool = false) {
        let nextProgress = min(max(progress, 0), 1)
        let shouldCollapse = nextProgress > 0.92
        guard abs(nextProgress - headerCollapseProgress) > 0.001 || shouldCollapse != isHeaderCollapsed else { return }

        if animated {
            withAnimation(IOSMotion.header) {
                headerCollapseProgress = nextProgress
                isHeaderCollapsed = shouldCollapse
            }
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            headerCollapseProgress = nextProgress
            isHeaderCollapsed = shouldCollapse
        }
    }

    func markHomeGalleryScrolling() {
        if !isHomeGalleryScrolling {
            isHomeGalleryScrolling = true
        }
    }

    func clearHomeGalleryScrolling() {
        isHomeGalleryScrolling = false
    }

    func rememberHomeScrollOffset(_ offset: CGFloat) {
        guard offset.isFinite else { return }
        homeScrollOffsetY = max(0, offset)
    }

    func isSubscribed(username: String) -> Bool {
        subscribedUsers.contains { $0.id == username.lowercased() }
    }

    func toggleSubscription(_ user: IOSSubscribedUser) {
        if let index = subscribedUsers.firstIndex(where: { $0.id == user.id }) {
            subscribedUsers.remove(at: index)
        } else {
            subscribedUsers.insert(user, at: 0)
        }
        saveCodable(subscribedUsers, forKey: Defaults.subscribedUsers)
    }

    func isFollowingTag(_ tagName: String) -> Bool {
        followedTags.contains { $0.id == tagName.lowercased() }
    }

    func toggleFollowedTag(_ tagName: String) {
        let trimmed = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let index = followedTags.firstIndex(where: { $0.id == trimmed.lowercased() }) {
            followedTags.remove(at: index)
        } else {
            followedTags.insert(IOSFollowedTag(name: trimmed), at: 0)
        }
        saveCodable(followedTags, forKey: Defaults.followedTags)
    }

    func saveAvatarImage(_ data: Data) {
        guard let image = UIImage(data: data) else { return }
        let side = min(image.size.width, image.size.height)
        let origin = CGPoint(
            x: (image.size.width - side) / 2,
            y: (image.size.height - side) / 2
        )
        let cropRect = CGRect(origin: origin, size: CGSize(width: side, height: side))
        let croppedImage = image.cgImage.flatMap { cgImage -> UIImage? in
            guard let cropped = cgImage.cropping(to: cropRect.applying(CGAffineTransform(scaleX: image.scale, y: image.scale))) else {
                return nil
            }
            return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
        } ?? image

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512))
        let rendered = renderer.image { _ in
            croppedImage.draw(in: CGRect(x: 0, y: 0, width: 512, height: 512))
        }

        guard let jpeg = rendered.jpegData(compressionQuality: 0.86) else { return }
        try? FileManager.default.createDirectory(at: Self.avatarFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? jpeg.write(to: Self.avatarFileURL, options: .atomic)
        avatarImageData = jpeg
        avatarURLString = ""
    }

    func removeAvatarImage() {
        try? FileManager.default.removeItem(at: Self.avatarFileURL)
        avatarImageData = nil
    }

    func clearCaches() {
        IOSClearImageCache()
    }

    private func fetch(
        page: Int,
        reset: Bool,
        showRefreshFeedback: Bool = false,
        operation: @escaping () async throws -> IOSWallhavenPage
    ) {
        let requestID = UUID()
        activeLoadID = requestID

        if reset {
            loadTask?.cancel()
            isLoading = true
            isLoadingMore = false
            if wallpapers.isEmpty {
                networkUnavailable = false
            }
            selectedWallpaperIDs.removeAll()
            selectedWallpapersByID.removeAll()
            selectedWallpaper = nil
            if showRefreshFeedback {
                beginHomeRefreshFeedback()
            }
        } else {
            isLoadingMore = true
        }

        errorMessage = nil

        loadTask = Task {
            do {
                let pageResult = try await operation()
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.activeLoadID == requestID else { return }
                    self.isLoading = false
                    self.isLoadingMore = false
                    self.networkUnavailable = false
                    self.meta = pageResult.meta

                    if reset {
                        withAnimation(IOSMotion.contentUpdate) {
                            self.wallpapers = Self.uniqueWallpapers(pageResult.data)
                        }
#if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("-forceMultiSelection"),
                           let first = self.wallpapers.first {
                            self.beginMultiSelection(with: first)
                        }
#endif
                        if pageResult.data.isEmpty {
                            self.errorMessage = self.filters.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? self.t("wallhaven_empty_help")
                                : self.t("empty_keyword_result")
                        }
                    } else {
                        let existing = Set(self.wallpapers.map(\.id))
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            self.wallpapers.append(contentsOf: pageResult.data.filter { !existing.contains($0.id) })
                        }
                    }
                    if showRefreshFeedback {
                        self.finishHomeRefreshFeedback(.success(pageResult.data.count))
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard self.activeLoadID == requestID else { return }
                    self.isLoading = false
                    self.isLoadingMore = false
                    if showRefreshFeedback {
                        self.homeRefreshFeedback = nil
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.activeLoadID == requestID else { return }
                    self.isLoading = false
                    self.isLoadingMore = false
                    if reset, self.wallpapers.isEmpty {
                        self.meta = nil
                    }
                    self.networkUnavailable = IOSIsNetworkUnavailable(error)
                    self.errorMessage = IOSDisplayMessage(for: error, language: self.languageMode)
                    if showRefreshFeedback {
                        self.finishHomeRefreshFeedback(.failed)
                    }
                }
            }
        }
    }

    private func beginHomeRefreshFeedback() {
        refreshFeedbackTask?.cancel()
        withAnimation(IOSMotion.quick) {
            homeRefreshFeedback = .refreshing
        }
    }

    private func finishHomeRefreshFeedback(_ feedback: IOSHomeRefreshFeedback) {
        refreshFeedbackTask?.cancel()
        withAnimation(IOSMotion.quick) {
            homeRefreshFeedback = feedback
        }

        switch feedback {
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .failed:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .refreshing:
            return
        }

        refreshFeedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(IOSMotion.quick) {
                self?.homeRefreshFeedback = nil
            }
        }
    }

    private static func uniqueWallpapers(_ wallpapers: [IOSWallpaper]) -> [IOSWallpaper] {
        var seen = Set<String>()
        return wallpapers.filter { wallpaper in
            seen.insert(wallpaper.id).inserted
        }
    }

#if DEBUG
    private func loadFixtureWallpapers() {
        guard wallpapers.isEmpty else { return }
        didInitialLoad = true
        isLoading = false
        isLoadingMore = false
        networkUnavailable = false
        errorMessage = nil
        galleryMode = .discover

        do {
            let page = try JSONDecoder().decode(IOSWallhavenPage.self, from: Data(Self.fixtureWallpapersJSON.utf8))
            if ProcessInfo.processInfo.arguments.contains("-usePagedFixtureWallpapers") {
                wallpapers = Array(page.data.prefix(12))
                fixtureQueuedWallpapers = Array(page.data.dropFirst(12).prefix(12))
                meta = IOSSearchMeta(currentPage: 1, lastPage: 2, perPage: 12, total: 24)
            } else {
                wallpapers = page.data
                meta = page.meta
            }
            if ProcessInfo.processInfo.arguments.contains("-forceMultiSelection"), let first = wallpapers.first {
                beginMultiSelection(with: first)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMoreFixtureWallpapers() {
        guard !fixtureQueuedWallpapers.isEmpty else { return }
        let nextBatch = fixtureQueuedWallpapers
        fixtureQueuedWallpapers.removeAll()
        isLoadingMore = true

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard let self else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.wallpapers.append(contentsOf: nextBatch)
                self.meta = IOSSearchMeta(currentPage: 2, lastPage: 2, perPage: 12, total: 24)
                self.isLoadingMore = false
            }
        }
    }

    private static var fixtureWallpapersJSON: String {
        let sizes = [
            (1600, 900), (1200, 1800), (1400, 1000), (900, 1400),
            (1800, 1050), (1000, 1500), (1500, 1000), (1100, 1650),
            (1700, 960), (960, 1400), (1440, 1080), (1000, 1300)
        ]

        let items = (0..<48).map { index -> String in
            let size = sizes[index % sizes.count]
            let id = "fixture-\(index)"
            let url = "https://example.com/\(id).jpg"
            return """
            {"id":"\(id)","url":"\(url)","short_url":"\(url)","views":0,"favorites":0,"source":null,"purity":"sfw","category":"general","dimension_x":\(size.0),"dimension_y":\(size.1),"resolution":"\(size.0)x\(size.1)","ratio":"","file_size":0,"file_type":"image/jpeg","created_at":"2026-07-06","colors":[],"path":"\(url)","thumbs":{"large":"\(url)","original":"\(url)","small":"\(url)"}}
            """
        }
        .joined(separator: ",")

        return """
        {"data":[\(items)],"meta":{"current_page":1,"last_page":2,"per_page":24,"total":48}}
        """
    }
#endif

    private func saveCodable<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func loadCodable<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static var avatarFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Profile", isDirectory: true)
            .appendingPathComponent("avatar.jpg")
    }

    private static var uploadsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Uploads", isDirectory: true)
    }

    private static let localUploadDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private enum Defaults {
    static let apiKey = "apiKey"
    static let favorites = "favorites"
    static let localUploads = "localUploads"
    static let displayName = "displayName"
    static let avatarURLString = "avatarURLString"
    static let themeMode = "themeMode"
    static let languageMode = "languageMode"
    static let subscribedUsers = "subscribedUsers"
    static let followedTags = "followedTags"
    static let includeAdultContent = "includeAdultContent"
}
