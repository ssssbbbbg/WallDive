import SwiftUI

struct UserProfileSheet: View {
    let page: UserProfilePage
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: UserProfileTab = .profile

    var body: some View {
        VStack(spacing: 0) {
            UserProfileHeader(page: page, model: model, dismiss: dismiss)

            Picker("主页分区", selection: $selectedTab) {
                ForEach(UserProfileTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            Divider()

            Group {
                switch selectedTab {
                case .profile:
                    UserProfileOverview(page: page, model: model)
                case .uploads:
                    UserUploadsPane(page: page, model: model)
                case .favorites:
                    UserFavoritesPane(page: page, model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 920, idealWidth: 1040, minHeight: 680, idealHeight: 760)
        .task {
            model.loadProfileUploads(username: page.username, reset: true)
        }
    }
}

private enum UserProfileTab: String, CaseIterable, Identifiable {
    case profile
    case uploads
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: "个人主页"
        case .uploads: "上传"
        case .favorites: "收藏"
        }
    }
}

private struct UserProfileHeader: View {
    let page: UserProfilePage
    @ObservedObject var model: AppModel
    let dismiss: DismissAction

    var body: some View {
        HStack(spacing: 14) {
            ProfileAvatar(url: page.avatarURL, size: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(page.displayName)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text(page.isCurrentUser ? "我的 Wallhaven 主页" : "@\(page.username)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !page.isCurrentUser {
                Button {
                    model.toggleSubscription(page: page)
                } label: {
                    Label(
                        model.isSubscribed(username: page.username) ? "已订阅" : "订阅",
                        systemImage: model.isSubscribed(username: page.username) ? "bell.fill" : "bell"
                    )
                }
            }

            Button {
                model.openUserUploads(page.username)
                dismiss()
            } label: {
                Label("查看上传", systemImage: "rectangle.grid.2x2")
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.bar)
    }
}

private struct UserProfileOverview: View {
    let page: UserProfilePage
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 16) {
                    ProfileAvatar(url: page.avatarURL, size: 86)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(page.displayName)
                            .font(.title.weight(.semibold))
                        Text(page.group ?? "Wallhaven 用户")
                            .foregroundStyle(.secondary)
                        Text("@\(page.username)")
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                let uploadCount = model.profileUploads[page.username.lowercased()]?.count ?? 0
                let favoriteCount = favoritesForPage.count

                HStack(spacing: 12) {
                    ProfileStat(title: "已加载上传", value: "\(uploadCount)")
                    ProfileStat(title: "收藏", value: "\(favoriteCount)")
                    ProfileStat(title: "订阅状态", value: subscriptionText)
                }

                Text("上传预览")
                    .font(.headline)

                HorizontalWallpaperStrip(wallpapers: Array((model.profileUploads[page.username.lowercased()] ?? []).prefix(8)), model: model)

                Text("收藏预览")
                    .font(.headline)

                HorizontalWallpaperStrip(wallpapers: Array(favoritesForPage.prefix(8)), model: model)
            }
            .padding(22)
        }
    }

    private var favoritesForPage: [Wallpaper] {
        model.favoriteList.filter { wallpaper in
            page.isCurrentUser || wallpaper.uploader?.username.caseInsensitiveCompare(page.username) == .orderedSame
        }
    }

    private var subscriptionText: String {
        page.isCurrentUser ? "本人" : (model.isSubscribed(username: page.username) ? "已订阅" : "未订阅")
    }
}

private struct UserUploadsPane: View {
    let page: UserProfilePage
    @ObservedObject var model: AppModel

    var body: some View {
        ProfileWallpaperGrid(
            wallpapers: model.profileUploads[page.username.lowercased()] ?? [],
            isLoading: model.profileLoadingUsernames.contains(page.username.lowercased()),
            emptyText: "还没有加载到上传内容",
            loadMore: {
                model.loadProfileUploads(username: page.username, reset: false)
            },
            model: model
        )
    }
}

private struct UserFavoritesPane: View {
    let page: UserProfilePage
    @ObservedObject var model: AppModel

    var body: some View {
        ProfileWallpaperGrid(
            wallpapers: favorites,
            isLoading: false,
            emptyText: "这里显示收藏中属于此用户的图片",
            loadMore: {},
            model: model
        )
    }

    private var favorites: [Wallpaper] {
        model.favoriteList.filter { wallpaper in
            page.isCurrentUser || wallpaper.uploader?.username.caseInsensitiveCompare(page.username) == .orderedSame
        }
    }
}

private struct ProfileWallpaperGrid: View {
    let wallpapers: [Wallpaper]
    let isLoading: Bool
    let emptyText: String
    let loadMore: () -> Void
    @ObservedObject var model: AppModel

    private let columns = [
        GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            if wallpapers.isEmpty && !isLoading {
                EmptyStateView(message: emptyText)
                    .frame(height: 360)
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(wallpapers) { wallpaper in
                        WallpaperCard(
                            wallpaper: wallpaper,
                            isSelected: model.selectedWallpaper?.id == wallpaper.id,
                            isFavorite: model.isFavorite(wallpaper),
                            isSelectionMode: false,
                            isBatchSelected: false,
                            selectionAction: {},
                            downloadAction: { model.download(wallpaper) },
                            favoriteAction: { model.toggleFavorite(wallpaper) }
                        )
                        .onTapGesture {
                            model.select(wallpaper)
                        }
                    }
                }
                .padding(20)

                if isLoading {
                    ProgressView()
                        .padding(.bottom, 22)
                } else if !wallpapers.isEmpty {
                    Button {
                        loadMore()
                    } label: {
                        Label("加载更多", systemImage: "arrow.down.circle")
                    }
                    .padding(.bottom, 22)
                }
            }
        }
    }
}

private struct HorizontalWallpaperStrip: View {
    let wallpapers: [Wallpaper]
    @ObservedObject var model: AppModel

    var body: some View {
        if wallpapers.isEmpty {
            Text("暂无内容")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 82, alignment: .center)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(wallpapers) { wallpaper in
                        CachedRemoteImage(url: wallpaper.gridPreviewURL, contentMode: .fill, maxPixelSize: 360) {
                            ZStack {
                                Color.secondary.opacity(0.12)
                                ProgressView()
                            }
                        }
                        .frame(width: 130, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .onTapGesture {
                            model.select(wallpaper)
                        }
                    }
                }
            }
        }
    }
}

private struct ProfileStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
