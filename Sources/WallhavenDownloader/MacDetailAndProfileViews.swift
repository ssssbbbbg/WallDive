import SwiftUI

struct MacWallpaperDetailView: View {
    @ObservedObject var model: AppModel
    let fallbackWallpaper: Wallpaper

    @Environment(\.dismiss) private var dismiss
    @State private var wallpaper: Wallpaper
    @State private var immersive = false
    @State private var profileRoute: UserProfilePage?
    @State private var tagRoute: MacTagRoute?

    init(model: AppModel, fallbackWallpaper: Wallpaper) {
        self.model = model
        self.fallbackWallpaper = fallbackWallpaper
        _wallpaper = State(initialValue: fallbackWallpaper)
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color.black.opacity(0.94)

                CachedRemoteImage(
                    url: wallpaper.detailPreviewURL,
                    contentMode: .fit,
                    maxPixelSize: 2600
                ) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }
                .padding(22)
                .contentShape(Rectangle())
                .onTapGesture { immersive = true }

                VStack {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 38, height: 38)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(.black.opacity(0.45), in: Circle())
                        .help(model.t("close"))
                        Spacer()
                        Button { immersive = true } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 38, height: 38)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(.black.opacity(0.45), in: Circle())
                    }
                    Spacer()
                }
                .padding(18)
            }
            .frame(minWidth: 620)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    uploaderSection
                    actionRow
                    metadataSection
                    tagsSection
                }
                .padding(24)
            }
            .frame(width: 390)
            .background(.regularMaterial)
        }
        .frame(minWidth: 1040, idealWidth: 1180, minHeight: 700, idealHeight: 790)
        .task(id: fallbackWallpaper.id) {
            wallpaper = await model.resolvedWallpaper(for: fallbackWallpaper)
        }
        .sheet(isPresented: $immersive) {
            MacImmersiveImageView(wallpaper: wallpaper)
        }
        .sheet(item: $profileRoute) { page in
            MacUserProfileView(page: page, model: model)
        }
        .sheet(item: $tagRoute) { route in
            MacTagFeedView(tagName: route.name, model: model)
        }
    }

    @ViewBuilder
    private var uploaderSection: some View {
        if let uploader = wallpaper.uploader {
            Button {
                profileRoute = UserProfilePage(uploader: uploader)
            } label: {
                HStack(spacing: 12) {
                    ProfileAvatar(url: uploader.bestAvatarURL, size: 50)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(uploader.username)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(uploader.group.nilIfEmpty ?? model.t("uploader"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                model.download(wallpaper)
            } label: {
                Label(
                    model.downloads.isDownloaded(wallpaper) ? model.t("downloaded") : model.t("download_original"),
                    systemImage: model.downloads.isDownloaded(wallpaper) ? "checkmark.circle.fill" : "arrow.down.circle.fill"
                )
                .frame(maxWidth: .infinity)
                .frame(height: 42)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)

            Button {
                model.toggleFavorite(wallpaper)
            } label: {
                Image(systemName: model.isFavorite(wallpaper) ? "heart.fill" : "heart")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(model.isFavorite(wallpaper) ? .red : .primary)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .background(.thinMaterial, in: Circle())

            Menu {
                Button(model.t("open_in_browser")) { model.openInBrowser(wallpaper) }
                Button(model.t("copy_link")) { model.copyWallpaperLink(wallpaper) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(.thinMaterial, in: Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.t("information"))
                .font(.headline)
            MacMetadataRow(title: model.t("resolution"), value: wallpaper.resolution)
            MacMetadataRow(title: model.t("ratio"), value: wallpaper.ratio.nilIfEmpty ?? String(format: "%.2f", wallpaper.previewAspectRatio))
            MacMetadataRow(title: model.t("size"), value: wallpaper.byteSizeText)
            MacMetadataRow(title: model.t("type"), value: wallpaper.fileType)
            MacMetadataRow(title: model.t("views"), value: "\(wallpaper.views)")
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: MacDesign.panelRadius, style: .continuous))
    }

    @ViewBuilder
    private var tagsSection: some View {
        if !wallpaper.tags.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.t("tags"))
                    .font(.headline)
                FlowLayout(spacing: 8) {
                    ForEach(wallpaper.tags) { tag in
                        HStack(spacing: 5) {
                            Button(tag.name) { tagRoute = MacTagRoute(name: tag.name) }
                                .buttonStyle(.plain)
                            Button {
                                model.toggleFollowedTag(tag.name)
                            } label: {
                                Image(systemName: model.isFollowingTag(tag.name) ? "checkmark" : "plus")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 11)
                        .frame(height: 32)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                    }
                }
            }
        }
    }
}

private struct MacMetadataRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .textSelection(.enabled)
                .lineLimit(1)
        }
        .font(.callout)
    }
}

