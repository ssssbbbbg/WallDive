import Foundation
import SwiftUI

enum WallhavenSorting: String, CaseIterable, Identifiable {
    case relevance
    case random
    case dateAdded = "date_added"
    case views
    case favorites
    case toplist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relevance: "相关"
        case .random: "随机"
        case .dateAdded: "最新"
        case .views: "浏览"
        case .favorites: "收藏"
        case .toplist: "榜单"
        }
    }
}

enum WallhavenOrder: String, CaseIterable, Identifiable {
    case desc
    case asc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desc: "降序"
        case .asc: "升序"
        }
    }
}

enum TopRange: String, CaseIterable, Identifiable {
    case oneDay = "1d"
    case threeDays = "3d"
    case oneWeek = "1w"
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1y"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneDay: "1 天"
        case .threeDays: "3 天"
        case .oneWeek: "1 周"
        case .oneMonth: "1 月"
        case .threeMonths: "3 月"
        case .sixMonths: "6 月"
        case .oneYear: "1 年"
        }
    }
}

enum ResolutionChoice: String, CaseIterable, Identifiable {
    case any = ""
    case fullHD = "1920x1080"
    case quadHD = "2560x1440"
    case ultraHD = "3840x2160"
    case fiveK = "5120x2880"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: "不限"
        case .fullHD: "1080p+"
        case .quadHD: "2K+"
        case .ultraHD: "4K+"
        case .fiveK: "5K+"
        }
    }
}

enum AspectRatioChoice: String, CaseIterable, Identifiable {
    case any = ""
    case wide = "16x9"
    case ten = "16x10"
    case ultrawide = "21x9"
    case classic = "4x3"
    case square = "1x1"
    case portrait = "9x16"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: "不限"
        case .wide: "16:9"
        case .ten: "16:10"
        case .ultrawide: "21:9"
        case .classic: "4:3"
        case .square: "1:1"
        case .portrait: "竖屏"
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "自动"
        case .light: "白天"
        case .dark: "深夜"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct SearchFilters: Equatable {
    var query = ""
    var general = true
    var anime = true
    var people = true
    var sfw = true
    var sketchy = false
    var nsfw = false
    var sorting: WallhavenSorting = .dateAdded
    var order: WallhavenOrder = .desc
    var topRange: TopRange = .oneMonth
    var minimumResolution: ResolutionChoice = .any
    var aspectRatio: AspectRatioChoice = .any
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

    var hasEnabledPurity: Bool {
        sfw || sketchy || nsfw
    }

    var ratiosParameter: String? {
        if aspectRatio != .any {
            return aspectRatio.rawValue
        }
        if landscape && !portrait {
            return "landscape"
        }
        if portrait && !landscape {
            return "portrait"
        }
        return nil
    }

    func allowsOrientation(of wallpaper: Wallpaper) -> Bool {
        if landscape && portrait { return true }
        if landscape { return wallpaper.dimensionX >= wallpaper.dimensionY }
        if portrait { return wallpaper.dimensionY > wallpaper.dimensionX }
        return false
    }
}

struct WallhavenPage: Decodable {
    let data: [Wallpaper]
    let meta: SearchMeta

    init(data: [Wallpaper], meta: SearchMeta) {
        self.data = data
        self.meta = meta
    }

    enum CodingKeys: String, CodingKey {
        case data
        case meta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lossyItems = try container.decode([LossyDecodable<Wallpaper>].self, forKey: .data)
        data = lossyItems.compactMap(\.value)
        meta = try container.decode(SearchMeta.self, forKey: .meta)
    }
}

struct SearchMeta: Codable, Equatable {
    let currentPage: Int
    let lastPage: Int
    let perPage: Int
    let total: Int
    let seed: String?

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
        perPage = container.decodeLossyInt(forKey: .perPage, default: 24)
        total = container.decodeLossyInt(forKey: .total, default: 0)
        seed = try? container.decodeIfPresent(String.self, forKey: .seed)
    }

