import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var filters = SearchFilters()
    @Published private(set) var wallpapers: [Wallpaper] = []
    @Published private(set) var meta: SearchMeta?
    @Published var selectedWallpaper: Wallpaper?
    @Published var networkUnavailable = false
    @Published private(set) var homeRefreshFeedback: HomeRefreshFeedback?
    @Published private(set) var mode: GalleryMode = .search
    @Published private(set) var collections: [WallhavenCollection] = []
    @Published private(set) var authState: AuthState = .signedOut
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var isHomeHeaderCollapsed = false
    @Published var isHomeGalleryScrolling = false
    @Published var isMultiSelecting = false
    @Published var isLoadingWallpaperDetail = false
    @Published var isLoadingSubscriptions = false
    @Published var isLoadingServerFavorites = false
    @Published var accountSyncMessage: String?
    @Published var subscriptionSyncMessage: String?
    @Published var profileLoadingUsernames: Set<String> = []
    @Published var userProfileLoadingUsernames: Set<String> = []
    @Published var activeUserProfilePage: UserProfilePage?
    @Published var myProfile = AppUserProfile(displayName: "", avatarURLString: "") {
        didSet {
            saveCodable(myProfile, forKey: Defaults.myProfile)
        }
    }
    @Published private(set) var favoriteWallpapers: [String: Wallpaper] = [:]
    @Published private(set) var serverFavoriteWallpapers: [String: Wallpaper] = [:]
    @Published private(set) var selectedWallpaperIDs: Set<String> = []
    @Published private(set) var selectedWallpapersByID: [String: Wallpaper] = [:]
    @Published private(set) var subscriptions: [SubscribedUser] = []
    @Published private(set) var followedTags: [FollowedTag] = []
    @Published private(set) var localUploadedWallpapers: [Wallpaper] = []
    @Published private(set) var subscriptionMessages: [SubscriptionMessage] = []
    @Published private(set) var profileUploads: [String: [Wallpaper]] = [:]
    @Published private(set) var profileUploadMeta: [String: SearchMeta] = [:]
    @Published private(set) var userProfiles: [String: WallhavenUserProfile] = [:]
    @Published private(set) var profileErrors: [String: String] = [:]
    @Published private var backStack: [GallerySnapshot] = []
    @Published private var forwardStack: [GallerySnapshot] = []
    @Published var downloadFolderPath: String
    @Published var appAppearance: AppAppearance = .system {
        didSet {
            UserDefaults.standard.set(appAppearance.rawValue, forKey: Defaults.appAppearance)
        }
    }
    @Published var languageMode: AppLanguage = .zhHans {
        didSet {
            UserDefaults.standard.set(languageMode.rawValue, forKey: Defaults.languageMode)
            downloads.language = languageMode
        }
    }
    @Published var includeAdultContent = false {
        didSet {
            UserDefaults.standard.set(includeAdultContent, forKey: Defaults.includeAdultContent)
        }
    }
    @Published var isDetailPanelVisible = true {
        didSet {
            UserDefaults.standard.set(isDetailPanelVisible, forKey: Defaults.detailPanelVisible)
        }
    }
    @Published private(set) var apiKey: String
    @Published private(set) var username: String

    let downloads = DownloadManager()

    private let api = WallhavenAPI()
    private var loadTask: Task<Void, Never>?
    private var activeLoadID: UUID?
    private var detailTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var refreshFeedbackTask: Task<Void, Never>?
    private var profileUploadTasks: [String: Task<Void, Never>] = [:]
    private var suppressNextFilterChange = false
    private var wallpaperDetails: [String: Wallpaper] = [:]
    private var didInitialLoad = false

    init() {
        apiKey = KeychainStore.readAPIKey()
        username = UserDefaults.standard.string(forKey: Defaults.username) ?? ""
        myProfile = Self.loadCodable(AppUserProfile.self, forKey: Defaults.myProfile) ?? AppUserProfile(displayName: "", avatarURLString: "")
        favoriteWallpapers = Self.loadCodable([String: Wallpaper].self, forKey: Defaults.favoriteWallpapers) ?? [:]
        subscriptions = Self.loadCodable([SubscribedUser].self, forKey: Defaults.subscriptions) ?? []
        followedTags = Self.loadCodable([FollowedTag].self, forKey: Defaults.followedTags) ?? []
        localUploadedWallpapers = Self.loadCodable([Wallpaper].self, forKey: Defaults.localUploads) ?? []
        appAppearance = AppAppearance(rawValue: UserDefaults.standard.string(forKey: Defaults.appAppearance) ?? "") ?? .system
        languageMode = AppLanguage(rawValue: UserDefaults.standard.string(forKey: Defaults.languageMode) ?? "") ?? .zhHans
        includeAdultContent = UserDefaults.standard.bool(forKey: Defaults.includeAdultContent)
        isDetailPanelVisible = UserDefaults.standard.object(forKey: Defaults.detailPanelVisible) as? Bool ?? true

        if let storedFolder = UserDefaults.standard.string(forKey: Defaults.downloadFolder), !storedFolder.isEmpty {
            downloadFolderPath = storedFolder
        } else {
            let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            downloadFolderPath = downloadsURL?.appendingPathComponent("Wallhaven").path ?? NSHomeDirectory()
        }

        authState = apiKey.isEmpty ? .signedOut : .validating
        downloads.language = languageMode
    }

    var downloadFolderURL: URL {
        URL(fileURLWithPath: downloadFolderPath)
    }

    var title: String {
        switch mode {
        case .search:
            filters.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "发现壁纸" : "搜索结果"
        case .collection(let collection):
            collection.label
        case .tag(let tag):
            "#\(tag)"
        case .userUploads(let username):
            "\(username) 的上传"
        case .localFavorites:
            "收藏"
        }
    }

    var subtitle: String {
        if mode == .localFavorites {
            "\(favoriteList.count) 张收藏"
        } else if case .userUploads(let username) = mode {
            if let meta {
                "\(username) · \(wallpapers.count) / \(meta.total) 张"
            } else {
                "\(username) 的最新上传"
            }
        } else if case .tag(let tag) = mode {
            if let meta {
                "\(tag) · \(wallpapers.count) / \(meta.total) 张"
            } else {
                "标签搜索"
            }
        } else {
            if let meta {
                "\(wallpapers.count) / \(meta.total) 张"
            } else {
                "准备好探索 Wallhaven 原图"
            }
        }
    }

    var canLoadMore: Bool {
        if mode == .localFavorites {
            return false
        }
        guard let meta else { return false }
        return meta.currentPage < meta.lastPage
    }

    var canGoBack: Bool {
        !backStack.isEmpty
    }

    var canGoForward: Bool {
        !forwardStack.isEmpty
    }

    var favoriteList: [Wallpaper] {
        let source = serverFavoriteWallpapers.isEmpty ? favoriteWallpapers : serverFavoriteWallpapers
        return source.values.sorted { $0.id < $1.id }
    }

    var selectedLoadedWallpapers: [Wallpaper] {
        selectedWallpaperIDs.compactMap { selectedWallpapersByID[$0] }
    }

    var myProfilePage: UserProfilePage? {
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = myProfile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUsername.isEmpty || !displayName.isEmpty else {
            return nil
        }
        return myProfile.page(username: cleanUsername)
    }

    var canUseNSFW: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var effectiveAdultContentEnabled: Bool {
        includeAdultContent && canUseNSFW
    }

    var visibleWallpapers: [Wallpaper] {
        if mode == .localFavorites { return favoriteList }
        return wallpapers
    }

    var cacheSizeText: String {
        formattedImageCacheSize()
    }

    func t(_ key: String) -> String {
        AppL10n.text(key, language: languageMode)
    }

    func initialLoad() {
        guard !didInitialLoad else { return }
        didInitialLoad = true

        if !apiKey.isEmpty {
            validateCredentials()
        }
        runSearch(reset: true)
    }

    func queueSearch() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.runSearch(reset: true)
            }
        }
    }

    func handleFiltersChanged() {
        if suppressNextFilterChange {
            suppressNextFilterChange = false
            return
        }

        queueSearch()
    }

    func runSearch(reset: Bool, modeOverride: GalleryMode? = nil) {
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

        let page = reset ? 1 : (meta?.currentPage ?? 0) + 1
        mode = modeOverride ?? .search
        let requestFilters = filters
        let requestAPIKey = apiKeyForSearch(filters: requestFilters)
        let requestSeed = reset ? nil : meta?.seed
        fetch(page: page, reset: reset) { [api] in
            try await api.searchWithFallback(
                filters: requestFilters,
                page: page,
                apiKey: requestAPIKey,
                seed: requestSeed
            )
        }
    }

    func refreshCurrentSearch(showFeedback: Bool = true) {
        if mode == .localFavorites {
            if showFeedback { finishRefreshFeedback(.success(favoriteList.count)) }
            return
        }
        if showFeedback { beginRefreshFeedback() }
        runSearch(reset: true, modeOverride: mode)
    }

    func setOrientationFilters(landscape: Bool, portrait: Bool) {
        guard landscape || portrait else { return }
        guard filters.landscape != landscape || filters.portrait != portrait else { return }
        filters.landscape = landscape
        filters.portrait = portrait
        refreshCurrentSearch(showFeedback: false)
    }

    func setFeedSorting(_ sorting: WallhavenSorting) {
        guard sorting == .dateAdded || sorting == .toplist || sorting == .random else { return }
        guard filters.sorting != sorting else { return }
        filters.sorting = sorting
        filters.order = .desc
        refreshCurrentSearch(showFeedback: false)
    }

    private func applyHiddenDefaultFilters() {
        let adult = effectiveAdultContentEnabled
        filters.general = true
        filters.anime = true
        filters.people = true
        filters.sfw = true
        filters.sketchy = adult
        filters.nsfw = adult
    }

    private func apiKeyForSearch(filters: SearchFilters) -> String? {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return (filters.sketchy || filters.nsfw) ? key : nil
    }

    func loadCollection(_ collection: WallhavenCollection, reset: Bool = true) {
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUsername.isEmpty else {
            errorMessage = "打开收藏夹需要在设置里填写 Wallhaven 用户名。"
            return
        }

        let page = reset ? 1 : (meta?.currentPage ?? 0) + 1
        mode = .collection(collection)
        fetch(page: page, reset: reset) { [api, apiKey] in
            try await api.collectionWallpapers(
                username: cleanUsername,
                collectionID: collection.id,
                page: page,
                apiKey: apiKey
            )
        }
    }

    func loadMoreIfNeeded(current wallpaper: Wallpaper) {
        guard wallpaper.id == wallpapers.last?.id else { return }
        loadMore()
    }

    func loadMore() {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }

        switch mode {
        case .search, .tag, .userUploads:
            runSearch(reset: false, modeOverride: mode)
        case .collection(let collection):
            loadCollection(collection, reset: false)
        case .localFavorites:
            break
        }
    }

    func download(_ wallpaper: Wallpaper) {
        downloads.download(wallpaper, to: downloadFolderURL)
    }

    func downloadVisible() {
        downloads.downloadAll(visibleWallpapers, to: downloadFolderURL)
    }

    func downloadSelected() {
        downloads.downloadAll(selectedLoadedWallpapers, to: downloadFolderURL)
    }

    func toggleMultiSelectionMode() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            isMultiSelecting.toggle()
            if !isMultiSelecting {
                selectedWallpaperIDs.removeAll()
                selectedWallpapersByID.removeAll()
            }
        }
    }

    func toggleWallpaperSelection(_ wallpaper: Wallpaper) {
        if selectedWallpaperIDs.contains(wallpaper.id) {
            selectedWallpaperIDs.remove(wallpaper.id)
            selectedWallpapersByID.removeValue(forKey: wallpaper.id)
        } else {
            selectedWallpaperIDs.insert(wallpaper.id)
            selectedWallpapersByID[wallpaper.id] = wallpaper
        }
    }

    func beginMultiSelection(with wallpaper: Wallpaper) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            isMultiSelecting = true
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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            isMultiSelecting = false
            selectedWallpaperIDs.removeAll()
            selectedWallpapersByID.removeAll()
        }
    }

    func isFavorite(_ wallpaper: Wallpaper) -> Bool {
        favoriteWallpapers[wallpaper.id] != nil
    }

    func toggleFavorite(_ wallpaper: Wallpaper) {
        if favoriteWallpapers[wallpaper.id] == nil {
            favoriteWallpapers[wallpaper.id] = wallpaperDetails[wallpaper.id] ?? wallpaper
        } else {
            favoriteWallpapers.removeValue(forKey: wallpaper.id)
        }
        saveCodable(favoriteWallpapers, forKey: Defaults.favoriteWallpapers)

        if mode == .localFavorites {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                wallpapers = favoriteList
                selectedWallpaper = wallpapers.first
                meta = SearchMeta(currentPage: 1, lastPage: 1, perPage: favoriteList.count, total: favoriteList.count)
            }
        }
    }

    func select(_ wallpaper: Wallpaper) {
        let resolvedWallpaper = wallpaperDetails[wallpaper.id] ?? wallpaper
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            selectedWallpaper = resolvedWallpaper
        }
        if !resolvedWallpaper.isLocalUpload {
            loadWallpaperDetail(for: resolvedWallpaper)
        }
    }

    func resolvedWallpaper(for wallpaper: Wallpaper) async -> Wallpaper {
        if wallpaper.isLocalUpload { return wallpaper }
        if let cached = wallpaperDetails[wallpaper.id] { return cached }
        do {
            let detailed = try await api.wallpaper(id: wallpaper.id, apiKey: apiKey.nilIfEmpty)
            wallpaperDetails[detailed.id] = detailed
            return detailed
        } catch {
            networkUnavailable = isNetworkUnavailable(error)
            errorMessage = displayMessage(for: error, language: languageMode)
            return wallpaper
        }
    }

    func showProfile(for uploader: WallhavenUploader) {
        activeUserProfilePage = UserProfilePage(uploader: uploader)
    }

    func showMyProfile() {
        guard let page = myProfilePage else {
            errorMessage = "请先在设置里填写你的 Wallhaven 用户名或显示名称。"
            return
        }
        activeUserProfilePage = page
    }

    func openTag(_ tag: WallpaperTag) {
        var nextFilters = filters
        nextFilters.query = tag.name
        nextFilters.sorting = .dateAdded
        navigateToSearch(filters: nextFilters, mode: .tag(tag.name), pushHistory: true)
    }

    func openUserUploads(_ username: String, pushHistory: Bool = true) {
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUsername.isEmpty else { return }

        var nextFilters = filters
        nextFilters.query = "@\(cleanUsername)"
        nextFilters.sorting = .dateAdded
        nextFilters.order = .desc
        navigateToSearch(filters: nextFilters, mode: .userUploads(cleanUsername), pushHistory: pushHistory)
    }

    func showLocalFavorites(pushHistory: Bool = true) {
        if pushHistory {
            pushCurrentSnapshot()
        }
        forwardStack.removeAll()
        loadRealFavorites()
        mode = .localFavorites
        meta = SearchMeta(currentPage: 1, lastPage: 1, perPage: favoriteList.count, total: favoriteList.count)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            wallpapers = favoriteList
            selectedWallpaper = wallpapers.first
        }
    }

    func goBack() {
        guard let snapshot = backStack.popLast() else { return }
        forwardStack.append(currentSnapshot)
        restore(snapshot)
    }

    func goForward() {
        guard let snapshot = forwardStack.popLast() else { return }
        backStack.append(currentSnapshot)
        restore(snapshot)
    }

    func updateMyProfile(displayName: String, avatarURLString: String) {
        myProfile = AppUserProfile(
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            avatarURLString: avatarURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func chooseLocalAvatarImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "选择头像"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                self.updateMyProfile(displayName: self.myProfile.displayName, avatarURLString: url.absoluteString)
                self.accountSyncMessage = "已替换为本地头像。"
            }
        }
    }

    func syncAccountProfileFromWallhaven() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            accountSyncMessage = "请先填写 API Key。"
            return
        }

        accountSyncMessage = "正在同步 Wallhaven 账号资料..."

        Task {
            do {
                let settings = try await api.accountSettings(apiKey: key)
                await MainActor.run {
                    self.applyAccountSettings(settings, overwriteProfile: true)
                    self.accountSyncMessage = "已同步 Wallhaven 用户名和头像。"
                }
            } catch {
                await MainActor.run {
                    self.accountSyncMessage = error.localizedDescription
                }
            }
        }
    }

    func isSubscribed(username: String) -> Bool {
        subscriptions.contains { $0.id == username.lowercased() }
    }

    func toggleSubscription(page: UserProfilePage) {
        let key = page.username.lowercased()
        if let index = subscriptions.firstIndex(where: { $0.id == key }) {
            subscriptions.remove(at: index)
        } else {
            subscriptions.append(
                SubscribedUser(
                    username: page.username,
                    displayName: page.displayName,
                    avatarURLString: page.avatarURL?.absoluteString ?? "",
                    group: page.group ?? "",
                    lastSeenWallpaperID: nil,
                    lastCheckedAt: nil
                )
            )
        }
        saveCodable(subscriptions, forKey: Defaults.subscriptions)
        refreshSubscriptions()
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
            followedTags.insert(FollowedTag(name: trimmed), at: 0)
        }
        saveCodable(followedTags, forKey: Defaults.followedTags)
    }

    func loadUserProfile(username: String, force: Bool = false) {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = trimmed.lowercased()
        guard !trimmed.isEmpty, !userProfileLoadingUsernames.contains(key) else { return }
        if !force, userProfiles[key] != nil { return }

        userProfileLoadingUsernames.insert(key)
        profileErrors.removeValue(forKey: key)
        Task {
            do {
                let profile = try await api.userProfile(username: trimmed)
                await MainActor.run {
                    self.userProfiles[key] = profile
                    self.userProfileLoadingUsernames.remove(key)
                }
            } catch {
                await MainActor.run {
                    self.userProfileLoadingUsernames.remove(key)
                    self.profileErrors[key] = displayMessage(for: error, language: self.languageMode)
                }
            }
        }
    }

    func profile(for username: String) -> WallhavenUserProfile? {
        userProfiles[username.lowercased()]
    }

    func chooseLocalUploadImages() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        panel.prompt = t("import_local")
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                self?.importLocalUploadImages(from: panel.urls)
            }
        }
    }

    func openWallhavenUpload() {
        guard let url = URL(string: "https://wallhaven.cc/upload") else { return }
        NSWorkspace.shared.open(url)
    }

    func clearCaches() {
        clearImageCache()
        URLCache.shared.removeAllCachedResponses()
    }

    func importWebSubscriptions(_ importedUsers: [WebSubscribedUser]) {
        let uniqueUsers = importedUsers.reduce(into: [String: WebSubscribedUser]()) { result, user in
            let cleanUsername = user.username.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanUsername.isEmpty else { return }
            let key = cleanUsername.lowercased()
            if result[key] == nil {
                result[key] = WebSubscribedUser(
                    username: cleanUsername,
                    displayName: user.displayName.nilIfEmpty ?? cleanUsername,
                    count: user.count
                )
            }
        }

        guard !uniqueUsers.isEmpty else {
            subscriptionSyncMessage = "当前网页没有识别到 USER UPLOADS 订阅用户。请确认你已在内置网页登录并打开订阅页。"
            return
        }

        var importedCount = 0
        var updatedCount = 0
        var nextSubscriptions = subscriptions

        for user in uniqueUsers.values.sorted(by: { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }) {
            if let index = nextSubscriptions.firstIndex(where: { $0.id == user.id }) {
                nextSubscriptions[index].displayName = user.displayName.nilIfEmpty ?? user.username
                if nextSubscriptions[index].group.isEmpty {
                    nextSubscriptions[index].group = "网页订阅"
                }
                updatedCount += 1
            } else {
                nextSubscriptions.append(
                    SubscribedUser(
                        username: user.username,
                        displayName: user.displayName.nilIfEmpty ?? user.username,
                        avatarURLString: "",
                        group: "网页订阅",
                        lastSeenWallpaperID: nil,
                        lastCheckedAt: nil
                    )
                )
                importedCount += 1
            }
        }

        subscriptions = nextSubscriptions.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        saveCodable(subscriptions, forKey: Defaults.subscriptions)
        subscriptionSyncMessage = "已同步 \(uniqueUsers.count) 个网页订阅用户，新增 \(importedCount) 个，更新 \(updatedCount) 个。"
        refreshSubscriptions()
    }

    func refreshSubscriptions() {
        guard !subscriptions.isEmpty else {
            subscriptionMessages = []
            isLoadingSubscriptions = false
            return
        }

        isLoadingSubscriptions = true
        subscriptionMessages = []

        Task {
            var messages: [SubscriptionMessage] = []
            var updatedSubscriptions = subscriptions

            for subscription in subscriptions {
                do {
                    let page = try await api.userUploads(username: subscription.username, page: 1, apiKey: apiKey)
                    let latest = page.data.first
                    let recentWallpapers = Array(page.data.prefix(5))
                    let newCount: Int
                    if let latestID = latest?.id, let lastSeen = subscription.lastSeenWallpaperID {
                        newCount = latestID == lastSeen ? 0 : max(1, page.data.prefix { $0.id != lastSeen }.count)
                    } else {
                        newCount = latest == nil ? 0 : 1
                    }

                    messages.append(
                        SubscriptionMessage(
                            user: subscription,
                            latestWallpaper: latest,
                            recentWallpapers: recentWallpapers,
                            newCount: newCount,
                            checkedAt: Date()
                        )
                    )

                    if let index = updatedSubscriptions.firstIndex(where: { $0.id == subscription.id }) {
                        updatedSubscriptions[index].lastCheckedAt = Date()
                    }
                } catch {
                    messages.append(
                        SubscriptionMessage(
                            user: subscription,
                            latestWallpaper: nil,
                            recentWallpapers: [],
                            newCount: 0,
                            checkedAt: Date()
                        )
                    )
                }
            }

            await MainActor.run {
                self.subscriptions = updatedSubscriptions
                self.subscriptionMessages = messages.sorted { $0.newCount > $1.newCount }
                self.isLoadingSubscriptions = false
                self.saveCodable(self.subscriptions, forKey: Defaults.subscriptions)
            }
        }
    }

    func openSubscriptionMessage(_ message: SubscriptionMessage) {
        if let latestID = message.latestWallpaper?.id,
           let index = subscriptions.firstIndex(where: { $0.id == message.user.id }) {
            subscriptions[index].lastSeenWallpaperID = latestID
            subscriptions[index].lastCheckedAt = Date()
            saveCodable(subscriptions, forKey: Defaults.subscriptions)
        }

        openUserUploads(message.user.username)
    }

    func loadProfileUploads(username: String, reset: Bool) {
        let key = username.lowercased()
        if !reset, let meta = profileUploadMeta[key], meta.currentPage >= meta.lastPage {
            return
        }
        let page = reset ? 1 : (profileUploadMeta[key]?.currentPage ?? 0) + 1

        if reset {
            profileUploadTasks[key]?.cancel()
            profileLoadingUsernames.insert(key)
        } else if profileLoadingUsernames.contains(key) {
            return
        } else {
            profileLoadingUsernames.insert(key)
        }

        profileUploadTasks[key] = Task {
            do {
                let result = try await api.userUploads(username: username, page: page, apiKey: apiKey)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    let existing = reset ? [] : (self.profileUploads[key] ?? [])
                    let existingIDs = Set(existing.map(\.id))
                    self.profileUploads[key] = existing + result.data.filter { !existingIDs.contains($0.id) }
                    self.profileUploadMeta[key] = result.meta
                    self.profileErrors.removeValue(forKey: key)
                    _ = self.profileLoadingUsernames.remove(key)
                }
            } catch is CancellationError {
                await MainActor.run {
                    _ = self.profileLoadingUsernames.remove(key)
                }
            } catch {
                await MainActor.run {
                    _ = self.profileLoadingUsernames.remove(key)
                    self.profileErrors[key] = displayMessage(for: error, language: self.languageMode)
                }
            }
        }
    }

    func saveCredentials(apiKey newKey: String, username newUsername: String) {
        do {
            try KeychainStore.saveAPIKey(newKey)
            apiKey = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
            username = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(username, forKey: Defaults.username)
            validateCredentials()
            queueSearch()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        saveCredentials(apiKey: "", username: "")
        includeAdultContent = false
        authState = .signedOut
        collections = []
        serverFavoriteWallpapers = [:]
    }

    func validateCredentials() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            authState = .signedOut
            collections = []
            return
        }

        authState = .validating

        Task {
            do {
                try await api.validate(apiKey: key)
                let accountSettings = try? await api.accountSettings(apiKey: key)
                let fetchedCollections = (try? await api.collections(apiKey: key)) ?? []
                await MainActor.run {
                    if let accountSettings {
                        self.applyAccountSettings(accountSettings, overwriteProfile: false)
                    }
                    self.authState = .signedIn
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        self.collections = fetchedCollections
                    }
                    self.loadRealFavorites()
                    self.refreshSubscriptions()
                }
            } catch {
                await MainActor.run {
                    self.authState = .failed(error.localizedDescription)
                    self.collections = []
                }
            }
        }
    }

    func loadRealFavorites() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !cleanUsername.isEmpty else {
            return
        }

        isLoadingServerFavorites = true

        Task {
            do {
                let fetchedCollections = collections.isEmpty ? try await api.collections(apiKey: key) : collections
                var allWallpapers: [String: Wallpaper] = [:]

                for collection in fetchedCollections {
                    var page = 1
                    var lastPage = 1

                    repeat {
                        let collectionPage = try await api.collectionWallpapers(
                            username: cleanUsername,
                            collectionID: collection.id,
                            page: page,
                            apiKey: key
                        )

                        collectionPage.data.forEach { allWallpapers[$0.id] = $0 }
                        lastPage = collectionPage.meta.lastPage
                        page += 1
                    } while page <= lastPage
                }

                await MainActor.run {
                    self.collections = fetchedCollections
                    self.serverFavoriteWallpapers = allWallpapers
                    self.isLoadingServerFavorites = false

                    if self.mode == .localFavorites {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                            self.wallpapers = self.favoriteList
                            self.selectedWallpaper = self.wallpapers.first
                            self.meta = SearchMeta(currentPage: 1, lastPage: 1, perPage: self.favoriteList.count, total: self.favoriteList.count)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingServerFavorites = false
                    self.errorMessage = "收藏读取失败：\(error.localizedDescription)"
                }
            }
        }
    }

    func chooseDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.directoryURL = URL(fileURLWithPath: downloadFolderPath)

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.downloadFolderPath = url.path
                UserDefaults.standard.set(url.path, forKey: Defaults.downloadFolder)
            }
        }
    }

    func revealDownloadFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([downloadFolderURL])
    }

    func openInBrowser(_ wallpaper: Wallpaper) {
        NSWorkspace.shared.open(wallpaper.url)
    }

    func copyWallpaperLink(_ wallpaper: Wallpaper) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(wallpaper.url.absoluteString, forType: .string)
    }

    private func fetch(page: Int, reset: Bool, operation: @escaping () async throws -> WallhavenPage) {
        let requestID = UUID()
        activeLoadID = requestID

        if reset {
            loadTask?.cancel()
            isLoading = true
            isLoadingMore = false
            selectedWallpaperIDs.removeAll()
            selectedWallpapersByID.removeAll()
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
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            self.wallpapers = Self.uniqueWallpapers(pageResult.data)
                        }
                        if pageResult.data.isEmpty {
                            self.errorMessage = self.filters.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? self.t("wallhaven_empty_help")
                                : self.t("empty_keyword_result")
                        }
                    } else {
                        let existing = Set(self.wallpapers.map(\.id))
                        let newWallpapers = pageResult.data.filter { !existing.contains($0.id) }
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            self.wallpapers.append(contentsOf: newWallpapers)
                        }
                    }
                    if self.homeRefreshFeedback == .refreshing {
                        self.finishRefreshFeedback(.success(pageResult.data.count))
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard self.activeLoadID == requestID else { return }
                    self.isLoading = false
                    self.isLoadingMore = false
                }
            } catch {
                await MainActor.run {
                    guard self.activeLoadID == requestID else { return }
                    self.isLoading = false
                    self.isLoadingMore = false
                    self.networkUnavailable = isNetworkUnavailable(error)
                    self.errorMessage = displayMessage(for: error, language: self.languageMode)
                    if self.homeRefreshFeedback == .refreshing {
                        self.finishRefreshFeedback(.failed)
                    }
                }
            }
        }
    }

    private func beginRefreshFeedback() {
        refreshFeedbackTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            homeRefreshFeedback = .refreshing
        }
    }

    private func finishRefreshFeedback(_ feedback: HomeRefreshFeedback) {
        refreshFeedbackTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            homeRefreshFeedback = feedback
        }
        guard feedback != .refreshing else { return }
        refreshFeedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.7))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                self?.homeRefreshFeedback = nil
            }
        }
    }

    private static func uniqueWallpapers(_ wallpapers: [Wallpaper]) -> [Wallpaper] {
        var seen = Set<String>()
        return wallpapers.filter { seen.insert($0.id).inserted }
    }

    private func loadWallpaperDetail(for wallpaper: Wallpaper) {
        if let cached = wallpaperDetails[wallpaper.id] {
            applyDetailedWallpaper(cached)
            isLoadingWallpaperDetail = false
            return
        }

        detailTask?.cancel()
        isLoadingWallpaperDetail = true

        detailTask = Task {
            do {
                let detailed = try await api.wallpaper(id: wallpaper.id, apiKey: apiKey)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.wallpaperDetails[detailed.id] = detailed
                    self.applyDetailedWallpaper(detailed)
                    self.isLoadingWallpaperDetail = false
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isLoadingWallpaperDetail = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingWallpaperDetail = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func applyDetailedWallpaper(_ detailed: Wallpaper) {
        if let index = wallpapers.firstIndex(where: { $0.id == detailed.id }) {
            wallpapers[index] = detailed
        }

        if selectedWallpaper?.id == detailed.id {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                selectedWallpaper = detailed
            }
        }
    }

    private func applyAccountSettings(_ settings: WallhavenAccountSettings, overwriteProfile: Bool) {
        if let settingsUsername = settings.username?.trimmingCharacters(in: .whitespacesAndNewlines), !settingsUsername.isEmpty {
            username = settingsUsername
            UserDefaults.standard.set(settingsUsername, forKey: Defaults.username)
        }

        let currentDisplayName = myProfile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentAvatar = myProfile.avatarURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextDisplayName = settings.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextAvatar = settings.avatar?.bestURL.absoluteString

        if overwriteProfile || currentDisplayName.isEmpty || currentAvatar.isEmpty {
            myProfile = AppUserProfile(
                displayName: overwriteProfile ? (nextDisplayName ?? currentDisplayName) : (currentDisplayName.isEmpty ? (nextDisplayName ?? "") : currentDisplayName),
                avatarURLString: overwriteProfile ? (nextAvatar ?? currentAvatar) : (currentAvatar.isEmpty ? (nextAvatar ?? "") : currentAvatar)
            )
        }
    }

    private var currentSnapshot: GallerySnapshot {
        GallerySnapshot(filters: filters, mode: mode)
    }

    private func navigateToSearch(filters nextFilters: SearchFilters, mode nextMode: GalleryMode, pushHistory: Bool) {
        if pushHistory {
            pushCurrentSnapshot()
            forwardStack.removeAll()
        }

        suppressNextFilterChange = true
        filters = nextFilters
        runSearch(reset: true, modeOverride: nextMode)
    }

    private func pushCurrentSnapshot() {
        let snapshot = currentSnapshot
        guard backStack.last != snapshot else { return }
        backStack.append(snapshot)
    }

    private func restore(_ snapshot: GallerySnapshot) {
        suppressNextFilterChange = true
        filters = snapshot.filters

        switch snapshot.mode {
        case .search, .tag, .userUploads:
            runSearch(reset: true, modeOverride: snapshot.mode)
        case .collection(let collection):
            loadCollection(collection, reset: true)
        case .localFavorites:
            showLocalFavorites(pushHistory: false)
        }
    }

    private func importLocalUploadImages(from urls: [URL]) {
        guard !urls.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: Self.localUploadsDirectory, withIntermediateDirectories: true)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        var imported: [Wallpaper] = []
        for sourceURL in urls {
            guard let data = try? Data(contentsOf: sourceURL),
                  let image = NSImage(data: data) else { continue }
            let representation = NSBitmapImageRep(data: data)
            let width = max(1, representation?.pixelsWide ?? Int(image.size.width))
            let height = max(1, representation?.pixelsHigh ?? Int(image.size.height))
            let id = "local-\(UUID().uuidString.lowercased())"
            let ext = sourceURL.pathExtension.nilIfEmpty ?? "jpg"
            let targetURL = Self.localUploadsDirectory.appendingPathComponent("\(id).\(ext)")

            do {
                try data.write(to: targetURL, options: .atomic)
            } catch {
                continue
            }

            let wallpaper = Wallpaper(
                id: id,
                url: targetURL,
                dimensionX: width,
                dimensionY: height,
                fileSize: data.count,
                fileType: ext.lowercased() == "png" ? "image/png" : "image/jpeg",
                createdAt: ISO8601DateFormatter().string(from: Date()),
                path: targetURL,
                thumbs: WallpaperThumbs(large: targetURL, original: targetURL, small: targetURL)
            )
            imported.append(wallpaper)
        }

        guard !imported.isEmpty else {
            errorMessage = languageMode == .en ? "No readable images were selected." : "没有读取到可导入的图片。"
            return
        }
        localUploadedWallpapers.insert(contentsOf: imported, at: 0)
        saveCodable(localUploadedWallpapers, forKey: Defaults.localUploads)
    }

    private func saveCodable<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func loadCodable<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static var localUploadsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WallDive", isDirectory: true)
            .appendingPathComponent("Uploads", isDirectory: true)
    }
}

private enum Defaults {
    static let username = "wallhaven.username"
    static let downloadFolder = "download.folder"
    static let appAppearance = "app.appearance"
    static let detailPanelVisible = "detail.panel.visible"
    static let myProfile = "my.profile"
    static let favoriteWallpapers = "favorite.wallpapers"
    static let subscriptions = "subscriptions"
    static let followedTags = "followed.tags"
    static let localUploads = "local.uploads"
    static let languageMode = "app.language"
    static let includeAdultContent = "include.adult.content"
}
