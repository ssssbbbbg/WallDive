import Foundation
import SwiftUI

enum IOSMotion {
    static let tabSwitch = Animation.smooth(duration: 0.32, extraBounce: 0)
    static let tabIndicator = Animation.smooth(duration: 0.24, extraBounce: 0)
    static let quick = Animation.smooth(duration: 0.18, extraBounce: 0)
    static let selection = Animation.smooth(duration: 0.2, extraBounce: 0)
    static let refresh = Animation.smooth(duration: 0.22, extraBounce: 0)
    static let contentUpdate = Animation.smooth(duration: 0.16, extraBounce: 0)
    static let scale = Animation.smooth(duration: 0.28, extraBounce: 0)
    static let filterPanel = Animation.smooth(duration: 0.38, extraBounce: 0)
    static let header = Animation.interactiveSpring(response: 0.22, dampingFraction: 0.96, blendDuration: 0.06)
}

enum IOSDesign {
    static let cardCornerRadius: CGFloat = 24
    static let imagePreviewCornerRadius: CGFloat = 12
}

enum IOSHomeRefreshFeedback: Equatable {
    case refreshing
    case success(Int)
    case failed
}

func IOSNetworkUnavailableMessage(for error: Error) -> String? {
    guard let urlError = error as? URLError else {
        return nil
    }

    switch urlError.code {
    case .notConnectedToInternet,
         .networkConnectionLost,
         .cannotFindHost,
         .cannotConnectToHost,
         .dnsLookupFailed,
         .secureConnectionFailed,
         .timedOut,
         .dataNotAllowed,
         .internationalRoamingOff,
         .cannotLoadFromNetwork:
        return "无网络或代理不可用，请检查网络/代理后再刷新。"
    default:
        return nil
    }
}

func IOSIsNetworkUnavailable(_ error: Error) -> Bool {
    IOSNetworkUnavailableMessage(for: error) != nil
}

func IOSDisplayMessage(for error: Error) -> String {
    IOSNetworkUnavailableMessage(for: error) ?? error.localizedDescription
}

func IOSNetworkUnavailableMessage(for error: Error, language: IOSAppLanguage) -> String? {
    IOSNetworkUnavailableMessage(for: error).map { _ in
        IOSL10n.t("network_unavailable_message", language)
    }
}

func IOSDisplayMessage(for error: Error, language: IOSAppLanguage) -> String {
    IOSNetworkUnavailableMessage(for: error, language: language) ?? error.localizedDescription
}

enum IOSWallhavenSorting: String, CaseIterable, Identifiable {
    case dateAdded = "date_added"
    case toplist
    case relevance
    case favorites
    case views
    case random

    var id: String { rawValue }

    var title: String {
        title(language: .zhHans)
    }

    func title(language: IOSAppLanguage) -> String {
        switch self {
        case .dateAdded: IOSL10n.t("latest", language)
        case .toplist: IOSL10n.t("popular", language)
        case .relevance: IOSL10n.t("relevance", language)
        case .favorites: IOSL10n.t("favorites", language)
        case .views: IOSL10n.t("views", language)
        case .random: IOSL10n.t("random", language)
        }
    }
}

enum IOSWallhavenOrder: String, CaseIterable, Identifiable {
    case desc
    case asc

    var id: String { rawValue }

    var title: String {
        title(language: .zhHans)
    }

    func title(language: IOSAppLanguage) -> String {
        switch self {
        case .desc: IOSL10n.t("descending", language)
        case .asc: IOSL10n.t("ascending", language)
        }
    }
}