    init(currentPage: Int, lastPage: Int, perPage: Int, total: Int, seed: String? = nil) {
        self.currentPage = currentPage
        self.lastPage = lastPage
        self.perPage = perPage
        self.total = total
        self.seed = seed
    }
}

struct Wallpaper: Codable, Identifiable, Hashable {
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
    let thumbs: WallpaperThumbs
    let uploader: WallhavenUploader?
    let tags: [WallpaperTag]

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
        thumbs = try container.decode(WallpaperThumbs.self, forKey: .thumbs)
        uploader = try? container.decodeIfPresent(WallhavenUploader.self, forKey: .uploader)
        tags = (try? container.decodeIfPresent([WallpaperTag].self, forKey: .tags)) ?? []
    }

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
        fileSize: Int = 0,
        fileType: String = "image/jpeg",
        createdAt: String = "",
        colors: [String] = [],
        path: URL,
        thumbs: WallpaperThumbs,
        uploader: WallhavenUploader? = nil,
        tags: [WallpaperTag] = []
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

    var fileExtension: String {
        if let ext = path.pathExtension.nilIfEmpty {
            ext
        } else if fileType.contains("png") {
            "png"
        } else {
            "jpg"
        }
    }

    var displayCategory: String {
        switch category {
        case "general": "常规"
        case "anime": "动漫"
        case "people": "人物"
        default: category
        }
    }

    var displayPurity: String {
        switch purity {
        case "sfw": "安全"
        case "sketchy": "微敏感"
        case "nsfw": "成人"
        default: purity
        }
    }

    var previewAspectRatio: CGFloat {
        if dimensionX > 0, dimensionY > 0 {
            return CGFloat(dimensionX) / CGFloat(dimensionY)
        }

        let parts = resolution.split(separator: "x")
        if parts.count == 2,
           let width = Double(parts[0]),
           let height = Double(parts[1]),
           width > 0,
           height > 0 {
            return CGFloat(width / height)
        }

        return 16 / 9
    }

    var gridPreviewURL: URL {
        isLocalUpload ? path : thumbs.original
    }

    var detailPreviewURL: URL {
        path
    }

    var isLocalUpload: Bool {
        id.hasPrefix("local-") || path.isFileURL
    }

    var byteSizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }
}

struct WallpaperThumbs: Codable, Hashable {
    let large: URL
    let original: URL
    let small: URL

    enum CodingKeys: String, CodingKey {
        case large
        case original
        case small
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        large = try container.decodeURL(forKey: .large)
        original = try container.decodeURL(forKey: .original)
        small = try container.decodeURL(forKey: .small)
    }

    init(large: URL, original: URL, small: URL) {
        self.large = large
        self.original = original
        self.small = small
    }
}

struct WallpaperDetailResponse: Decodable {
    let data: Wallpaper
}

struct WallhavenSettingsResponse: Decodable {
    let data: WallhavenAccountSettings
}

struct WallhavenAccountSettings: Decodable, Equatable {
    let username: String?
    let displayName: String?
    let avatar: WallhavenAvatar?

    enum CodingKeys: String, CodingKey {
        case username
        case name
        case displayName = "display_name"
        case avatar
        case avatarURL = "avatar_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = container.decodeOptionalString(forKey: .username)
        displayName = container.decodeOptionalString(forKey: .displayName)
            ?? container.decodeOptionalString(forKey: .name)
            ?? username

        if let decodedAvatar = try? container.decodeIfPresent(WallhavenAvatar.self, forKey: .avatar) {
            avatar = decodedAvatar
        } else if let avatarURL = container.decodeOptionalURL(forKey: .avatarURL) {
            avatar = WallhavenAvatar(url: avatarURL)
        } else {
            avatar = nil
        }
    }
}

struct WallhavenUploader: Codable, Hashable {
    let username: String
    let group: String
    let avatar: WallhavenAvatar

    var profileURL: URL {
        URL(string: "https://wallhaven.cc/user/\(username)")!
    }

    var bestAvatarURL: URL {
        avatar.size200 ?? avatar.size128 ?? avatar.size32 ?? avatar.size20
    }
}

