import SwiftUI
import PhotosUI

private enum IOSWallhavenConnectionState: Equatable {
    case idle
    case checking
    case connected
    case failed
}

struct IOSSettingsView: View {
    @ObservedObject var model: IOSAppModel
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var apiKey = ""
    @State private var displayName = ""
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var cacheMessage: String?
    @State private var cacheFeedbackToken = UUID()
    @State private var cacheSizeText = "0 KB"
    @State private var revealKey = false
    @State private var initialAPIKey = ""
    @State private var wallhavenConnection: IOSWallhavenConnectionState = .idle

    var body: some View {
        NavigationStack {
            Form {
                Section(t("profile")) {
                    HStack(spacing: 16) {
                        PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                            IOSLocalAvatarView(model: model, size: 58)
                        }
                        .buttonStyle(.plain)

                        TextField(t("name"), text: $displayName)
                            .font(.headline)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.vertical, 4)
                }

                Section(t("appearance")) {
                    Picker(t("display_mode"), selection: $model.themeMode) {
                        ForEach(IOSThemeMode.allCases) { mode in
                            Text(mode.title(language: model.languageMode)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker(t("language"), selection: $model.languageMode) {
                        ForEach(IOSAppLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(t("wallhaven_account")) {
                    HStack(spacing: 10) {
                        Image(systemName: wallhavenConnectionIcon)
                            .foregroundStyle(wallhavenConnectionColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(wallhavenConnectionTitle)
                                .font(.subheadline.weight(.semibold))
                            Text(wallhavenConnectionDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if wallhavenConnection == .checking {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if wallhavenConnection == .idle || wallhavenConnection == .failed {
                        Button {
                            openURL(URL(string: "https://wallhaven.cc/login")!)
                        } label: {
                            Label(t("wallhaven_login"), systemImage: "safari")
                        }

                        Text(t("wallhaven_login_privacy"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Toggle(isOn: $model.includeAdultContent) {
                        Label(t("restricted_content"), systemImage: "eye")
                    }

                    HStack {
                        if revealKey {
                            TextField(t("api_key"), text: $apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField(t("api_key"), text: $apiKey)
                        }

                        Button {
                            revealKey.toggle()
                        } label: {
                            Image(systemName: revealKey ? "eye.slash" : "eye")
                        }
                    }

                    Text(t("restricted_description"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(t("cache")) {
                    HStack {
                        Button {
                            clearCache()
                        } label: {
                            Label(t("clear_cache"), systemImage: "trash")
                        }

                        Spacer()

                        Text(cacheSizeText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Section(t("software_version")) {
                    LabeledContent("WallDive", value: appVersion)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(t("settings"))
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .top) {
                if let cacheMessage {
                    Label(cacheMessage, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 46)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 23, style: .continuous)
                                .stroke(.white.opacity(0.2), lineWidth: 0.5)
                        }
                        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(IOSMotion.quick, value: cacheMessage)
            .sensoryFeedback(.success, trigger: cacheFeedbackToken)
            .onAppear {
                loadSettings()
                updateCacheSize()
            }
            .onDisappear {
                persistSettings()
            }
            .onChange(of: displayName) { _, _ in
                persistProfile()
            }
            .onChange(of: apiKey) { _, newValue in
                model.apiKey = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .onChange(of: model.languageMode) { _, _ in
                cacheMessage = cacheMessage == nil ? nil : t("cache_cleared")
            }
            .onChange(of: model.includeAdultContent) { _, _ in
                model.refreshCurrentSearch()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await refreshWallhavenConnection() }
                }
            }
            .onChange(of: selectedAvatarItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            model.saveAvatarImage(data)
                            selectedAvatarItem = nil
                        }
                    }
                }
            }
            .iosGlassHomeIndicatorArea()
        }
        .task(id: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)) {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await refreshWallhavenConnection()
        }
        .dismissKeyboardOnOutsideTap()
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.1.1"
    }

    private func t(_ key: String) -> String {
        IOSL10n.t(key, model.languageMode)
    }

    private func updateCacheSize() {
        cacheSizeText = IOSFormattedCacheSize()
    }

    private func clearCache() {
        model.clearCaches()
        updateCacheSize()

        let token = UUID()
        cacheFeedbackToken = token
        withAnimation(IOSMotion.quick) {
            cacheMessage = t("cache_cleared")
        }

        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard cacheFeedbackToken == token else { return }
                withAnimation(IOSMotion.quick) {
                    cacheMessage = nil
                }
            }
        }
    }

    private var wallhavenConnectionIcon: String {
        switch wallhavenConnection {
        case .connected: "checkmark.circle.fill"
        case .checking: "arrow.triangle.2.circlepath"
        case .idle, .failed: "key"
        }
    }

    private var wallhavenConnectionColor: Color {
        switch wallhavenConnection {
        case .connected: .green
        case .failed: .red
        case .idle, .checking: .secondary
        }
    }

    private var wallhavenConnectionTitle: String {
        switch wallhavenConnection {
        case .connected: t("wallhaven_api_connected")
        case .checking: t("wallhaven_api_checking")
        case .failed: t("wallhaven_api_failed")
        case .idle: t("wallhaven_api_required")
        }
    }

    private var wallhavenConnectionDetail: String {
        wallhavenConnection == .connected ? displayName : t("wallhaven_secure_session_detail")
    }

    private func refreshWallhavenConnection() async {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            wallhavenConnection = .idle
            return
        }

        wallhavenConnection = .checking
        do {
            wallhavenConnection = try await IOSWallhavenAPI().validateAPIKey(key) ? .connected : .failed
        } catch {
            guard !Task.isCancelled else { return }
            wallhavenConnection = .failed
        }
    }

    private func loadSettings() {
        apiKey = model.apiKey
        displayName = model.displayName
        initialAPIKey = apiKey
    }

    private func persistSettings() {
        let nextAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldRefresh = nextAPIKey != initialAPIKey

        persistProfile()
        model.apiKey = nextAPIKey

        initialAPIKey = nextAPIKey

        if shouldRefresh {
            model.refreshCurrentSearch()
        }
    }

    private func persistProfile() {
        model.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "WallDive"
    }
}

struct IOSDownloadsView: View {
    @ObservedObject var downloads: IOSDownloadManager
    let language: IOSAppLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if downloads.items.isEmpty {
                    ContentUnavailableView(t("no_download_tasks"), systemImage: "arrow.down.circle")
                } else {
                    ForEach(downloads.items) { item in
                        HStack(spacing: 12) {
                            downloadPreview(for: item)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                Text(statusText(for: item.status))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if case .failed = item.status {
                                Button {
                                    downloads.retry(item)
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                            }

                            if let fileURL = item.fileURL {
                                ShareLink(item: fileURL) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(t("download_queue"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(t("close")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if downloads.failedCount > 0 {
                        Button(t("retry_failed")) {
                            downloads.retryFailed()
                        }
                    } else {
                        Button(t("clear")) {
                            downloads.clearFinished()
                        }
                    }
                }
            }
            .iosGlassHomeIndicatorArea()
        }
    }

    @ViewBuilder
    private func downloadPreview(for item: IOSDownloadItem) -> some View {
        ZStack {
            IOSCachedRemoteImage(url: item.wallpaper.gridPreviewURL, contentMode: .fill, maxPixelSize: 180) {
                Image(systemName: "photo")
                    .font(.headline)
                    .foregroundStyle(.secondary.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemFill))
            }
            .frame(width: 58, height: 58)
            .clipped()

            if case .running = item.status {
                statusBadge(for: item.status)
            } else {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        statusBadge(for: item.status)
                            .offset(x: 3, y: 3)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: IOSDesign.imagePreviewCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IOSDesign.imagePreviewCornerRadius, style: .continuous)
                .stroke(Color(.separator).opacity(0.16), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func statusBadge(for status: IOSDownloadStatus) -> some View {
        switch status {
        case .queued:
            Image(systemName: "clock")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(.regularMaterial, in: Circle())
        case .running:
            ProgressView()
                .controlSize(.small)
                .frame(width: 30, height: 30)
                .background(.regularMaterial, in: Circle())
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.green)
                .frame(width: 22, height: 22)
                .background(.regularMaterial, in: Circle())
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)
                .frame(width: 22, height: 22)
                .background(.regularMaterial, in: Circle())
        }
    }

    private func statusText(for status: IOSDownloadStatus) -> String {
        switch status {
        case .queued:
            t("queued")
        case .running:
            t("downloading_original")
        case .finished:
            t("saved_to_photos")
        case .failed(let message):
            message
        }
    }

    private func t(_ key: String) -> String {
        IOSL10n.t(key, language)
    }
}
