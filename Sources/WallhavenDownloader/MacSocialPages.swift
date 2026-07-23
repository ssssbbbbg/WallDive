import SwiftUI

struct MacFollowingView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.t("your_subscriptions"))
                        .font(.system(size: 36, weight: .bold))
                    Text("(\(model.subscriptions.count + model.followedTags.count))")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.refreshSubscriptions()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .background(.thinMaterial, in: Circle())
                    .help(model.t("refresh"))
                }

                if model.subscriptions.isEmpty && model.followedTags.isEmpty {
                    MacCenteredState(
                        icon: "person.wave.2",
                        title: model.t("your_subscriptions"),
                        message: model.t("subscription_empty"),
                        isLoading: false,
                        actionTitle: nil,
                        action: nil
                    )
                    .frame(minHeight: 480)
                } else {
                    if !model.subscriptions.isEmpty {
                        Text(model.t("subscribed_users"))
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        LazyVStack(spacing: 12) {
                            ForEach(model.subscriptions) { user in
                                MacSubscriptionRow(
                                    user: user,
                                    message: model.subscriptionMessages.first(where: { $0.user.id == user.id }),
                                    model: model
                                )
                            }
                        }
                    }

                    if !model.followedTags.isEmpty {
                        Text(model.t("followed_tags"))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)

                        LazyVStack(spacing: 10) {
                            ForEach(model.followedTags) { tag in
                                MacFollowedTagRow(tag: tag, model: model)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, MacDesign.pagePadding)
            .padding(.top, 42)
            .padding(.bottom, 126)
        }
        .scrollIndicators(.hidden)
        .onAppear { model.refreshSubscriptions() }
    }
}

private struct MacSubscriptionRow: View {
    let user: SubscribedUser
    let message: SubscriptionMessage?
    @ObservedObject var model: AppModel