enum IOSThemeMode: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        title(language: .zhHans)
    }

    func title(language: IOSAppLanguage) -> String {
        switch self {
        case .system: IOSL10n.t("automatic", language)
        case .light: IOSL10n.t("day", language)
        case .dark: IOSL10n.t("night", language)
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum IOSAppLanguage: String, CaseIterable, Identifiable, Codable {
    case zhHans
    case en

    var id: String { rawValue }

    var title: String {
        switch self {
        case .zhHans: "中文"
        case .en: "English"
        }
    }
}

enum IOSL10n {
    static func t(_ key: String, _ language: IOSAppLanguage) -> String {
        switch language {
        case .zhHans:
            return zhHans[key] ?? key
        case .en:
            return en[key] ?? zhHans[key] ?? key
        }
    }

    private static let zhHans: [String: String] = [
        "settings": "设置",
        "profile": "个人资料",
        "name": "名称",
        "appearance": "外观",
        "display_mode": "显示模式",
        "language": "语言",
        "wallhaven_account": "Wallhaven 账号",
        "wallhaven_connected": "Wallhaven 已连接",
        "wallhaven_not_connected": "Wallhaven 未登录",
        "wallhaven_login": "登录 Wallhaven",
        "manage_wallhaven_session": "管理登录",
        "wallhaven_login_privacy": "登录会打开系统 Safari，可正常完成 Cloudflare 安全验证。WallDive 不读取密码或 Cookie；发布和留言使用 Safari，用户与标签订阅仅保存在本机。",
        "wallhaven_secure_session": "Wallhaven 安全会话",
        "wallhaven_secure_session_detail": "使用系统 Safari",
        "wallhaven_api_connected": "Wallhaven 连接成功",
        "wallhaven_api_checking": "正在验证账号数据",
        "wallhaven_api_failed": "Wallhaven 连接失败",
        "wallhaven_api_required": "需要 Wallhaven API Key",
        "wallhaven_upload": "上传到 Wallhaven",
        "publish": "发布",
        "wallhaven_comment": "发表留言",
        "wallhaven_subscription": "Wallhaven 订阅",
        "api_key": "API Key",
        "restricted_content": "限制级内容",
        "restricted_description": "开启后会包含微敏感和限制级分级，需要 API Key，且取决于你的 Wallhaven 账号设置。关闭时首页使用公开安全流，加载更稳定。",
        "cache": "缓存",
        "clear_cache": "清除缓存",
        "cache_cleared": "缓存已清除",
        "software_version": "软件版本",
        "download_queue": "下载队列",
        "close": "关闭",
        "retry_failed": "重试失败",
        "clear": "清理",
        "no_download_tasks": "没有下载任务",
        "queued": "等待下载",
        "downloading_original": "正在下载原图",
        "saved_to_photos": "已保存到系统相册",
        "automatic": "自动",
        "day": "日间",
        "night": "夜间",
        "latest": "最新",
        "popular": "热门",
        "relevance": "相关",
        "favorites": "收藏",
        "views": "浏览",
        "random": "随机",
        "descending": "降序",
        "ascending": "升序",
        "download_selected": "下载 %@ 张",
        "select_images": "选择图片",
        "no_network": "无网络",
        "no_wallpapers": "没有壁纸",
        "try_another_keyword": "换个关键词试试",
        "reload": "重新加载",
        "your_subscriptions": "你的订阅",
        "subscription_empty": "关注用户或标签后，更新会出现在这里",
        "discover": "去发现",
        "subscribed_users": "订阅用户",
        "followed_tags": "关注标签",
        "continue_load_more": "继续下滑加载更多",
        "select_all": "全选",
        "clear_selection": "清空",
        "done": "完成",
        "downloaded": "已下载",
        "downloading": "下载中",
        "download_original": "下载原图",
        "tags": "标签",
        "preview": "预览",
        "orientation": "方向",
        "feed_mode": "浏览模式",
        "content_type": "内容类型",
        "photos": "照片",
        "landscape_wallpapers": "横屏壁纸",
        "portrait_wallpapers": "竖屏壁纸",
        "subscribe": "订阅",
        "subscribed": "已订阅",
        "menu": "菜单",
        "my_uploads": "我的上传",
        "subscriptions": "订阅",
        "online": "在线",
        "upload": "上传",
        "uploads": "上传",
        "no_favorites": "没有收藏",
        "no_subscriptions": "没有订阅",
        "no_tags": "没有标签",
        "input_tag": "输入 tag",
        "follow": "关注",
        "wallpaper_count": "%@ 张",
        "discover_wallpapers": "发现壁纸",
        "empty_tag_result": "这个标签暂时没有结果",
        "network_unavailable_message": "无网络或代理不可用，请检查网络/代理后再刷新。",
        "wallhaven_empty_help": "Wallhaven 没有返回图片，请确认手机网络能打开 wallhaven.cc。",
        "empty_keyword_result": "这个关键词暂时没有结果。",
        "at_least_one_category": "至少选择一个分类。",
        "at_least_one_purity": "至少选择一个分级。",
        "loading": "正在加载",
        "refreshing": "正在刷新",
        "refresh_complete": "已刷新 %@ 张",
        "refresh_failed": "刷新失败",
        "general": "常规",
        "anime": "动漫",
        "people": "人物",
        "safe": "安全",
        "sketchy": "微敏感",
        "restricted": "限制级",
        "sort": "排序",
        "order": "顺序",
        "home": "首页",
        "following": "关注",
        "me": "我",
        "no_uploads": "没有上传",
        "profile_home": "主页",
        "joined": "加入时间",
        "joined_year_format": "%@年",
        "subscribers": "订阅者",
        "profile_comments": "留言",
        "no_profile_comments": "暂无公开留言",
        "profile_live_data": "Wallhaven 公开资料",
        "profile_data_unavailable": "暂时无法读取 Wallhaven 主页资料",
        "saved_to_album": "已保存到相册",
        "photo_access_denied": "没有相册写入权限，请在系统设置中允许 WallDive 添加照片。",
        "photo_save_failed": "原图已下载，但保存到系统相册失败。",
        "original_download_http_failed": "原图下载失败（HTTP %@）。"
    ]

    private static let en: [String: String] = [
        "settings": "Settings",
        "profile": "Profile",
        "name": "Name",
        "appearance": "Appearance",
        "display_mode": "Display Mode",
        "language": "Language",
        "wallhaven_account": "Wallhaven Account",
        "wallhaven_connected": "Wallhaven Connected",
        "wallhaven_not_connected": "Not Signed In",
        "wallhaven_login": "Sign in to Wallhaven",
        "manage_wallhaven_session": "Manage Sign-in",
        "wallhaven_login_privacy": "Sign-in opens system Safari so Cloudflare verification can complete normally. WallDive never reads passwords or cookies. Publishing and comments use Safari; user and tag subscriptions stay on this device.",
        "wallhaven_secure_session": "Wallhaven Secure Session",
        "wallhaven_secure_session_detail": "Uses system Safari",
        "wallhaven_api_connected": "Wallhaven Connected",
        "wallhaven_api_checking": "Checking account data",
        "wallhaven_api_failed": "Wallhaven Connection Failed",
        "wallhaven_api_required": "Wallhaven API Key Required",
        "wallhaven_upload": "Upload to Wallhaven",
        "publish": "Publish",
        "wallhaven_comment": "Post Comment",
        "wallhaven_subscription": "Wallhaven Subscription",
        "api_key": "API Key",
        "restricted_content": "Restricted Content",
        "restricted_description": "Includes sketchy and restricted ratings when enabled. Requires an API Key and depends on your Wallhaven account settings. When disabled, Home uses the public safe feed for better stability.",
        "cache": "Cache",
        "clear_cache": "Clear Cache",
        "cache_cleared": "Cache cleared",
        "software_version": "Version",
        "download_queue": "Downloads",
        "close": "Close",
        "retry_failed": "Retry Failed",
        "clear": "Clear",
        "no_download_tasks": "No downloads",
        "queued": "Queued",
        "downloading_original": "Downloading original",
        "saved_to_photos": "Saved to Photos",
        "automatic": "Auto",
        "day": "Light",
        "night": "Dark",
        "latest": "Latest",
        "popular": "Popular",
        "relevance": "Relevance",
        "favorites": "Favorites",
        "views": "Views",
        "random": "Random",
        "descending": "Descending",
        "ascending": "Ascending",
        "download_selected": "Download %@",
        "select_images": "Select images",
        "no_network": "No Network",
        "no_wallpapers": "No Wallpapers",
        "try_another_keyword": "Try another keyword",
        "reload": "Reload",
        "your_subscriptions": "Your Subscriptions",
        "subscription_empty": "Follow users or tags to see updates here",
        "discover": "Discover",
        "subscribed_users": "Users",
        "followed_tags": "Tags",
        "continue_load_more": "Scroll for more",
        "select_all": "Select All",
        "clear_selection": "Clear",
        "done": "Done",
        "downloaded": "Downloaded",
        "downloading": "Downloading",
        "download_original": "Download Original",
        "tags": "Tags",
        "preview": "Preview",
        "orientation": "Orientation",
        "feed_mode": "Feed Mode",
        "content_type": "Content Type",
        "photos": "Photos",
        "landscape_wallpapers": "Landscape",
        "portrait_wallpapers": "Portrait",
        "subscribe": "Subscribe",
        "subscribed": "Subscribed",
        "menu": "Menu",
        "my_uploads": "My Uploads",
        "subscriptions": "Subscriptions",
        "online": "Online",
        "upload": "Upload",
        "uploads": "Uploads",
        "no_favorites": "No Favorites",
        "no_subscriptions": "No Subscriptions",
        "no_tags": "No Tags",
        "input_tag": "Enter tag",
        "follow": "Follow",
        "wallpaper_count": "%@",
        "discover_wallpapers": "Discover",
        "empty_tag_result": "No results for this tag yet",
        "network_unavailable_message": "No network or proxy is available. Check your network/proxy and refresh.",
        "wallhaven_empty_help": "Wallhaven returned no images. Check whether this phone can open wallhaven.cc.",
        "empty_keyword_result": "No results for this keyword yet.",
        "at_least_one_category": "Select at least one category.",
        "at_least_one_purity": "Select at least one rating.",
        "loading": "Loading",
        "refreshing": "Refreshing",
        "refresh_complete": "Refreshed %@",
        "refresh_failed": "Refresh Failed",
        "general": "General",
        "anime": "Anime",
        "people": "People",
        "safe": "Safe",
        "sketchy": "Sketchy",
        "restricted": "Restricted",
        "sort": "Sort",
        "order": "Order",
        "home": "Home",
        "following": "Following",
        "me": "Me",
        "no_uploads": "No Uploads",
        "profile_home": "Profile",
        "joined": "Joined",
        "joined_year_format": "%@",
        "subscribers": "Subscribers",
        "profile_comments": "Comments",
        "no_profile_comments": "No public comments",
        "profile_live_data": "Wallhaven public profile",
        "profile_data_unavailable": "Wallhaven profile data is temporarily unavailable",
        "saved_to_album": "Saved to Photos",
        "photo_access_denied": "Allow WallDive to add photos in Settings.",
        "photo_save_failed": "The original downloaded, but saving to Photos failed.",
        "original_download_http_failed": "Original download failed (HTTP %@)."
    ]
}

enum IOSGalleryMode: Equatable {
    case discover
    case favorites
    case userUploads(String)
    case tag(String)

    var title: String {
        switch self {
        case .discover: "发现壁纸"
        case .favorites: "收藏"
        case .userUploads(let username): "\(username) 的上传"
        case .tag(let tagName): "#\(tagName)"
        }
    }
}

struct IOSSubscribedUser: Codable, Identifiable, Hashable {
    var username: String
    var group: String?
    var avatarURL: URL?

    var id: String {
        username.lowercased()
    }

    init(username: String, group: String? = nil, avatarURL: URL? = nil) {
        self.username = username
        self.group = group
        self.avatarURL = avatarURL
    }

    init(uploader: IOSWallhavenUploader) {
        username = uploader.username
        group = uploader.group
        avatarURL = uploader.bestAvatarURL
    }
}

struct IOSWallhavenProfileComment: Codable, Identifiable, Hashable {
    let id: String
    let author: String
    let avatarURL: URL?
    let postedAt: String
    let message: String
}

struct IOSWallhavenUserProfile: Codable, Equatable {
    let username: String
    let avatarURL: URL?
    let joined: String
    let uploadCount: Int
    let favoriteCount: Int
    let subscriberCount: Int
    let comments: [IOSWallhavenProfileComment]
    let fetchedAt: Date

    func joinedYearText(language: IOSAppLanguage, referenceDate: Date = Date()) -> String {
        let currentYear = Calendar.current.component(.year, from: referenceDate)
        let normalized = joined.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let range = normalized.range(of: #"\b(?:19|20)\d{2}\b"#, options: .regularExpression),
           let year = Int(normalized[range]) {
            return String(format: IOSL10n.t("joined_year_format", language), "\(year)")
        }

        var resolvedYear: Int?
        if normalized.contains("a year ago") || normalized.contains("one year ago") {
            resolvedYear = currentYear - 1
        } else if let range = normalized.range(of: #"\d+\s+years?\s+ago"#, options: .regularExpression),
                  let years = Int(normalized[range].split(separator: " ").first ?? "") {
            resolvedYear = currentYear - years
        } else if ["month", "week", "day", "hour", "minute", "second", "today", "just now"].contains(where: normalized.contains) {
            resolvedYear = currentYear
        }

        guard let resolvedYear else { return joined }
        return String(format: IOSL10n.t("joined_year_format", language), "\(resolvedYear)")
    }
}

struct IOSFollowedTag: Codable, Identifiable, Hashable {
    var name: String

    var id: String {
        name.lowercased()
    }
}

struct IOSSearchFilters: Equatable {
    var query = ""
    var general = true
    var anime = true
    var people = true
    var sfw = true
    var sketchy = false
    var nsfw = false
    var sorting: IOSWallhavenSorting = .dateAdded
    var order: IOSWallhavenOrder = .desc
    var landscape = true
    var portrait = true

    var categoriesParameter: String {
        "\(general ? "1" : "0")\(anime ? "1" : "0")\(people ? "1" : "0")"
    }

    var purityParameter: String {
        "\(sfw ? "1" : "0")\(sketchy ? "1" : "0")\(nsfw ? "1" : "0")"
    }

    var hasEnabledCategory: Bool {
        general || anime || people
    }

    var photosEnabled: Bool {
        general || people
    }

    var hasCategoryFilter: Bool {
        !(general && anime && people)
    }

    var hasEnabledPurity: Bool {
        sfw || sketchy || nsfw
    }

    var ratiosParameter: String? {
        switch (landscape, portrait) {
        case (true, false): "landscape"
        case (false, true): "portrait"
        default: nil
        }
    }

    func allowsOrientation(of wallpaper: IOSWallpaper) -> Bool {
        switch (landscape, portrait) {
        case (true, true): true
        case (true, false): wallpaper.dimensionX > wallpaper.dimensionY
        case (false, true): wallpaper.dimensionY > wallpaper.dimensionX
        case (false, false): false
        }
    }
}

struct IOSWallhavenPage: Decodable {
    let data: [IOSWallpaper]
    let meta: IOSSearchMeta
}

struct IOSSearchMeta: Decodable, Equatable {
    let currentPage: Int
    let lastPage: Int
    let perPage: Int
    let total: Int
    let seed: String?

    init(currentPage: Int, lastPage: Int, perPage: Int, total: Int, seed: String? = nil) {
        self.currentPage = currentPage
        self.lastPage = lastPage
        self.perPage = perPage
        self.total = total
        self.seed = seed
    }

    enum CodingKeys: String, CodingKey {
        case currentPage = "current_page"
        case lastPage = "last_page"
        case perPage = "per_page"
        case total
        case seed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentPage = container.decodeLossyInt(forKey: .currentPage, default: 1)
        lastPage = container.decodeLossyInt(forKey: .lastPage, default: 1)
        perPage = container.decodeLossyInt(forKey: .perPage, default: 0)
        total = container.decodeLossyInt(forKey: .total, default: 0)
        seed = try? container.decodeIfPresent(String.self, forKey: .seed)
    }
}

struct IOSWallpaper: Codable, Identifiable, Hashable {
    let id: String
    let url: URL
    let shortURL: URL?
    let views: Int
    let favorites: Int
    let source: String?
    let purity: String
    let category: String
    let dimensionX: Int
    let dimensionY: Int
    let resolution: String
    let ratio: String
    let fileSize: Int
    let fileType: String
    let createdAt: String
    let colors: [String]
    let path: URL
    let thumbs: IOSWallpaperThumbs
    let uploader: IOSWallhavenUploader?
    let tags: [IOSWallpaperTag]

    init(
        id: String,
        url: URL,
        shortURL: URL? = nil,
        views: Int = 0,
        favorites: Int = 0,
        source: String? = nil,
        purity: String = "sfw",
        category: String = "general",
        dimensionX: Int,
        dimensionY: Int,
        resolution: String? = nil,
        ratio: String = "",
        fileSize: Int,
        fileType: String = "image/jpeg",
        createdAt: String,
        colors: [String] = [],
        path: URL,
        thumbs: IOSWallpaperThumbs,
        uploader: IOSWallhavenUploader? = nil,
        tags: [IOSWallpaperTag] = []
    ) {
        self.id = id
        self.url = url
        self.shortURL = shortURL
        self.views = views
        self.favorites = favorites
        self.source = source
        self.purity = purity
        self.category = category
        self.dimensionX = dimensionX
        self.dimensionY = dimensionY
        self.resolution = resolution ?? "\(dimensionX)x\(dimensionY)"
        self.ratio = ratio
        self.fileSize = fileSize
        self.fileType = fileType
        self.createdAt = createdAt
        self.colors = colors
        self.path = path
        self.thumbs = thumbs
        self.uploader = uploader
        self.tags = tags
    }

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case shortURL = "short_url"
        case views
        case favorites
        case source
        case purity
        case category
        case dimensionX = "dimension_x"
        case dimensionY = "dimension_y"
        case resolution
        case ratio
        case fileSize = "file_size"
        case fileType = "file_type"
        case createdAt = "created_at"
        case colors
        case path
        case thumbs
        case uploader
        case tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeLossyString(forKey: .id)
        url = try container.decodeURL(forKey: .url)
        shortURL = container.decodeOptionalURL(forKey: .shortURL)
        views = container.decodeLossyInt(forKey: .views, default: 0)
        favorites = container.decodeLossyInt(forKey: .favorites, default: 0)
        source = container.decodeOptionalString(forKey: .source)
        purity = container.decodeOptionalString(forKey: .purity) ?? "sfw"
        category = container.decodeOptionalString(forKey: .category) ?? "general"
        dimensionX = container.decodeLossyInt(forKey: .dimensionX, default: 0)
        dimensionY = container.decodeLossyInt(forKey: .dimensionY, default: 0)
        resolution = container.decodeOptionalString(forKey: .resolution) ?? "\(dimensionX)x\(dimensionY)"
        ratio = container.decodeOptionalString(forKey: .ratio) ?? ""
        fileSize = container.decodeLossyInt(forKey: .fileSize, default: 0)
        fileType = container.decodeOptionalString(forKey: .fileType) ?? "image/jpeg"
        createdAt = container.decodeOptionalString(forKey: .createdAt) ?? ""
        colors = (try? container.decode([String].self, forKey: .colors)) ?? []
        path = try container.decodeURL(forKey: .path)
        thumbs = try container.decode(IOSWallpaperThumbs.self, forKey: .thumbs)
        uploader = try? container.decodeIfPresent(IOSWallhavenUploader.self, forKey: .uploader)
        tags = (try? container.decodeIfPresent([IOSWallpaperTag].self, forKey: .tags)) ?? []
    }

    var previewAspectRatio: CGFloat {
        if dimensionX > 0, dimensionY > 0 {
            return CGFloat(dimensionX) / CGFloat(dimensionY)
        }
        return 16 / 9
    }

    var gridPreviewURL: URL {
        thumbs.original
    }

    var detailPreviewURL: URL {
        path
    }

    var isLocalUpload: Bool {
        path.isFileURL || id.hasPrefix("local-")
    }

    var fileExtension: String {
        if let ext = path.pathExtension.nilIfEmpty {
            return ext
        }
        return fileType.contains("png") ? "png" : "jpg"
    }

    var displayPurity: String {
        displayPurity(language: .zhHans)
    }

    func displayPurity(language: IOSAppLanguage) -> String {
        switch purity {
        case "sfw": IOSL10n.t("safe", language)
        case "sketchy": IOSL10n.t("sketchy", language)
        case "nsfw": IOSL10n.t("restricted", language)
        default: purity
        }
    }

    var displayCategory: String {
        displayCategory(language: .zhHans)
    }

    func displayCategory(language: IOSAppLanguage) -> String {
        switch category {
        case "general": IOSL10n.t("general", language)
        case "anime": IOSL10n.t("anime", language)
        case "people": IOSL10n.t("people", language)
        default: category
        }
    }
}

struct IOSWallpaperThumbs: Codable, Hashable {
    let large: URL
    let original: URL
    let small: URL

    enum CodingKeys: String, CodingKey {
        case large
        case original
        case small
    }

    init(large: URL, original: URL, small: URL) {
        self.large = large
        self.original = original
        self.small = small
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        large = try container.decodeURL(forKey: .large)
        original = try container.decodeURL(forKey: .original)
        small = try container.decodeURL(forKey: .small)
    }
}

struct IOSWallhavenUploader: Codable, Hashable {
    let username: String
    let group: String?
    let avatar: IOSWallhavenAvatar?

    enum CodingKeys: String, CodingKey {
        case username
        case group
        case avatar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = try container.decodeLossyString(forKey: .username)
        group = container.decodeOptionalString(forKey: .group)
        avatar = try? container.decodeIfPresent(IOSWallhavenAvatar.self, forKey: .avatar)
    }

    var bestAvatarURL: URL? {
        avatar?.size200 ?? avatar?.size128 ?? avatar?.size32 ?? avatar?.size20
    }
}

struct IOSWallhavenAvatar: Codable, Hashable {
    let size200: URL?
    let size128: URL?
    let size32: URL?
    let size20: URL?

    enum CodingKeys: String, CodingKey {
        case size200 = "200px"
        case size128 = "128px"
        case size32 = "32px"
        case size20 = "20px"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size200 = container.decodeOptionalURL(forKey: .size200)
        size128 = container.decodeOptionalURL(forKey: .size128)
        size32 = container.decodeOptionalURL(forKey: .size32)
        size20 = container.decodeOptionalURL(forKey: .size20)
    }
}

struct IOSWallpaperTag: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let alias: String?
    let categoryID: Int?
    let category: String?
    let purity: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case alias
        case categoryID = "category_id"
        case category
        case purity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyInt(forKey: .id, default: 0)
        name = try container.decodeLossyString(forKey: .name)
        alias = container.decodeOptionalString(forKey: .alias)
        categoryID = container.decodeLossyIntIfPresent(forKey: .categoryID)
        category = container.decodeOptionalString(forKey: .category)
        purity = container.decodeOptionalString(forKey: .purity)
    }
}

struct IOSDownloadItem: Identifiable, Equatable {
    let id = UUID()
    let wallpaper: IOSWallpaper
    let wallpaperID: String
    var title: String
    var status: IOSDownloadStatus
    var fileURL: URL?
}

enum IOSDownloadStatus: Equatable {
    case queued
    case running
    case finished
    case failed(String)
}

private extension KeyedDecodingContainer {
    func decodeLossyString(forKey key: Key) throws -> String {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return "\(value)"
        }
        if let value = try? decode(Double.self, forKey: key) {
            return "\(value)"
        }
        throw DecodingError.typeMismatch(
            String.self,
            DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Expected string-compatible value.")
        )
    }

    func decodeOptionalString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return "\(value)"
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return "\(value)"
        }
        return nil
    }

    func decodeLossyInt(forKey key: Key, default defaultValue: Int) -> Int {
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? decode(String.self, forKey: key), let intValue = Int(value) {
            return intValue
        }
        return defaultValue
    }

    func decodeLossyIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? decode(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    func decodeURL(forKey key: Key) throws -> URL {
        let rawValue = try decodeLossyString(forKey: key)
        if let url = URL.wallhavenSafeURL(from: rawValue) {
            return url
        }
        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Invalid URL.")
    }

    func decodeOptionalURL(forKey key: Key) -> URL? {
        guard let rawValue = decodeOptionalString(forKey: key) else {
            return nil
        }
        return URL.wallhavenSafeURL(from: rawValue)
    }
}

extension URL {
    static func wallhavenSafeURL(from rawValue: String) -> URL? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("//") {
            value = "https:" + value
        }
        return URL(string: value)
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
