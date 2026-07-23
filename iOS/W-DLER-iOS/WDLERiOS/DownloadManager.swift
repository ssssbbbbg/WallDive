import Foundation
import Photos
import SwiftUI
import UIKit

@MainActor
final class IOSDownloadManager: ObservableObject {
    @Published private(set) var items: [IOSDownloadItem] = []
    @Published private(set) var downloadedIDs: Set<String>
    @Published var feedback: IOSDownloadFeedback?
    var language: IOSAppLanguage = .zhHans

    init() {
        downloadedIDs = Set(UserDefaults.standard.stringArray(forKey: Defaults.downloadedIDs) ?? [])
    }

    var activeCount: Int {
        items.filter {
            if case .queued = $0.status { return true }
            if case .running = $0.status { return true }
            return false
        }.count
    }

    var failedCount: Int {
        items.filter {
            if case .failed = $0.status { return true }
            return false
        }.count
    }

    func isDownloaded(_ wallpaper: IOSWallpaper) -> Bool {
        downloadedIDs.contains(wallpaper.id)
    }

    func isDownloading(_ wallpaper: IOSWallpaper) -> Bool {
        items.contains { item in
            guard item.wallpaperID == wallpaper.id else { return false }
            if case .queued = item.status { return true }
            if case .running = item.status { return true }
            return false
        }
    }

    func download(_ wallpaper: IOSWallpaper) {
        if isDownloaded(wallpaper) {
            showFeedback(.already(t("downloaded")))
            return
        }

        if isDownloading(wallpaper) {
            showFeedback(.running(t("downloading")))
            return
        }

        var item = IOSDownloadItem(
            wallpaper: wallpaper,
            wallpaperID: wallpaper.id,
            title: "wallhaven-\(wallpaper.id).\(wallpaper.fileExtension)",
            status: .queued,
            fileURL: nil
        )
        items.insert(item, at: 0)
        let itemID = item.id

        Task {
            update(itemID) { $0.status = .running }

            do {
                var request = URLRequest(url: wallpaper.path)
                request.timeoutInterval = 90
                request.setValue("WallDive iOS/3.1.1", forHTTPHeaderField: "User-Agent")

                let (temporaryURL, response) = try await URLSession.shared.download(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300 ~= http.statusCode) {
                    throw IOSDownloadError.http(http.statusCode)
                }

                let localURL = try makeTemporaryURL(for: wallpaper)
                if FileManager.default.fileExists(atPath: localURL.path) {
                    try FileManager.default.removeItem(at: localURL)
                }
                try FileManager.default.moveItem(at: temporaryURL, to: localURL)
                defer {
                    try? FileManager.default.removeItem(at: localURL)
                }

                try await saveToPhotoLibrary(fileURL: localURL)

                item.title = localURL.lastPathComponent
                markDownloaded(wallpaper.id)
                update(itemID) {
                    $0.title = item.title
                    $0.fileURL = nil
                    $0.status = .finished
                }
                showFeedback(.success(t("saved_to_album")))
            } catch {
                update(itemID) {
                    $0.status = .failed(displayMessage(for: error))
                }
                showFeedback(.failed(displayMessage(for: error)))
            }
        }
    }

    func downloadAll(_ wallpapers: [IOSWallpaper]) {
        let pending = wallpapers.filter { !isDownloaded($0) && !isDownloading($0) }
        guard !pending.isEmpty else {
            showFeedback(.already(t("downloaded")))
            return
        }
        pending.forEach { download($0) }
    }

    func retryFailed() {
        let failedWallpapers = items.compactMap { item -> IOSWallpaper? in
            if case .failed = item.status {
                return item.wallpaper
            }
            return nil
        }

        items.removeAll {
            if case .failed = $0.status { return true }
            return false
        }

        downloadAll(failedWallpapers)
    }

    func retry(_ item: IOSDownloadItem) {
        items.removeAll { $0.id == item.id }
        download(item.wallpaper)
    }

    func clearFinished() {
        items.removeAll {
            if case .finished = $0.status { return true }
            return false
        }
    }

    func clearFeedback(id: UUID) {
        guard feedback?.id == id else { return }
        feedback = nil
    }

    private func update(_ id: UUID, mutate: (inout IOSDownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
    }

    private func markDownloaded(_ id: String) {
        downloadedIDs.insert(id)
        UserDefaults.standard.set(Array(downloadedIDs), forKey: Defaults.downloadedIDs)
    }

    private func showFeedback(_ state: IOSDownloadFeedback.State) {
        feedback = IOSDownloadFeedback(state: state)
        switch state {
        case .success, .already:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .running:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .failed:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func displayMessage(for error: Error) -> String {
        if let downloadError = error as? IOSDownloadError {
            switch downloadError {
            case .http(let code):
                return String(format: t("original_download_http_failed"), "\(code)")
            case .photoAccessDenied:
                return t("photo_access_denied")
            case .photoSaveFailed:
                return t("photo_save_failed")
            }
        }
        return IOSDisplayMessage(for: error, language: language)
    }

    private func t(_ key: String) -> String {
        IOSL10n.t(key, language)
    }

    private func makeTemporaryURL(for wallpaper: IOSWallpaper) throws -> URL {
        let base = "wallhaven-\(wallpaper.id)"
        let ext = wallpaper.fileExtension
        var candidate = FileManager.default.temporaryDirectory.appendingPathComponent("\(base).\(ext)")

        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = FileManager.default.temporaryDirectory.appendingPathComponent("\(base)-\(suffix).\(ext)")
            suffix += 1
        }

        return candidate
    }

    private func saveToPhotoLibrary(fileURL: URL) async throws {
        try await ensurePhotoLibraryAddAccess()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: .photo, fileURL: fileURL, options: options)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: IOSDownloadError.photoSaveFailed)
                }
            }
        }
    }

    private func ensurePhotoLibraryAddAccess() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            if newStatus == .authorized || newStatus == .limited {
                return
            }
            throw IOSDownloadError.photoAccessDenied
        case .denied, .restricted:
            throw IOSDownloadError.photoAccessDenied
        @unknown default:
            throw IOSDownloadError.photoAccessDenied
        }
    }
}

struct IOSDownloadFeedback: Identifiable, Equatable {
    enum State: Equatable {
        case success(String)
        case failed(String)
        case already(String)
        case running(String)

        var message: String {
            switch self {
            case .success(let message), .failed(let message), .already(let message), .running(let message):
                return message
            }
        }

        var systemImage: String {
            switch self {
            case .success, .already:
                return "checkmark.circle.fill"
            case .failed:
                return "exclamationmark.triangle.fill"
            case .running:
                return "arrow.down.circle.fill"
            }
        }
    }

    let id = UUID()
    let state: State
}

enum IOSDownloadError: LocalizedError {
    case http(Int)
    case photoAccessDenied
    case photoSaveFailed

    var errorDescription: String? {
        switch self {
        case .http(let code):
            "原图下载失败（HTTP \(code)）。"
        case .photoAccessDenied:
            "没有相册写入权限，请在系统设置中允许 WallDive 添加照片。"
        case .photoSaveFailed:
            "原图已下载，但保存到系统相册失败。"
        }
    }
}

private enum Defaults {
    static let downloadedIDs = "downloadedIDs"
}