struct WallhavenAvatar: Codable, Hashable {
    let size200: URL?
    let size128: URL?
    let size32: URL?
    let size20: URL

    enum CodingKeys: String, CodingKey {
        case size200 = "200px"
        case size128 = "128px"
        case size32 = "32px"
        case size20 = "20px"
    }

    var bestURL: URL {
        size200 ?? size128 ?? size32 ?? size20
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size200 = container.decodeOptionalURL(forKey: .size200)
        size128 = container.decodeOptionalURL(forKey: .size128)
        size32 = container.decodeOptionalURL(forKey: .size32)
        size20 = try container.decodeURL(forKey: .size20)
    }

    init(url: URL) {
        size200 = url
        size128 = url
        size32 = url
        size20 = url
    }
}

struct WallpaperTag: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let alias: String?
    let categoryID: Int?
    let category: String?
    let purity: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case alias
        case categoryID = "category_id"
        case category
        case purity
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyInt(forKey: .id, default: 0)
        name = try container.decodeLossyString(forKey: .name)
        alias = container.decodeOptionalString(forKey: .alias)
        categoryID = container.decodeLossyIntIfPresent(forKey: .categoryID)
        category = container.decodeOptionalString(forKey: .category)
        purity = container.decodeOptionalString(forKey: .purity)
        createdAt = container.decodeOptionalString(forKey: .createdAt)
    }
}

struct CollectionPage: Decodable {
    let data: [Wallpaper]
    let meta: SearchMeta
}

struct CollectionsResponse: Decodable {
    let data: [WallhavenCollection]
}

struct WallhavenCollection: Decodable, Identifiable, Hashable {
    let id: Int
    let label: String
    let views: Int?
    let isPublic: Bool?
    let count: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case views
        case isPublic = "public"
        case count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        views = try container.decodeIfPresent(Int.self, forKey: .views)
        count = try container.decodeIfPresent(Int.self, forKey: .count)

        if let value = try? container.decodeIfPresent(Bool.self, forKey: .isPublic) {
            isPublic = value
        } else if let value = try? container.decodeIfPresent(Int.self, forKey: .isPublic) {
            isPublic = value == 1
        } else {
            isPublic = nil
        }
    }
}

enum GalleryMode: Equatable {
    case search
    case collection(WallhavenCollection)
    case tag(String)
    case userUploads(String)
    case localFavorites
}

struct WallhavenProfileComment: Codable, Identifiable, Hashable {
    let id: String
    let author: String
    let avatarURL: URL?
    let postedAt: String
    let message: String
}

struct WallhavenUserProfile: Codable, Equatable {
    let username: String
    let avatarURL: URL?
    let joined: String
    let uploadCount: Int
    let favoriteCount: Int
    let subscriberCount: Int
    let comments: [WallhavenProfileComment]
    let fetchedAt: Date

