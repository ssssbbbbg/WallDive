import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        MacParityRootView(model: model)
        .preferredColorScheme(model.appAppearance.colorScheme)
        .task {
            model.initialLoad()
        }
    }
}

struct SidebarView: View {
    @ObservedObject var model: AppModel
    @Binding var showingSettings: Bool
    @State private var showingSubscriptions = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Button {
                        model.showMyProfile()
                    } label: {
                        HStack(spacing: 10) {
                            ProfileAvatar(url: model.myProfile.avatarURL, size: 46)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.myProfilePage?.displayName ?? "Wallhaven")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                AuthStatusView(state: model.authState)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 18)

                    SidebarSection("来源") {
                        Button {
                            model.runSearch(reset: true)
                        } label: {
                            Label("发现", systemImage: "rectangle.grid.2x2")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.large)

                        Button {
                            model.showLocalFavorites()
                        } label: {
                            HStack {
                                Label("收藏", systemImage: "heart.fill")
                                Spacer()
                                if model.isLoadingServerFavorites {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text("\(model.favoriteList.count)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.large)

                        Button {
                            showingSubscriptions = true
                            model.refreshSubscriptions()
                        } label: {
                            HStack {
                                Label("订阅动态", systemImage: "bell.badge")
                                Spacer()
                                Text("\(model.subscriptions.count)")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.large)
                    }

                    SidebarSection("分类") {
                        ToggleGrid {
                            PillToggle(title: "常规", systemImage: "photo", isOn: $model.filters.general)
                            PillToggle(title: "动漫", systemImage: "paintbrush.pointed", isOn: $model.filters.anime)
                            PillToggle(title: "人物", systemImage: "person.crop.rectangle", isOn: $model.filters.people)
                        }
                    }

                    SidebarSection("分级") {
                        ToggleGrid {
                            PillToggle(title: "安全", systemImage: "checkmark.shield", isOn: $model.filters.sfw)
                            PillToggle(title: "微敏感", systemImage: "eye", isOn: $model.filters.sketchy)
                            PillToggle(title: "成人", systemImage: "lock.open", isOn: $model.filters.nsfw)
                                .disabled(!model.canUseNSFW)
                                .opacity(model.canUseNSFW ? 1 : 0.45)
                        }
                    }

                    SidebarSection("排序") {
                        Picker("排序", selection: $model.filters.sorting) {
                            ForEach(WallhavenSorting.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.menu)

                        if model.filters.sorting == .toplist {
                            Picker("范围", selection: $model.filters.topRange) {
                                ForEach(TopRange.allCases) { item in
                                    Text(item.title).tag(item)
                                }
                            }
                            .pickerStyle(.menu)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        Picker("顺序", selection: $model.filters.order) {
                            ForEach(WallhavenOrder.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    SidebarSection("尺寸") {
                        Picker("最低分辨率", selection: $model.filters.minimumResolution) {
                            ForEach(ResolutionChoice.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("比例", selection: $model.filters.aspectRatio) {
                            ForEach(AspectRatioChoice.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }

            Divider()

            HStack(spacing: 10) {
                Button {
                    showingSettings = true
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
                .help("账号和下载目录")

                Spacer()

                Button {
                    model.revealDownloadFolder()
                } label: {
                    Image(systemName: "folder")
                }
                .help("打开下载目录")
            }
            .padding(16)
            .background(.thinMaterial)
        }
        .onChange(of: model.filters) {
            model.handleFiltersChanged()
        }
        .sheet(isPresented: $showingSubscriptions) {
            SubscriptionsSheet(model: model)
        }
    }

}

struct GalleryView: View {
    @ObservedObject var model: AppModel
    @Binding var showingDownloads: Bool

    var body: some View {
        VStack(spacing: 0) {
            GalleryHeader(model: model, showingDownloads: $showingDownloads)

            Divider()

            ZStack {
                if model.isLoading && model.wallpapers.isEmpty {
                    LoadingStateView()
                } else if model.wallpapers.isEmpty {
                    EmptyStateView(message: model.errorMessage)
                } else {
                    MasonryGalleryView(
                        wallpapers: model.wallpapers,
                        selectedWallpaperID: model.selectedWallpaper?.id,
                        favoriteIDs: Set(model.favoriteWallpapers.keys),
                        batchSelectedIDs: model.selectedWallpaperIDs,
                        isSelectionMode: model.isMultiSelecting,
                        isLoading: model.isLoading,
                        isLoadingMore: model.isLoadingMore,
                        canLoadMore: model.canLoadMore,
                        selectAction: { model.select($0) },
                        selectionAction: { model.toggleWallpaperSelection($0) },
                        downloadAction: { model.download($0) },
                        favoriteAction: { model.toggleFavorite($0) },
                        loadMoreAction: { model.loadMore() }
                    )
                    .equatable()
                }

                if let error = model.errorMessage, !model.wallpapers.isEmpty {
                    VStack {
                        ErrorBanner(message: error)
                            .padding(.top, 12)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct MasonryGalleryView: View, Equatable {
    let wallpapers: [Wallpaper]
    let selectedWallpaperID: String?
    let favoriteIDs: Set<String>
    let batchSelectedIDs: Set<String>
    let isSelectionMode: Bool
    let isLoading: Bool
    let isLoadingMore: Bool
    let canLoadMore: Bool
    let selectAction: (Wallpaper) -> Void
    let selectionAction: (Wallpaper) -> Void
    let downloadAction: (Wallpaper) -> Void
    let favoriteAction: (Wallpaper) -> Void
    let loadMoreAction: () -> Void

    private let spacing: CGFloat = 16
    private let horizontalPadding: CGFloat = 40
    private let minimumColumnWidth: CGFloat = 220
    private let maximumColumnCount = 5
    private let preloadDistance: CGFloat = 900

    static func == (lhs: MasonryGalleryView, rhs: MasonryGalleryView) -> Bool {
        lhs.wallpapers.map(\.id) == rhs.wallpapers.map(\.id)
            && lhs.selectedWallpaperID == rhs.selectedWallpaperID
            && lhs.favoriteIDs == rhs.favoriteIDs
            && lhs.batchSelectedIDs == rhs.batchSelectedIDs
            && lhs.isSelectionMode == rhs.isSelectionMode
            && lhs.isLoading == rhs.isLoading
            && lhs.isLoadingMore == rhs.isLoadingMore
            && lhs.canLoadMore == rhs.canLoadMore
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = makeLayout(width: proxy.size.width)

            ScrollView {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(layout.columns.enumerated()), id: \.offset) { _, column in
                        LazyVStack(spacing: spacing) {
                            ForEach(column) { wallpaper in
                                WallpaperCard(
                                    wallpaper: wallpaper,
                                    isSelected: selectedWallpaperID == wallpaper.id,
                                    isFavorite: favoriteIDs.contains(wallpaper.id),
                                    isSelectionMode: isSelectionMode,
                                    isBatchSelected: batchSelectedIDs.contains(wallpaper.id),
                                    selectionAction: { selectionAction(wallpaper) },
                                    downloadAction: { downloadAction(wallpaper) },
                                    favoriteAction: { favoriteAction(wallpaper) }
                                )
                                .equatable()
                                .onTapGesture {
                                    if isSelectionMode {
                                        selectionAction(wallpaper)
                                    } else {
                                        selectAction(wallpaper)
                                    }
                                }
                            }
                        }
                        .frame(width: layout.columnWidth)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, horizontalPadding / 2)
                .padding(.top, 20)
                .padding(.bottom, 16)

                footer
                bottomLoadTrigger
            }
            .coordinateSpace(name: "masonryScroll")
            .onPreferenceChange(MasonryBottomPreferenceKey.self) { bottomY in
                triggerLoadMoreIfNeeded(bottomY: bottomY, viewportHeight: proxy.size.height)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if isLoadingMore {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在加载更多")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
                .padding(.bottom, 24)
        } else if canLoadMore {
            Text("继续下滑加载更多")
                .font(.caption)
                .foregroundStyle(.secondary)
            .padding(.bottom, 24)
        }
    }

    private var bottomLoadTrigger: some View {
        Color.clear
            .frame(height: 1)
            .background {
                GeometryReader { marker in
                    Color.clear.preference(
                        key: MasonryBottomPreferenceKey.self,
                        value: marker.frame(in: .named("masonryScroll")).maxY
                    )
                }
            }
    }

    private func triggerLoadMoreIfNeeded(bottomY: CGFloat, viewportHeight: CGFloat) {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }
        guard bottomY <= viewportHeight + preloadDistance else { return }
        loadMoreAction()
    }

    private func makeLayout(width: CGFloat) -> MasonryLayoutResult {
        let availableWidth = max(width - horizontalPadding, minimumColumnWidth)
        let rawCount = Int((availableWidth + spacing) / (minimumColumnWidth + spacing))
        let columnCount = min(max(rawCount, 1), maximumColumnCount)
        let columnWidth = (availableWidth - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)

        var columns = Array(repeating: [Wallpaper](), count: columnCount)
        var heights = Array(repeating: CGFloat.zero, count: columnCount)

        for wallpaper in wallpapers {
            let targetColumn = heights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            columns[targetColumn].append(wallpaper)
            heights[targetColumn] += columnWidth / max(wallpaper.previewAspectRatio, 0.35) + spacing
        }

        return MasonryLayoutResult(columns: columns, columnWidth: columnWidth)
    }
}

private struct MasonryLayoutResult {
    let columns: [[Wallpaper]]
    let columnWidth: CGFloat
}

private struct MasonryBottomPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct GalleryHeader: View {
    @ObservedObject var model: AppModel
    @Binding var showingDownloads: Bool

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.title)
                        .font(.title2.weight(.semibold))
                    Text(model.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    model.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!model.canGoBack)
                .help("返回上一级")

                Button {
                    model.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!model.canGoForward)
                .help("前进到下一级")

                Button {
                    model.runSearch(reset: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新")

                Button {
                    model.isDetailPanelVisible.toggle()
                } label: {
                    Image(systemName: model.isDetailPanelVisible ? "sidebar.right" : "rectangle")
                }
                .help(model.isDetailPanelVisible ? "隐藏右侧预览" : "显示右侧预览")

                Button {
                    model.toggleMultiSelectionMode()
                } label: {
                    Label("多选", systemImage: model.isMultiSelecting ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .help(model.isMultiSelecting ? "退出多选" : "进入多选")

                Button {
                    model.downloadVisible()
                    showingDownloads = true
                } label: {
                    Label("全部下载", systemImage: "square.and.arrow.down.on.square")
                }
                .disabled(model.wallpapers.isEmpty)

                Button {
                    showingDownloads = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle")
                        if model.downloads.activeCount > 0 {
                            Text("\(model.downloads.activeCount)")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                }
                .help("下载队列")
            }

            if model.isMultiSelecting {
                HStack(spacing: 10) {
                    Label("\(model.selectedWallpaperIDs.count) 张已选", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Spacer()

                    Button {
                        model.selectAllLoadedWallpapers()
                    } label: {
                        Label("全选已加载", systemImage: "checklist")
                    }
                    .disabled(model.wallpapers.isEmpty)
                    .help("只选择当前已经加载出来的图片")

                    Button {
                        model.clearWallpaperSelection()
                    } label: {
                        Label("清空", systemImage: "xmark.circle")
                    }
                    .disabled(model.selectedWallpaperIDs.isEmpty)

                    Button {
                        model.downloadSelected()
                        showingDownloads = true
                    } label: {
                        Label("下载选中", systemImage: "square.and.arrow.down")
                    }
                    .disabled(model.selectedLoadedWallpapers.isEmpty)
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("搜索关键词、tag 或 ID", text: $model.filters.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .onSubmit {
                        model.runSearch(reset: true)
                    }

                if !model.filters.query.isEmpty {
                    Button {
                        model.filters.query = ""
                        model.runSearch(reset: true)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("清空")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(.quaternary.opacity(0.8), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(.bar)
    }
}

struct WallpaperCard: View, Equatable {
    let wallpaper: Wallpaper
    let isSelected: Bool
    let isFavorite: Bool
    let isSelectionMode: Bool
    let isBatchSelected: Bool
    let selectionAction: () -> Void
    let downloadAction: () -> Void
    let favoriteAction: () -> Void

    static func == (lhs: WallpaperCard, rhs: WallpaperCard) -> Bool {
        lhs.wallpaper.id == rhs.wallpaper.id
            && lhs.wallpaper.resolution == rhs.wallpaper.resolution
            && lhs.wallpaper.purity == rhs.wallpaper.purity
            && lhs.wallpaper.gridPreviewURL == rhs.wallpaper.gridPreviewURL
            && lhs.isSelected == rhs.isSelected
            && lhs.isFavorite == rhs.isFavorite
            && lhs.isSelectionMode == rhs.isSelectionMode
            && lhs.isBatchSelected == rhs.isBatchSelected
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(.quaternary)

            CachedRemoteImage(url: wallpaper.gridPreviewURL, contentMode: .fit, maxPixelSize: 760) {
                ZStack {
                    Color.clear
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary.opacity(0.35))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0),
                    .init(color: .black.opacity(0.58), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(wallpaper.resolution)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(wallpaper.displayPurity)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.78))
                }

                Spacer()

                if !isSelectionMode {
                    HStack(spacing: 8) {
                        Button(action: downloadAction) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 22))
                                .symbolRenderingMode(.hierarchical)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .help("下载原图")

                        Button(action: favoriteAction) {
                            Image(systemName: isFavorite ? "heart.fill" : "heart")
                                .font(.system(size: 21, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(isFavorite ? .red : .white)
                        }
                        .buttonStyle(.plain)
                        .help(isFavorite ? "取消收藏" : "收藏")
                    }
                }
            }
            .padding(10)
        }
        .overlay(alignment: .topTrailing) {
            if isSelectionMode {
                Button(action: selectionAction) {
                    Image(systemName: isBatchSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(isBatchSelected ? .white : .white.opacity(0.92), isBatchSelected ? Color.accentColor : .black.opacity(0.34))
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .padding(9)
                .help(isBatchSelected ? "取消勾选" : "勾选")
            }
        }
        .aspectRatio(wallpaper.previewAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: isBatchSelected ? 3 : (isSelected ? 2 : 1))
        }
        .shadow(color: .black.opacity((isSelected || isBatchSelected) ? 0.16 : 0.035), radius: (isSelected || isBatchSelected) ? 10 : 2, y: (isSelected || isBatchSelected) ? 6 : 1)
        .scaleEffect((isSelected || isBatchSelected) ? 1.015 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: isSelected)
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: isBatchSelected)
        .animation(.spring(response: 0.24, dampingFraction: 0.88), value: isSelectionMode)
    }

    private var cardStrokeColor: Color {
        if isBatchSelected {
            return Color.accentColor
        }
        if isSelected {
            return Color.accentColor
        }
        return Color.white.opacity(0.08)
    }
}

struct DetailPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if let wallpaper = model.selectedWallpaper {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ZStack {
                            Rectangle()
                                .fill(.quaternary)

                            CachedRemoteImage(url: wallpaper.detailPreviewURL, contentMode: .fit, maxPixelSize: 1200) {
                                ZStack {
                                    Color.clear
                                    ProgressView()
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(maxWidth: .infinity)
                        .aspectRatio(wallpaper.previewAspectRatio, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("wallhaven-\(wallpaper.id)")
                                .font(.title3.weight(.semibold))
                            Text("\(wallpaper.displayCategory) · \(wallpaper.displayPurity)")
                                .foregroundStyle(.secondary)
                        }

                        UploaderSection(model: model, wallpaper: wallpaper)

                        HStack(spacing: 10) {
                            Button {
                                model.download(wallpaper)
                            } label: {
                                Label("下载原图", systemImage: "arrow.down.circle.fill")
                            }
                            .controlSize(.large)

                            Button {
                                model.openInBrowser(wallpaper)
                            } label: {
                                Image(systemName: "safari")
                            }
                            .help("在浏览器打开")

                            Button {
                                model.copyWallpaperLink(wallpaper)
                            } label: {
                                Image(systemName: "link")
                            }
                            .help("复制链接")
                        }

                        MetadataGrid(wallpaper: wallpaper)

                        TagsSection(model: model, tags: wallpaper.tags)

                        if !wallpaper.colors.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("颜色")
                                    .font(.headline)
                                HStack(spacing: 8) {
                                    ForEach(wallpaper.colors, id: \.self) { hex in
                                        ColorSwatch(hex: hex)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text("选择一张壁纸")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.regularMaterial)
    }
}

struct UploaderSection: View {
    @ObservedObject var model: AppModel
    let wallpaper: Wallpaper

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("上传者")
                .font(.headline)

            if let uploader = wallpaper.uploader {
                Button {
                    model.showProfile(for: uploader)
                } label: {
                    HStack(spacing: 12) {
                        CachedRemoteImage(url: uploader.bestAvatarURL, contentMode: .fill, maxPixelSize: 160) {
                            ZStack {
                                Color.clear
                                ProgressView()
                            }
                        }
                        .frame(width: 46, height: 46)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(.separator.opacity(0.65), lineWidth: 1)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(uploader.username)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(uploader.group)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.separator.opacity(0.55), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .help("打开 \(uploader.username) 的主页")
            } else {
                HStack(spacing: 10) {
                    if model.isLoadingWallpaperDetail {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .foregroundStyle(.secondary)
                    }

                    Text(model.isLoadingWallpaperDetail ? "正在读取上传者信息" : "暂无上传者信息")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

struct TagsSection: View {
    @ObservedObject var model: AppModel
    let tags: [WallpaperTag]

    var body: some View {
        if !tags.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("标签")
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags.prefix(18)) { tag in
                            Button {
                                model.openTag(tag)
                            } label: {
                                Text(tag.name)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .help("搜索标签：\(tag.name)")
                        }
                    }
                }
            }
        }
    }
}

struct MetadataGrid: View {
    let wallpaper: Wallpaper

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("信息")
                .font(.headline)

            VStack(spacing: 0) {
                InfoRow(label: "分辨率", value: wallpaper.resolution)
                InfoRow(label: "比例", value: wallpaper.ratio)
                InfoRow(label: "大小", value: wallpaper.byteSizeText)
                InfoRow(label: "类型", value: wallpaper.fileType)
                InfoRow(label: "收藏", value: "\(wallpaper.favorites)")
                InfoRow(label: "浏览", value: "\(wallpaper.views)")
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.separator.opacity(0.55), lineWidth: 1)
            }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 34)
    }
}

struct ColorSwatch: View {
    let hex: String

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(hex: hex) ?? .secondary)
            .frame(width: 30, height: 30)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: 1)
            }
            .help(hex)
    }
}

struct SettingsSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var username = ""
    @State private var displayName = ""
    @State private var avatarURLString = ""
    @State private var revealKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("设置")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Wallhaven 账号")
                    .font(.headline)

                HStack {
                    if revealKey {
                        TextField("API Key", text: $apiKey)
                    } else {
                        SecureField("API Key", text: $apiKey)
                    }

                    Button {
                        revealKey.toggle()
                    } label: {
                        Image(systemName: revealKey ? "eye.slash" : "eye")
                    }
                    .help(revealKey ? "隐藏" : "显示")
                }

                TextField("用户名（同步收藏时使用）", text: $username)

                AuthStatusView(state: model.authState)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("我的资料")
                    .font(.headline)

                HStack(spacing: 12) {
                    ProfileAvatar(url: URL.wallhavenSafeURL(from: avatarURLString), size: 44)

                    VStack(spacing: 8) {
                        TextField("显示名称", text: $displayName)
                        TextField("头像图片 URL", text: $avatarURLString)
                    }
                }

                HStack {
                    Button {
                        model.syncAccountProfileFromWallhaven()
                    } label: {
                        Label("同步 Wallhaven 头像", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Button {
                        model.chooseLocalAvatarImage()
                    } label: {
                        Label("选择本地头像", systemImage: "photo")
                    }
                }

                if let message = model.accountSyncMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("下载目录")
                    .font(.headline)

                HStack {
                    Text(model.downloadFolderPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.chooseDownloadFolder()
                    } label: {
                        Label("选择", systemImage: "folder")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("外观")
                    .font(.headline)

                Picker("外观", selection: $model.appAppearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                Toggle(isOn: $model.isDetailPanelVisible) {
                    Label("显示右侧预览和信息", systemImage: "sidebar.right")
                }
            }

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                Button {
                    model.saveCredentials(apiKey: apiKey, username: username)
                    model.updateMyProfile(displayName: displayName, avatarURLString: avatarURLString)
                    dismiss()
                } label: {
                    Label("保存", systemImage: "checkmark")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460)
        .onAppear {
            apiKey = model.apiKey
            username = model.username
            displayName = model.myProfile.displayName
            avatarURLString = model.myProfile.avatarURLString
        }
        .onChange(of: model.myProfile) {
            displayName = model.myProfile.displayName
            avatarURLString = model.myProfile.avatarURLString
        }
    }
}

struct DownloadsSheet: View {
    @ObservedObject var downloads: DownloadManager
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("下载队列")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    downloads.clearFinished()
                } label: {
                    Label("清理完成项", systemImage: "checkmark.circle")
                }
                .disabled(downloads.items.isEmpty)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if downloads.items.isEmpty {
                EmptyStateView(message: nil)
                    .frame(height: 220)
            } else {
                List(downloads.items) { item in
                    DownloadRow(item: item) {
                        downloads.reveal(item)
                    }
                }
                .listStyle(.inset)
            }

            HStack {
                Text(model.downloadFolderPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.revealDownloadFolder()
                } label: {
                    Label("打开目录", systemImage: "folder")
                }
            }
        }
        .padding(22)
        .frame(width: 560, height: 520)
    }
}

struct DownloadRow: View {
    let item: DownloadItem
    let reveal: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                reveal()
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .disabled(!isFinished)
            .help("在 Finder 中显示")
        }
        .padding(.vertical, 5)
    }

    private var isFinished: Bool {
        if case .finished = item.status { return true }
        return false
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .queued:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .running:
            ProgressView().controlSize(.small)
        case .finished:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var statusText: String {
        switch item.status {
        case .queued:
            "等待中"
        case .running:
            "下载中"
        case .finished(let url):
            url.path
        case .failed(let message):
            message
        }
    }
}

struct AuthStatusView: View {
    let state: AuthState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var color: Color {
        switch state {
        case .signedOut: .secondary
        case .validating: .yellow
        case .signedIn: .green
        case .failed: .red
        }
    }

    private var text: String {
        switch state {
        case .signedOut: "离线"
        case .validating: "连接中"
        case .signedIn: "在线"
        case .failed: "离线"
        }
    }
}

struct SidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
        }
    }
}

struct ToggleGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], alignment: .leading, spacing: 8) {
            content
        }
    }
}

struct PillToggle: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.84)) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .imageScale(.small)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .font(.caption.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(background)
            .foregroundStyle(isOn ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isOn ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.09))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isOn ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
            }
    }
}

struct LoadingStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("正在连接 Wallhaven")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    let message: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: message == nil ? "photo.on.rectangle.angled" : "exclamationmark.triangle")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(message ?? "暂无内容")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .lineLimit(2)
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.6), lineWidth: 1)
        }
    }
}

extension Color {
    init?(hex: String) {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }

        guard clean.count == 6, let value = Int(clean, radix: 16) else {
            return nil
        }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
