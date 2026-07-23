import AppKit
import Foundation

@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var items: [DownloadItem] = []
    @Published private(set) var downloadedIDs: Set<String>
    @Published var feedback: DownloadFeedback?
    var language: AppLanguage = .zhHans

    init() {
        downloadedIDs = Set(UserDefaults.standard.stringArray(forKey: Defaults.downloadedIDs) ?? [])
    }

    var activeCount: Int {
        items.filter {
            if case .running = $0.status { return true }
            if case .queued = $0.status { return true }
            return false
        }.count
    }

    var failedCount: Int {
        items.filter {
            if case .failed = $0.status { return true }
            return false
        }.count
    }

    func isDownloaded(_ wallpaper: Wallpaper) -> Bool {
        downloadedIDs.contains(wallpaper.id)
    }

    func isDownloading(_ wallpaper: Wallpaper) -> Bool {
        items.contains { item in
            guard item.wallpaperID == wallpaper.id else { return false }
            if case .queued = item.status { return true }
            if case .running = item.status { return true }
            return false
        }
    }

    func download(_ wallpaper: Wallpaper, to folder: URL) {
        if isDownloaded(wallpaper) {
            showFeedback(.already(t("downloaded")))
            return
        }
        if isDownloading(wallpaper) {
            showFeedback(.running(t("downloading_original")))
            return
        }

        var item = DownloadItem(
            wallpaper: wallpaper,
            wallpaperID: wallpaper.id,
            title: "wallhaven-\(wallpaper.id).\(wallpaper.fileExtension)",
            sourceURL: wallpaper.path,
            status: .queued
        )
        items.insert(item, at: 0)
        let itemID = item.id

        Task {
            update(itemID) { $0.status = .running }

            do {
                let targetURL = try makeDestinationURL(for: wallpaper, in: folder)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

                var request = URLRequest(url: wallpaper.path)
                request.timeoutInterval = 90
                request.setValue("WallDive macOS/3.1.1", forHTTPHeaderField: "User-Agent")

                let (temporaryURL, response) = try await URLSession.shared.download(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw DownloadError.http(http.statusCode)
                }

                if FileManager.default.fileExists(atPath: targetURL.path) {
                    try FileManager.default.removeItem(at: targetURL)
                }
                try FileManager.default.moveItem(at: temporaryURL, to: targetURL)

                item.title = targetURL.lastPathComponent
                markDownloaded(wallpaper.id)
                update(itemID) {
                    $0.title = item.title
                    $0.status = .finished(targetURL)
                }
                showFeedback(.success(t("downloaded")))
            } catch {
                update(itemID) { $0.status = .failed(error.localizedDescription) }
                showFeedback(.failed(error.localizedDescription))
            }
        }
    }

    func downloadAll(_ wallpapers: [Wallpaper], to folder: URL) {
        let pending = wallpapers.filter { !isDownloaded($0) && !isDownloading($0) }
        guard !pending.isEmpty else {
            showFeedback(.already(t("downloaded")))
            return
        }
        pending.forEach { download($0, to: folder) }
    }

    func retryFailed(to folder: URL) {
        let failedWallpapers = items.compactMap { item -> Wallpaper? in
            if case .failed = item.status { return item.wallpaper }
            return nil
        }
        items.removeAll {
            if case .failed = $0.status { return true }
            return false
        }
        downloadAll(failedWallpapers, to: folder)
    }

    func retry(_ item: DownloadItem, to folder: URL) {
        items.removeAll { $0.id == item.id }
        download(item.wallpaper, to: folder)
    }

    func clearFinished() {
        items.removeAll {
            if case .finished = $0.status { return true }
            return false
        }
    }

    func reveal(_ item: DownloadItem) {
        if case .finished(let url) = item.status {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func clearFeedback(id: UUID) {
        guard feedback?.id == id else { return }
        feedback = nil
    }

    private func update(_ id: UUID, mutate: (inout DownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
    }

    private func markDownloaded(_ id: String) {
        downloadedIDs.insert(id)
        UserDefaults.standard.set(Array(downloadedIDs), forKey: Defaults.downloadedIDs)
    }

    private func showFeedback(_ state: DownloadFeedback.State) {
        feedback = DownloadFeedback(state: state)
    }

    private func t(_ key: String) -> String {
        AppL10n.text(key, language: language)
    }

    private func makeDestinationURL(for wallpaper: Wallpaper, in folder: URL) throws -> URL {
        let base = "wallhaven-\(wallpaper.id)"
        let ext = wallpaper.fileExtension
        var candidate = folder.appendingPathComponent("\(base).\(ext)")
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base)-\(suffix).\(ext)")
            suffix += 1
        }
        return candidate
    }
}

enum DownloadError: LocalizedError {
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .http(let code):
            "原图下载失败（HTTP \(code)）。"
        }
    }
}

private enum Defaults {
    static let downloadedIDs = "downloadedIDs"
}
