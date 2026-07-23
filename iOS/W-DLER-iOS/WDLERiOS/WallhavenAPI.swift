import Foundation

actor IOSWallhavenAPI {
    private let baseURL = URL(string: "https://wallhaven.cc/api/v1")!
    private let decoder = JSONDecoder()

    private struct SearchCandidate {
        var filters: IOSSearchFilters
        var apiKey: String?
    }

    private struct APISettingsResponse: Decodable {
        let data: APISettingsData
    }

    private struct APISettingsData: Decodable {
        let purity: [String]?
    }

    func search(filters: IOSSearchFilters, page: Int, apiKey: String?, seed: String? = nil) async throws -> IOSWallhavenPage {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "categories", value: filters.categoriesParameter),
            URLQueryItem(name: "purity", value: filters.purityParameter),
            URLQueryItem(name: "sorting", value: filters.sorting.rawValue),
            URLQueryItem(name: "order", value: filters.order.rawValue),
            URLQueryItem(name: "page", value: "\(page)")
        ]

        let query = filters.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            items.append(URLQueryItem(name: "q", value: query))
        }
        if let ratios = filters.ratiosParameter {
            items.append(URLQueryItem(name: "ratios", value: ratios))
        }
        if filters.sorting == .toplist {
            items.append(URLQueryItem(name: "topRange", value: "1M"))
        }
        if filters.sorting == .random,
           let seed = seed?.trimmingCharacters(in: .whitespacesAndNewlines),
           !seed.isEmpty {
            items.append(URLQueryItem(name: "seed", value: seed))
        }

        appendAPIKey(apiKey, to: &items)
        let page: IOSWallhavenPage = try await request(pathComponents: ["search"], queryItems: items)
        guard filters.ratiosParameter != nil else { return page }
        return IOSWallhavenPage(
            data: page.data.filter(filters.allowsOrientation),
            meta: page.meta
        )
    }

    func searchWithFallback(filters: IOSSearchFilters, page: Int, apiKey: String?, seed: String? = nil) async throws -> IOSWallhavenPage {
        var lastEmptyResult: IOSWallhavenPage?
        var lastError: Error?

        for candidate in searchCandidates(for: filters, page: page, apiKey: apiKey) {
            do {
                let result = try await search(
                    filters: candidate.filters,
                    page: page,
                    apiKey: candidate.apiKey,
                    seed: seed
                )
                if !result.data.isEmpty || page > 1 {
                    return result
                }
                lastEmptyResult = result
            } catch {
                if shouldStopFallback(after: error) {
                    throw error
                }
                lastError = error
            }
        }

        if let lastEmptyResult {
            return lastEmptyResult
        }
        if let lastError {
            throw lastError
        }
        return try await search(filters: filters, page: page, apiKey: apiKey, seed: seed)
    }

    func wallpaper(id: String, apiKey: String?) async throws -> IOSWallpaper {
        var items: [URLQueryItem] = []
        appendAPIKey(apiKey, to: &items)

        let response: IOSWallpaperDetailResponse = try await request(
            pathComponents: ["w", id],
            queryItems: items
        )
        return response.data
    }

    func validateAPIKey(_ apiKey: String) async throws -> Bool {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        let _: APISettingsResponse = try await request(
            pathComponents: ["settings"],
            queryItems: [URLQueryItem(name: "apikey", value: key)]
        )
        return true
    }

    func userUploads(username: String, page: Int, apiKey: String?) async throws -> IOSWallhavenPage {
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUsername.isEmpty, page > 0 else {
            throw IOSWallhavenAPIError.invalidURL
        }

        var url = URL(string: "https://wallhaven.cc/user")!
        url.appendPathComponent(cleanUsername)
        url.appendPathComponent("uploads")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw IOSWallhavenAPIError.invalidURL
        }
        components.queryItems = page > 1 ? [URLQueryItem(name: "page", value: "\(page)")] : nil
        guard let requestURL = components.url else {
            throw IOSWallhavenAPIError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 30
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue("WallDive iOS/3.1.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw IOSWallhavenAPIError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw IOSWallhavenAPIError.http(
                statusCode: http.statusCode,
                message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            )
        }
        guard let html = String(data: data, encoding: .utf8), !html.isEmpty else {
            throw IOSWallhavenAPIError.decoding("用户上传页为空")
        }

        let ids = Self.wallpaperIDs(inUploadsHTML: html)
        var wallpapersByID: [String: IOSWallpaper] = [:]
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        for chunkStart in stride(from: 0, to: ids.count, by: 4) {
            let chunk = Array(ids[chunkStart..<min(chunkStart + 4, ids.count)])
            await withTaskGroup(of: (String, IOSWallpaper?).self) { group in
                for id in chunk {
                    group.addTask { [api = self] in
                        (id, await api.wallpaperWithRetry(id: id, apiKey: key))
                    }
                }
                for await (id, wallpaper) in group {
                    if let wallpaper {
                        wallpapersByID[id] = wallpaper
                    }
                }
            }
        }

        let wallpapers = ids.compactMap { wallpapersByID[$0] }
        if !ids.isEmpty, wallpapers.isEmpty {
            throw IOSWallhavenAPIError.decoding("上传图片详情暂时不可用")
        }
        let lastPage = max(page, Self.lastUploadsPage(in: html))
        return IOSWallhavenPage(
            data: wallpapers,
            meta: IOSSearchMeta(
                currentPage: page,
                lastPage: lastPage,
                perPage: ids.count,
                total: lastPage == 1 ? ids.count : lastPage * max(ids.count, 1)
            )
        )
    }

    private func wallpaperWithRetry(id: String, apiKey: String?) async -> IOSWallpaper? {
        for attempt in 0..<2 {
            do {
                return try await wallpaper(id: id, apiKey: apiKey)
            } catch {
                guard attempt == 0 else { break }
                try? await Task.sleep(for: .milliseconds(220))
            }
        }

        guard apiKey != nil else { return nil }
        return try? await wallpaper(id: id, apiKey: nil)
    }

    func userProfile(username: String) async throws -> IOSWallhavenUserProfile {
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUsername.isEmpty else {
            throw IOSWallhavenAPIError.invalidURL
        }

        var url = URL(string: "https://wallhaven.cc/user")!
        url.appendPathComponent(cleanUsername)

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue("WallDive iOS/3.1.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw IOSWallhavenAPIError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw IOSWallhavenAPIError.http(
                statusCode: http.statusCode,
                message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            )
        }
        guard let html = String(data: data, encoding: .utf8), !html.isEmpty else {
            throw IOSWallhavenAPIError.decoding("用户主页为空")
        }

        return try Self.parseUserProfile(html: html, requestedUsername: cleanUsername)
    }

    private func appendAPIKey(_ apiKey: String?, to items: inout [URLQueryItem]) {
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !key.isEmpty {
            items.append(URLQueryItem(name: "apikey", value: key))
        }
    }

    private func searchCandidates(for filters: IOSSearchFilters, page: Int, apiKey: String?) -> [SearchCandidate] {
        var candidates: [SearchCandidate] = []
        var seen = Set<String>()

        func append(_ filters: IOSSearchFilters, apiKey: String?) {
            let key = [
                filters.query,
                filters.categoriesParameter,
                filters.purityParameter,
                filters.sorting.rawValue,
                filters.order.rawValue,
                filters.ratiosParameter ?? "all",
                apiKey?.nilIfEmpty ?? ""
            ].joined(separator: "|")
            guard !seen.contains(key) else { return }
            seen.insert(key)
            candidates.append(SearchCandidate(filters: filters, apiKey: apiKey?.nilIfEmpty))
        }

        append(filters, apiKey: apiKey)

        guard page == 1 else {
            return candidates
        }

        if filters.sketchy || filters.nsfw {
            var safeAndSketchy = filters
            safeAndSketchy.sfw = true
            safeAndSketchy.sketchy = true
            safeAndSketchy.nsfw = false
            append(safeAndSketchy, apiKey: apiKey)

            var safeAndNSFW = filters
            safeAndNSFW.sfw = true
            safeAndNSFW.sketchy = false
            safeAndNSFW.nsfw = true
            append(safeAndNSFW, apiKey: apiKey)

            var sketchyOnly = filters
            sketchyOnly.sfw = false
            sketchyOnly.sketchy = true
            sketchyOnly.nsfw = false
            append(sketchyOnly, apiKey: apiKey)

            var nsfwOnly = filters
            nsfwOnly.sfw = false
            nsfwOnly.sketchy = false
            nsfwOnly.nsfw = true
            append(nsfwOnly, apiKey: apiKey)
        }

        var safeSelectedMode = filters
        safeSelectedMode.sfw = true
        safeSelectedMode.sketchy = false
        safeSelectedMode.nsfw = false
        append(safeSelectedMode, apiKey: nil)

        return candidates
    }

    private func shouldStopFallback(after error: Error) -> Bool {
        guard let urlError = error as? URLError else {
            return false
        }

        switch urlError.code {
        case .timedOut, .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    private func request<T: Decodable>(pathComponents: [String], queryItems: [URLQueryItem]) async throws -> T {
        var url = baseURL
        pathComponents.forEach { url.appendPathComponent($0) }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw IOSWallhavenAPIError.invalidURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let requestURL = components.url else {
            throw IOSWallhavenAPIError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 28
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("WallDive iOS/3.1.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where shouldRetryRequest(error) {
            try await Task.sleep(nanoseconds: 650_000_000)
            (data, response) = try await URLSession.shared.data(for: request)
        }

        guard let http = response as? HTTPURLResponse else {
            throw IOSWallhavenAPIError.invalidResponse
        }

        guard 200..<300 ~= http.statusCode else {
            let message = decodeErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw IOSWallhavenAPIError.http(statusCode: http.statusCode, message: message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw IOSWallhavenAPIError.decoding(Self.decodingMessage(for: error, data: data))
        }
    }

    private func shouldRetryRequest(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            true
        default:
            false
        }
    }

    private func decodeErrorMessage(from data: Data) -> String? {
        struct ErrorResponse: Decodable {
            let error: String?
        }

        return try? decoder.decode(ErrorResponse.self, from: data).error
    }

    private static func decodingMessage(for error: Error, data: Data) -> String {
        let detail: String

        switch error {
        case let DecodingError.keyNotFound(key, context):
            detail = "缺少字段 \(pathDescription(context.codingPath + [key]))"
        case let DecodingError.typeMismatch(type, context):
            detail = "\(pathDescription(context.codingPath)) 类型不匹配，期望 \(type)"
        case let DecodingError.valueNotFound(type, context):
            detail = "\(pathDescription(context.codingPath)) 缺少值，期望 \(type)"
        case let DecodingError.dataCorrupted(context):
            detail = "\(pathDescription(context.codingPath)) 数据损坏：\(context.debugDescription)"
        default:
            detail = error.localizedDescription
        }

        guard let sample = String(data: data.prefix(220), encoding: .utf8), !sample.isEmpty else {
            return detail
        }
        return "\(detail)。响应片段：\(sample)"
    }

    private static func pathDescription(_ codingPath: [CodingKey]) -> String {
        let path = codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? "根节点" : path
    }

    private static func parseUserProfile(html: String, requestedUsername: String) throws -> IOSWallhavenUserProfile {
        let lines = plainTextLines(from: html)
        let username = profileUsername(in: html) ?? requestedUsername
        let avatarURL = firstURL(
            matching: #"(?i)(?:https?:)?//wallhaven\.cc/images/user/avatar/(?:200|128)/[^\"'<>\s]+"#,
            in: html
        )
        let joined = value(after: "Joined", in: lines) ?? "-"
        let uploads = countValue(after: "Uploads", in: lines)
        let favorites = countValue(after: "Favorites", in: lines)
        let subscribers = countValue(after: "Subscribers", in: lines)

        guard joined != "-" || uploads > 0 || favorites > 0 || subscribers > 0 || avatarURL != nil else {
            throw IOSWallhavenAPIError.decoding("Wallhaven 用户主页结构无法识别")
        }

        return IOSWallhavenUserProfile(
            username: username,
            avatarURL: avatarURL,
            joined: joined,
            uploadCount: uploads,
            favoriteCount: favorites,
            subscriberCount: subscribers,
            comments: profileComments(in: html),
            fetchedAt: Date()
        )
    }

    private static func wallpaperIDs(inUploadsHTML html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)href=[\"'][^\"']*/w/([a-z0-9]{6})[\"']"#) else {
            return []
        }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html))
        var seen = Set<String>()
        return matches.compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: html) else { return nil }
            let id = String(html[range]).lowercased()
            return seen.insert(id).inserted ? id : nil
        }
    }

    private static func lastUploadsPage(in html: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)[?&]page=(\d+)"#) else { return 1 }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html))
        return matches.compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: html) else { return nil }
            return Int(html[range])
        }.max() ?? 1
    }

    private static func profileUsername(in html: String) -> String? {
        guard let value = firstCapture(matching: #"(?is)<h1[^>]*>(.*?)</h1>"#, in: html) else { return nil }
        return plainTextLines(from: value).first?.nilIfEmpty
    }

    private static func countValue(after label: String, in lines: [String]) -> Int {
        guard let raw = value(after: label, in: lines) else { return 0 }
        return Int(raw.filter(\.isNumber)) ?? 0
    }

    private static func value(after label: String, in lines: [String]) -> String? {
        if let index = lines.lastIndex(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) {
            return lines.dropFirst(index + 1).first(where: { !$0.isEmpty })
        }

        let prefix = label.lowercased() + " "
        if let line = lines.last(where: { $0.lowercased().hasPrefix(prefix) }) {
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        return nil
    }

    private static func profileComments(in html: String) -> [IOSWallhavenProfileComment] {
        let boundaryPattern = #"(?i)<(?:li|article|div)[^>]*id=[\"'](?:profile-)?comment-(\d+)[\"'][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: boundaryPattern) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, range: range)
        guard !matches.isEmpty else { return [] }

        return matches.prefix(60).enumerated().compactMap { offset, match in
            guard let start = Range(match.range, in: html)?.lowerBound else { return nil }
            let end: String.Index
            if offset + 1 < matches.count, let next = Range(matches[offset + 1].range, in: html)?.lowerBound {
                end = next
            } else {
                end = html.endIndex
            }

            let block = String(html[start..<end])
            let id = capture(match: match, group: 1, in: html) ?? UUID().uuidString
            guard let author = firstCapture(
                matching: #"(?is)href=[\"'](?:https?:)?(?://wallhaven\.cc)?/user/([^\"'/?#]+)[\"']"#,
                in: block
            ) else {
                return nil
            }
            let avatar = firstURL(
                matching: #"(?i)(?:https?:)?//wallhaven\.cc/images/user/avatar/(?:200|128|32|20)/[^\"'<>\s]+"#,
                in: block
            )
            let postedAt = firstCapture(matching: #"(?is)<time[^>]*>(.*?)</time>"#, in: block).flatMap { plainTextLines(from: $0).first }
                ?? firstCapture(matching: #"(?is)<time[^>]*(?:datetime|title)=[\"']([^\"']+)[\"'][^>]*>"#, in: block)
                ?? ""

            let contentHTML = firstCapture(
                matching: #"(?is)<(?:div|section|p)[^>]*class=[\"'][^\"']*(?:comment-body|comment-content|comment-text)[^\"']*[\"'][^>]*>(.*?)</(?:div|section|p)>"#,
                in: block
            ) ?? block
            let ignored = Set([author.lowercased(), postedAt.lowercased(), id.lowercased()])
            let message = plainTextLines(from: contentHTML)
                .filter { line in
                    let key = line.lowercased()
                    return !ignored.contains(key)
                        && !key.hasPrefix("reply")
                        && !key.hasPrefix("show all")
                        && !key.hasPrefix("report")
                }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !message.isEmpty else { return nil }
            return IOSWallhavenProfileComment(
                id: id,
                author: decodeHTMLEntities(author),
                avatarURL: avatar,
                postedAt: decodeHTMLEntities(postedAt),
                message: message
            )
        }
    }

    private static func plainTextLines(from html: String) -> [String] {
        var value = html
        value = value.replacingOccurrences(
            of: #"(?is)<(?:script|style)[^>]*>.*?</(?:script|style)>"#,
            with: " ",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?i)<(?:br\s*/?|/p|/div|/li|/article|/section|/h[1-6]|/dt|/dd)\s*>"#,
            with: "\n",
            options: .regularExpression
        )
        value = value.replacingOccurrences(of: #"(?s)<[^>]+>"#, with: " ", options: .regularExpression)
        value = decodeHTMLEntities(value)
        return value
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private static func firstURL(matching pattern: String, in value: String) -> URL? {
        guard var raw = firstCapture(matching: "(\(pattern))", in: value) else { return nil }
        if raw.hasPrefix("//") { raw = "https:" + raw }
        return URL(string: decodeHTMLEntities(raw))
    }

    private static func firstCapture(matching pattern: String, in value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range) else { return nil }
        return capture(match: match, group: 1, in: value)
    }

    private static func capture(match: NSTextCheckingResult, group: Int, in value: String) -> String? {
        guard group < match.numberOfRanges,
              match.range(at: group).location != NSNotFound,
              let range = Range(match.range(at: group), in: value) else { return nil }
        return String(value[range])
    }
}

struct IOSWallpaperDetailResponse: Decodable {
    let data: IOSWallpaper
}

enum IOSWallhavenAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case http(statusCode: Int, message: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "请求地址无效。"
        case .invalidResponse:
            "Wallhaven 返回了无法识别的响应。"
        case .http(let statusCode, let message):
            "Wallhaven 请求失败（\(statusCode)）：\(message)"
        case .decoding(let message):
            "无法解析 Wallhaven 响应：\(message)"
        }
    }
}