    func joinedYearText(language: AppLanguage, referenceDate: Date = Date()) -> String {
        let currentYear = Calendar.current.component(.year, from: referenceDate)
        let normalized = joined.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let range = normalized.range(of: #"\b(?:19|20)\d{2}\b"#, options: .regularExpression),
           let year = Int(normalized[range]) {
            return String(format: AppL10n.text("joined_year_format", language: language), "\(year)")
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
        return String(format: AppL10n.text("joined_year_format", language: language), "\(resolvedYear)")
    }
}

struct UserProfilePage: Identifiable, Equatable {
    let username: String
    let displayName: String
    let avatarURL: URL?
    let group: String?
    let isCurrentUser: Bool

    var id: String { "\(isCurrentUser ? "me" : "user")-\(username)" }

    init(username: String, displayName: String? = nil, avatarURL: URL? = nil, group: String? = nil, isCurrentUser: Bool = false) {
        self.username = username
        self.displayName = displayName?.nilIfEmpty ?? username
        self.avatarURL = avatarURL
        self.group = group
        self.isCurrentUser = isCurrentUser
    }

    init(uploader: WallhavenUploader) {
        self.init(
            username: uploader.username,
            displayName: uploader.username,
            avatarURL: uploader.bestAvatarURL,
            group: uploader.group,
            isCurrentUser: false
        )
    }
}

struct AppUserProfile: Codable, Equatable {
    var displayName: String
    var avatarURLString: String

    var avatarURL: URL? {
        URL.wallhavenSafeURL(from: avatarURLString)
    }

    func page(username: String) -> UserProfilePage {
        UserProfilePage(
            username: username.nilIfEmpty ?? displayName.nilIfEmpty ?? "me",
            displayName: displayName.nilIfEmpty ?? username.nilIfEmpty ?? "个人资料",
            avatarURL: avatarURL,
            group: "本机资料",
            isCurrentUser: true
        )
    }
}

struct SubscribedUser: Codable, Identifiable, Equatable {
    var username: String
    var displayName: String
    var avatarURLString: String
    var group: String
    var lastSeenWallpaperID: String?
    var lastCheckedAt: Date?

    var id: String { username.lowercased() }

    var avatarURL: URL? {
        URL.wallhavenSafeURL(from: avatarURLString)
    }

    var page: UserProfilePage {
        UserProfilePage(username: username, displayName: displayName, avatarURL: avatarURL, group: group)
    }
}

struct FollowedTag: Codable, Identifiable, Hashable {
    var name: String

    var id: String {
        name.lowercased()
    }
}

struct WebSubscribedUser: Codable, Hashable, Identifiable {
    var username: String
    var displayName: String
    var count: Int?

    var id: String { username.lowercased() }
}

struct SubscriptionMessage: Identifiable, Equatable {
    let user: SubscribedUser
    let latestWallpaper: Wallpaper?
    let recentWallpapers: [Wallpaper]
    let newCount: Int
    let checkedAt: Date

    var id: String { user.id }

    var title: String {
        user.displayName
    }

    var subtitle: String {
        if let latestWallpaper {
            return "最新上传 · \(latestWallpaper.resolution)"
        }
        return "还没有读取到上传内容"
    }
}

struct GallerySnapshot: Equatable {
    var filters: SearchFilters
    var mode: GalleryMode
}

enum AuthState: Equatable {
    case signedOut
    case validating
    case signedIn
    case failed(String)
}

enum DownloadStatus: Equatable {
    case queued
    case running
    case finished(URL)
    case failed(String)
}

enum HomeRefreshFeedback: Equatable {
    case refreshing
    case success(Int)
    case failed
}

struct DownloadItem: Identifiable, Equatable {
    let id = UUID()
    let wallpaper: Wallpaper
    let wallpaperID: String
    var title: String
    let sourceURL: URL
    var status: DownloadStatus
    var createdAt = Date()
}

struct DownloadFeedback: Identifiable, Equatable {
    enum State: Equatable {
        case success(String)
        case failed(String)
        case already(String)
        case running(String)

        var message: String {
            switch self {
            case .success(let message), .failed(let message), .already(let message), .running(let message):
                message
            }
        }

        var systemImage: String {
            switch self {
            case .success, .already: "checkmark.circle.fill"
            case .failed: "exclamationmark.triangle.fill"
            case .running: "arrow.down.circle.fill"
            }
        }
    }

    let id = UUID()
    let state: State
}

enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }
}

struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

extension KeyedDecodingContainer {
    func decodeLossyString(forKey key: Key) throws -> String {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return "\(value)"
        }
        if let value = try? decode(Double.self, forKey: key) {
            return String(value)
        }
        throw DecodingError.typeMismatch(
            String.self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "Expected string-compatible value."
            )
        )
    }

    func decodeOptionalString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    func decodeLossyInt(forKey key: Key, default defaultValue: Int) -> Int {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value) ?? defaultValue
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        return defaultValue
    }

    func decodeLossyIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    func decodeURL(forKey key: Key) throws -> URL {
        let rawValue = try decodeLossyString(forKey: key)
        if let url = URL.wallhavenSafeURL(from: rawValue) {
            return url
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "Invalid URL: \(rawValue)"
        )
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
