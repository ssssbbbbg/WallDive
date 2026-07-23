import SwiftUI

struct MacSettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey = ""
    @State private var username = ""
    @State private var displayName = ""
    @State private var cacheCleared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(model.t("settings"))
                        .font(.system(size: 30, weight: .bold))
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .background(.thinMaterial, in: Circle())
                }

                profileSection
                accountSection
                preferencesSection
                storageSection

                HStack {
                    Text(model.t("software_version"))
                    Spacer()
                    Text(versionText)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
            .padding(24)
        }
        .frame(width: 640)
        .frame(minHeight: 700, idealHeight: 780)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            apiKey = model.apiKey
            username = model.username
            displayName = model.myProfile.displayName
        }
        .onDisappear {
            model.updateMyProfile(displayName: displayName, avatarURLString: model.myProfile.avatarURLString)
            if apiKey != model.apiKey || username != model.username {
                model.saveCredentials(apiKey: apiKey, username: username)
            }
        }
        .onChange(of: model.includeAdultContent) {
            model.refreshCurrentSearch(showFeedback: false)
        }
        .overlay(alignment: .bottom) {
            if cacheCleared {
                Label(model.t("cache_cleared"), systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 15)
                    .frame(height: 40)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var profileSection: some View {
        HStack(spacing: 16) {
            Button {
                model.chooseLocalAvatarImage()
            } label: {
                ProfileAvatar(url: model.myProfile.avatarURL, size: 68)
            }
            .buttonStyle(.plain)
            .help(model.t("profile"))

            VStack(alignment: .leading, spacing: 6) {
                Text(model.t("profile"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(model.t("name"), text: $displayName)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: MacDesign.panelRadius, style: .continuous))
    }

    @ViewBuilder
    private var accountSection: some View {
        if model.authState == .signedIn {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.t("wallhaven_account"))
                        .font(.headline)
                    Text(model.username.nilIfEmpty ?? model.t("online"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.syncAccountProfileFromWallhaven()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .help(model.t("sync_profile"))
                Button {
                    apiKey = ""
                    username = ""
                    model.signOut()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
            .padding(18)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: MacDesign.panelRadius, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.t("wallhaven_account"))
                    .font(.headline)
                SecureField(model.t("api_key"), text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                TextField(model.t("username"), text: $username)
                    .textFieldStyle(.roundedBorder)
                if case .failed(let message) = model.authState {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(18)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: MacDesign.panelRadius, style: .continuous))
        }
    }

    private var preferencesSection: some View {
        VStack(spacing: 0) {
            settingRow(title: model.t("appearance"), icon: "circle.lefthalf.filled") {
                Picker("", selection: $model.appAppearance) {
                    Text(model.t("automatic")).tag(AppAppearance.system)
                    Text(model.t("day")).tag(AppAppearance.light)
                    Text(model.t("night")).tag(AppAppearance.dark)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 230)
            }

            Divider().padding(.leading, 42)

            settingRow(title: model.t("language"), icon: "globe") {
                Picker("", selection: $model.languageMode) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }

            Divider().padding(.leading, 42)

            settingRow(title: model.t("restricted_content"), icon: "eye.trianglebadge.exclamationmark") {
                Toggle("", isOn: $model.includeAdultContent)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            Text(model.t("restricted_description"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 42)
                .padding(.trailing, 14)
                .padding(.bottom, 14)
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: MacDesign.panelRadius, style: .continuous))
    }

    private var storageSection: some View {
        VStack(spacing: 0) {
            settingRow(title: model.t("download_folder"), icon: "folder") {
                HStack(spacing: 8) {
                    Text(model.downloadFolderURL.lastPathComponent)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button { model.chooseDownloadFolder() } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().padding(.leading, 42)

            settingRow(title: model.t("cache"), icon: "internaldrive") {
                HStack(spacing: 10) {
                    Text(model.cacheSizeText)
                        .foregroundStyle(.secondary)
                    Button(model.t("clear_cache")) {
                        model.clearCaches()
                        withAnimation(MacDesign.quickMotion) { cacheCleared = true }
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(1.6))
                            withAnimation(MacDesign.quickMotion) { cacheCleared = false }
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
            }
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: MacDesign.panelRadius, style: .continuous))
    }

    private func settingRow<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            Text(title)
                .font(.body.weight(.medium))
            Spacer()
            content()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3.1.1"
        return version
    }
}

struct MacDownloadsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel) {
        self.model = model
        self.downloads = model.downloads
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .background(.thinMaterial, in: Circle())

                Spacer()
                Text(model.t("download_queue"))
                    .font(.title2.weight(.semibold))
                Spacer()

                Menu {
                    if downloads.failedCount > 0 {
                        Button(model.t("retry_failed")) { downloads.retryFailed(to: model.downloadFolderURL) }
                    }
                    Button(model.t("clear")) { downloads.clearFinished() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(.thinMaterial, in: Circle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
            .padding(20)

            if downloads.items.isEmpty {
                MacCenteredState(icon: "arrow.down.circle", title: model.t("no_download_tasks"), message: "", isLoading: false, actionTitle: nil, action: nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(downloads.items) { item in
                            MacDownloadRow(item: item, model: model, downloads: downloads)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }

            HStack {
                Text(model.downloadFolderPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button { model.revealDownloadFolder() } label: {
                    Label(model.t("open_folder"), systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
            .padding(20)
            .background(.bar)
        }
        .frame(width: 660)
        .frame(minHeight: 560, idealHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct MacDownloadRow: View {
    let item: DownloadItem
    @ObservedObject var model: AppModel
    @ObservedObject var downloads: DownloadManager

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                CachedRemoteImage(url: item.wallpaper.gridPreviewURL, contentMode: .fit, maxPixelSize: 260) {
                    Color.secondary.opacity(0.08)
                }
                if isRunning {
                    Circle()
                        .fill(.black.opacity(0.56))
                        .frame(width: 30, height: 30)
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
            }
            .frame(width: 76, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Label(statusText, systemImage: statusIcon)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }

            Spacer()

            if case .failed = item.status {
                Button(model.t("retry")) { downloads.retry(item, to: model.downloadFolderURL) }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            } else if case .finished = item.status {
                Button { downloads.reveal(item) } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: MacDesign.panelRadius, style: .continuous))
    }

    private var isRunning: Bool {
        if case .running = item.status { return true }
        return false
    }

    private var statusText: String {
        switch item.status {
        case .queued: model.t("queued")
        case .running: model.t("downloading_original")
        case .finished: model.t("downloaded")
        case .failed(let message): message
        }
    }

    private var statusIcon: String {
        switch item.status {
        case .queued: "clock"
        case .running: "arrow.down.circle"
        case .finished: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .finished: .green
        case .failed: .orange
        default: .secondary
        }
    }
}