    var body: some View {
        Button {
            model.activeUserProfilePage = user.page
        } label: {
            HStack(spacing: 16) {
                ProfileAvatar(url: user.avatarURL ?? message?.latestWallpaper?.uploader?.bestAvatarURL, size: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(user.displayName.nilIfEmpty ?? user.username)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("@\(user.username)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 14)

                MacPreviewStack(wallpapers: message?.recentWallpapers ?? [])

                if let count = message?.newCount, count > 0 {
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(.red, in: Capsule())
                        .alignmentGuide(.top) { _ in 0 }
                }

                Image(systemName: "chevron.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: MacDesign.panelRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MacDesign.panelRadius, style: .continuous)
                    .stroke(.white.opacity(0.15), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct MacPreviewStack: View {
    let wallpapers: [Wallpaper]

    var body: some View {
        ZStack {
            ForEach(Array(wallpapers.prefix(5).enumerated()), id: \.element.id) { index, wallpaper in
                CachedRemoteImage(url: wallpaper.gridPreviewURL, contentMode: .fill, maxPixelSize: 220) {
                    Color.secondary.opacity(0.12)
                }
                .frame(width: 78, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.36), lineWidth: 0.8)
                }
                .offset(x: CGFloat(index) * -8, y: CGFloat(index) * 2)
                .zIndex(Double(5 - index))
            }
        }
        .frame(width: wallpapers.isEmpty ? 0 : 112, height: 62)
    }
}

private struct MacFollowedTagRow: View {
    let tag: FollowedTag
    @ObservedObject var model: AppModel
    @State private var showingTag = false

    var body: some View {
        Button {
            showingTag = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)
                    .background(Color.accentColor.opacity(0.12), in: Circle())
                Text(tag.name)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(height: 68)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: MacDesign.panelRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingTag) {
            MacTagFeedView(tagName: tag.name, model: model)
        }
    }
}

private enum MacMyProfileTab: String, CaseIterable, Identifiable {
    case uploads
    case favorites
    case comments

    var id: String { rawValue }
}

struct MacMeView: View {
    @ObservedObject var model: AppModel
    @Binding var showingSettings: Bool
    @Binding var showingDownloads: Bool
    @State private var selectedTab: MacMyProfileTab = .uploads

    private var cleanUsername: String {
        model.username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var profile: WallhavenUserProfile? {
        model.profile(for: cleanUsername)
    }

    private var uploadedWallpapers: [Wallpaper] {
        let remote = model.profileUploads[cleanUsername.lowercased()] ?? []
        var seen = Set<String>()
        return (model.localUploadedWallpapers + remote).filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    profileHeader
                    profileTabBar

                    switch selectedTab {
                    case .uploads:
                        if uploadedWallpapers.isEmpty, model.profileLoadingUsernames.contains(cleanUsername.lowercased()) {
                            ProgressView().frame(maxWidth: .infinity).padding(80)
                        } else if uploadedWallpapers.isEmpty {
                            MacCenteredState(icon: "square.and.arrow.up", title: model.t("no_uploads"), message: "", isLoading: false, actionTitle: nil, action: nil)
                                .frame(minHeight: 360)
                        } else {
                            MacMasonryGallery(
                                wallpapers: uploadedWallpapers,
                                model: model,
                                minimumColumnWidth: 230,
                                showsLoadMore: true,
                                loadMore: { model.loadProfileUploads(username: cleanUsername, reset: false) }
                            )
                        }
                    case .favorites:
                        if model.favoriteList.isEmpty {
                            MacCenteredState(icon: "heart", title: model.t("no_favorites"), message: "", isLoading: false, actionTitle: nil, action: nil)
                                .frame(minHeight: 360)
                        } else {
                            MacMasonryGallery(wallpapers: model.favoriteList, model: model, minimumColumnWidth: 230, loadMore: {})
                        }
                    case .comments:
                        MacProfileComments(comments: profile?.comments ?? [], model: model)
                    }
                }
                .frame(width: max(0, viewport.size.width - MacDesign.pagePadding * 2), alignment: .leading)
                .padding(.horizontal, MacDesign.pagePadding)
                .padding(.top, 38)
                .padding(.bottom, 132)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            guard !cleanUsername.isEmpty else { return }
            model.loadUserProfile(username: cleanUsername)
            model.loadProfileUploads(username: cleanUsername, reset: model.profileUploads[cleanUsername.lowercased()] == nil)
        }
    }

    private var profileTabBar: some View {
        HStack(spacing: 6) {
            ForEach(MacMyProfileTab.allCases) { tab in
                Button {
                    withAnimation(MacDesign.quickMotion) { selectedTab = tab }
                } label: {
                    Text(title(for: tab))
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            selectedTab == tab ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.clear),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .frame(width: 500)
        .background(Color.secondary.opacity(0.08), in: Capsule())
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func title(for tab: MacMyProfileTab) -> String {
        switch tab {
        case .uploads: model.t("uploads")
        case .favorites: model.t("favorites")
        case .comments: model.t("profile_comments")
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 20) {
            ZStack {
                HStack(spacing: 18) {
                    Button {
                        showingSettings = true
                    } label: {
                        ProfileAvatar(url: profile?.avatarURL ?? model.myProfile.avatarURL, size: 84)
                    }
                    .buttonStyle(.plain)
                    .help(model.t("settings"))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.myProfile.displayName.nilIfEmpty ?? profile?.username ?? "WallDive")
                            .font(.system(size: 34, weight: .bold))
                        Label(
                            model.authState == .signedIn ? model.t("online") : model.t("offline"),
                            systemImage: "circle.fill"
                        )
                        .font(.callout.weight(.medium))
                        .foregroundStyle(model.authState == .signedIn ? .green : .secondary)
                        .symbolRenderingMode(.monochrome)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Button {
                        showingDownloads = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 19, weight: .semibold))
                            if model.downloads.activeCount > 0 {
                                Circle().fill(.red).frame(width: 8, height: 8).offset(x: 1, y: 1)
                            }
                        }
                        .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.plain)
                    .background(Color.secondary.opacity(0.1), in: Circle())
                    .help(model.t("download_queue"))

                    Menu {
                        Button(model.t("import_local")) { model.chooseLocalUploadImages() }
                        Button(model.t("publish")) { model.openWallhavenUpload() }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 48, height: 48)
                    }
                    .frame(width: 48, height: 48)
                    .background(Color.secondary.opacity(0.1), in: Circle())
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity)

            Divider()

            HStack(spacing: 0) {
                MacProfileStat(value: "\(profile?.uploadCount ?? uploadedWallpapers.count)", title: model.t("uploads"))
                Divider().frame(height: 38)
                MacProfileStat(value: "\(profile?.favoriteCount ?? model.favoriteList.count)", title: model.t("favorites"))
                Divider().frame(height: 38)
                MacProfileStat(value: "\(profile?.subscriberCount ?? 0)", title: model.t("subscribers"))
                Divider().frame(height: 38)
                MacProfileStat(value: profile?.joinedYearText(language: model.languageMode) ?? "-", title: model.t("joined"))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: MacDesign.panelRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacDesign.panelRadius, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 0.8)
        }
    }
}

struct MacProfileStat: View {
    let value: String
    let title: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MacProfileComments: View {
    let comments: [WallhavenProfileComment]
    @ObservedObject var model: AppModel

    var body: some View {
        if comments.isEmpty {
            MacCenteredState(icon: "text.bubble", title: model.t("no_profile_comments"), message: "", isLoading: false, actionTitle: nil, action: nil)
                .frame(minHeight: 360)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(comments) { comment in
                    HStack(alignment: .top, spacing: 14) {
                        ProfileAvatar(url: comment.avatarURL, size: 42)
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(comment.author)
                                    .font(.headline)
                                Spacer()
                                Text(comment.postedAt)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(comment.message)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: MacDesign.panelRadius, style: .continuous))
                }
            }
        }
    }
}