private struct MacImmersiveImageView: View {
    let wallpaper: Wallpaper
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CachedRemoteImage(url: wallpaper.path, contentMode: .fit, maxPixelSize: 5200) {
                ProgressView().controlSize(.large).tint(.white)
            }
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        scale = min(8, max(1, lastScale * value.magnification))
                    }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= 1.01 {
                            withAnimation(MacDesign.quickMotion) {
                                scale = 1
                                lastScale = 1
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        guard scale > 1 else { return }
                        offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
                    }
                    .onEnded { _ in lastOffset = offset }
            )
            .onTapGesture { dismiss() }

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(.black.opacity(0.5), in: Circle())
                }
                Spacer()
            }
            .padding(22)
        }
        .frame(minWidth: 1180, minHeight: 760)
    }
}

private enum MacProfileTab: String, Identifiable {
    case uploads
    case favorites
    case comments
    var id: String { rawValue }
}

struct MacUserProfileView: View {
    let page: UserProfilePage
    @ObservedObject var model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: MacProfileTab = .uploads
    @State private var selectedWallpaper: Wallpaper?

    private var key: String { page.username.lowercased() }
    private var profile: WallhavenUserProfile? { model.profile(for: page.username) }
    private var tabs: [MacProfileTab] { page.isCurrentUser ? [.uploads, .favorites, .comments] : [.uploads, .comments] }
    private var uploads: [Wallpaper] {
        let remote = model.profileUploads[key] ?? []
        guard page.isCurrentUser else { return remote }
        var seen = Set<String>()
        return (model.localUploadedWallpapers + remote).filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    profileHero
                    tabBar

                    switch selectedTab {
                    case .uploads:
                        uploadsContent
                    case .favorites:
                        favoritesContent
                    case .comments:
                        MacProfileComments(comments: profile?.comments ?? [], model: model)
                    }
                }
                .frame(width: max(0, viewport.size.width - 56), alignment: .leading)
                .padding(28)
                .padding(.bottom, 30)
            }
        }
        .frame(minWidth: 980, idealWidth: 1120, minHeight: 700, idealHeight: 800)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: key) {
            model.loadUserProfile(username: page.username)
            model.loadProfileUploads(username: page.username, reset: model.profileUploads[key] == nil)
        }
        .sheet(item: $selectedWallpaper) { wallpaper in
            MacWallpaperDetailView(model: model, fallbackWallpaper: wallpaper)
        }
    }

    private var profileHero: some View {
        VStack(spacing: 20) {
            header
            Divider()
            stats
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: MacDesign.panelRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacDesign.panelRadius, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 0.8)
        }
    }

    private var header: some View {
        HStack(spacing: 18) {
            ProfileAvatar(url: profile?.avatarURL ?? page.avatarURL, size: 82)
            VStack(alignment: .leading, spacing: 5) {
                Text(page.displayName)
                    .font(.system(size: 34, weight: .bold))
                Text("@\(page.username)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !page.isCurrentUser {
                Button {
                    model.toggleSubscription(page: page)
                } label: {
                    Label(
                        model.isSubscribed(username: page.username) ? model.t("subscribed") : model.t("subscribe"),
                        systemImage: model.isSubscribed(username: page.username) ? "checkmark" : "plus"
                    )
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            } else {
                Button(model.t("publish")) { model.openWallhavenUpload() }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .background(.thinMaterial, in: Circle())
        }
        .frame(maxWidth: .infinity)
    }

    private var stats: some View {
        HStack(spacing: 12) {
            statPanel(value: "\(profile?.uploadCount ?? uploads.count)", title: model.t("uploads"))
            statPanel(value: "\(profile?.favoriteCount ?? 0)", title: model.t("favorites"))
            statPanel(value: "\(profile?.subscriberCount ?? 0)", title: model.t("subscribers"))
            statPanel(value: profile?.joinedYearText(language: model.languageMode) ?? "-", title: model.t("joined"))
        }
        .frame(maxWidth: .infinity)
    }

    private func statPanel(value: String, title: String) -> some View {
        VStack(spacing: 5) {
            Text(value).font(.title3.weight(.semibold)).lineLimit(1)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 76)
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(tabs) { tab in
                Button {
                    withAnimation(MacDesign.quickMotion) { selectedTab = tab }
                } label: {
                    Text(title(for: tab))
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(selectedTab == tab ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.clear), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .frame(maxWidth: 480)
        .background(Color.secondary.opacity(0.08), in: Capsule())
    }

    @ViewBuilder
    private var uploadsContent: some View {
        if uploads.isEmpty, model.profileLoadingUsernames.contains(key) {
            ProgressView().controlSize(.large).frame(maxWidth: .infinity).padding(100)
        } else if uploads.isEmpty {
            MacCenteredState(
                icon: model.profileErrors[key] == nil ? "square.and.arrow.up" : "exclamationmark.triangle",
                title: model.t("no_uploads"),
                message: model.profileErrors[key] ?? "",
                isLoading: false,
                actionTitle: model.t("reload"),
                action: { model.loadProfileUploads(username: page.username, reset: true) }
            )
            .frame(minHeight: 380)
        } else {
            MacMasonryGallery(
                wallpapers: uploads,
                model: model,
                minimumColumnWidth: 225,
                showsLoadMore: true,
                loadMore: { model.loadProfileUploads(username: page.username, reset: false) },
                onOpen: { selectedWallpaper = $0 }
            )
        }
    }

    @ViewBuilder
    private var favoritesContent: some View {
        if model.favoriteList.isEmpty {
            MacCenteredState(icon: "heart", title: model.t("no_favorites"), message: "", isLoading: false, actionTitle: nil, action: nil)
                .frame(minHeight: 380)
        } else {
            MacMasonryGallery(
                wallpapers: model.favoriteList,
                model: model,
                minimumColumnWidth: 225,
                loadMore: {},
                onOpen: { selectedWallpaper = $0 }
            )
        }
    }

    private func title(for tab: MacProfileTab) -> String {
        switch tab {
        case .uploads: model.t("uploads")
        case .favorites: model.t("favorites")
        case .comments: model.t("profile_comments")
        }
    }
}

@MainActor
private final class MacTagFeedStore: ObservableObject {
    @Published var wallpapers: [Wallpaper] = []
    @Published var meta: SearchMeta?
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var networkUnavailable = false
    @Published var errorMessage: String?
    @Published var filters: SearchFilters

    private let api = WallhavenAPI()
    private var task: Task<Void, Never>?

    init(tagName: String) {
        var filters = SearchFilters()
        filters.query = tagName
        filters.sorting = .dateAdded
        filters.order = .desc
        self.filters = filters
    }

    var canLoadMore: Bool {
        guard let meta else { return false }
        return meta.currentPage < meta.lastPage
    }

    func load(reset: Bool, apiKey: String, includeAdult: Bool, language: AppLanguage) {
        guard reset || (canLoadMore && !isLoadingMore) else { return }
        let page = reset ? 1 : (meta?.currentPage ?? 0) + 1
        filters.general = true
        filters.anime = true
        filters.people = true
        filters.sfw = true
        filters.sketchy = includeAdult && !apiKey.isEmpty
        filters.nsfw = includeAdult && !apiKey.isEmpty
        let requestFilters = filters
        let key = (requestFilters.sketchy || requestFilters.nsfw) ? apiKey.nilIfEmpty : nil
        let seed = reset ? nil : meta?.seed

        if reset {
            task?.cancel()
            isLoading = true
        } else {
            isLoadingMore = true
        }
        errorMessage = nil

        task = Task {
            do {
                let result = try await api.searchWithFallback(filters: requestFilters, page: page, apiKey: key, seed: seed)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isLoading = false
                    self.isLoadingMore = false
                    self.networkUnavailable = false
                    self.meta = result.meta
                    if reset {
                        self.wallpapers = result.data
                    } else {
                        let existing = Set(self.wallpapers.map(\.id))
                        self.wallpapers.append(contentsOf: result.data.filter { !existing.contains($0.id) })
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.isLoadingMore = false
                    self.networkUnavailable = isNetworkUnavailable(error)
                    self.errorMessage = displayMessage(for: error, language: language)
                }
            }
        }
    }
}

struct MacTagFeedView: View {
    let tagName: String
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store: MacTagFeedStore
    @State private var selectedWallpaper: Wallpaper?
    @State private var showingFilter = false

    init(tagName: String, model: AppModel) {
        self.tagName = tagName
        self.model = model
        _store = StateObject(wrappedValue: MacTagFeedStore(tagName: tagName))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.plain)
                    .background(.thinMaterial, in: Circle())

                    Text("#\(tagName)")
                        .font(.system(size: 34, weight: .bold))
                    Spacer()
                    Button {
                        model.toggleFollowedTag(tagName)
                    } label: {
                        Label(model.isFollowingTag(tagName) ? model.t("followed") : model.t("follow"), systemImage: model.isFollowingTag(tagName) ? "checkmark" : "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)

                    Button { showingFilter.toggle() } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.plain)
                    .background(.thinMaterial, in: Circle())
                    .popover(isPresented: $showingFilter) {
                        VStack(spacing: 14) {
                            Picker(model.t("feed_mode"), selection: $store.filters.sorting) {
                                Text(model.t("latest")).tag(WallhavenSorting.dateAdded)
                                Text(model.t("popular")).tag(WallhavenSorting.toplist)
                                Text(model.t("random")).tag(WallhavenSorting.random)
                            }
                            .pickerStyle(.segmented)
                            Toggle(model.t("landscape_wallpapers"), isOn: $store.filters.landscape)
                            Toggle(model.t("portrait_wallpapers"), isOn: $store.filters.portrait)
                        }
                        .padding(20)
                        .frame(width: 340)
                        .onChange(of: store.filters) {
                            if !store.filters.landscape && !store.filters.portrait { store.filters.landscape = true }
                            store.load(reset: true, apiKey: model.apiKey, includeAdult: model.effectiveAdultContentEnabled, language: model.languageMode)
                        }
                    }
                }

                if store.wallpapers.isEmpty, store.isLoading {
                    ProgressView().controlSize(.large).frame(maxWidth: .infinity).padding(120)
                } else if store.wallpapers.isEmpty {
                    MacCenteredState(
                        icon: store.networkUnavailable ? "wifi.exclamationmark" : "tag",
                        title: store.networkUnavailable ? model.t("no_network") : model.t("no_wallpapers"),
                        message: store.errorMessage ?? "",
                        isLoading: false,
                        actionTitle: model.t("reload"),
                        action: { store.load(reset: true, apiKey: model.apiKey, includeAdult: model.effectiveAdultContentEnabled, language: model.languageMode) }
                    )
                    .frame(minHeight: 460)
                } else {
                    MacMasonryGallery(
                        wallpapers: store.wallpapers,
                        model: model,
                        minimumColumnWidth: 230,
                        showsLoadMore: true,
                        loadMore: { store.load(reset: false, apiKey: model.apiKey, includeAdult: model.effectiveAdultContentEnabled, language: model.languageMode) },
                        onOpen: { selectedWallpaper = $0 }
                    )
                    if store.isLoadingMore { ProgressView().frame(maxWidth: .infinity).padding(24) }
                    else if store.canLoadMore {
                        Text(model.t("continue_load_more"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(24)
                    }
                }
            }
            .padding(28)
        }
        .frame(minWidth: 980, idealWidth: 1120, minHeight: 700, idealHeight: 800)
        .task {
            store.load(reset: true, apiKey: model.apiKey, includeAdult: model.effectiveAdultContentEnabled, language: model.languageMode)
        }
        .sheet(item: $selectedWallpaper) { wallpaper in
            MacWallpaperDetailView(model: model, fallbackWallpaper: wallpaper)
        }
    }
}

private struct MacTagRoute: Identifiable {
    let name: String
    var id: String { name.lowercased() }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
