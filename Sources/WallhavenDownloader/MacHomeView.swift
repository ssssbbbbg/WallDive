import AppKit
import SwiftUI

struct MacHomeView: View {
    @ObservedObject var model: AppModel

    @State private var showingFilter = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        ScrollViewReader { scrollProxy in
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: 0) {
                        MacScrollOffsetObserver { offset in
                            if offset > 8 {
                                model.isHomeGalleryScrolling = true
                            }
                            let collapsed = model.isHomeHeaderCollapsed ? offset > 8 : offset > 52
                            guard collapsed != model.isHomeHeaderCollapsed else { return }
                            withAnimation(MacDesign.motion) {
                                model.isHomeHeaderCollapsed = collapsed
                            }
                        }
                        .frame(width: 1, height: 1)
                        .id("wallDiveHomeTop")

                        content
                            .padding(.top, 92)
                            .padding(.bottom, 126)
                    }
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.immediately)

                MacSearchIsland(
                    model: model,
                    collapsed: model.isHomeHeaderCollapsed,
                    searchFocused: $searchFocused,
                    showingFilter: $showingFilter,
                    expandSearch: {
                        withAnimation(MacDesign.motion) {
                            scrollProxy.scrollTo("wallDiveHomeTop", anchor: .top)
                        }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(280))
                            searchFocused = true
                        }
                    }
                )
                .padding(.horizontal, MacDesign.pagePadding)
                .padding(.top, 20)
            }
        }
        .onDisappear {
            searchFocused = false
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.wallpapers.isEmpty, model.isLoading {
            MacCenteredState(
                icon: "photo.stack",
                title: model.t("loading"),
                message: "",
                isLoading: true,
                actionTitle: nil,
                action: nil
            )
            .frame(minHeight: 540)
        } else if model.wallpapers.isEmpty {
            MacCenteredState(
                icon: model.networkUnavailable ? "wifi.exclamationmark" : "photo.stack",
                title: model.networkUnavailable ? model.t("no_network") : model.t("no_wallpapers"),
                message: model.errorMessage ?? (model.networkUnavailable ? model.t("network_unavailable_message") : model.t("wallhaven_empty_help")),
                isLoading: false,
                actionTitle: model.t("reload"),
                action: { model.refreshCurrentSearch(showFeedback: true) }
            )
            .frame(minHeight: 540)
        } else {
            MacMasonryGallery(
                wallpapers: model.visibleWallpapers,
                model: model,
                minimumColumnWidth: 250,
                showsLoadMore: true,
                loadMore: { model.loadMore() }
            )
            .padding(.horizontal, MacDesign.pagePadding)

            if model.isLoadingMore {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(model.t("loading"))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 24)
            } else if model.canLoadMore {
                Text(model.t("continue_load_more"))
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 24)
            }
        }
    }
}

private struct MacSearchIsland: View {
    @ObservedObject var model: AppModel
    let collapsed: Bool
    let searchFocused: FocusState<Bool>.Binding
    @Binding var showingFilter: Bool
    let expandSearch: () -> Void

    var body: some View {
        Group {
            if collapsed {
                HStack(spacing: 10) {
                    Button(action: expandSearch) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 52, height: 52)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay { Circle().stroke(.white.opacity(0.2), lineWidth: 0.8) }
                    .shadow(color: .black.opacity(0.13), radius: 16, y: 6)

                    Spacer(minLength: 0)

                    filterButton(size: 52)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay { Circle().stroke(.white.opacity(0.2), lineWidth: 0.8) }
                        .shadow(color: .black.opacity(0.13), radius: 16, y: 6)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.secondary)

                    TextField("", text: $model.filters.query)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused(searchFocused)
                        .onSubmit { model.runSearch(reset: true) }

                    if !model.filters.query.isEmpty {
                        Button {
                            model.filters.query = ""
                            model.runSearch(reset: true)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    filterButton(size: 36)
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: 720)
                .frame(height: 58)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay { Capsule().stroke(.white.opacity(0.2), lineWidth: 0.8) }
                .shadow(color: .black.opacity(0.14), radius: 20, y: 8)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .animation(MacDesign.motion, value: collapsed)
    }

    private func filterButton(size: CGFloat) -> some View {
        Button {
            showingFilter.toggle()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: size > 40 ? 21 : 19, weight: .semibold))
                if model.filters.ratiosParameter != nil || model.filters.sorting != .dateAdded {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .offset(x: 5, y: -4)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingFilter, arrowEdge: .top) {
            MacFeedFilterView(model: model)
        }
        .help(model.t("menu"))
    }
}

struct MacFeedFilterView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(model.t("feed_mode"))
                .font(.headline)

            HStack(spacing: 10) {
                sortingButton(.dateAdded, title: model.t("latest"), icon: "clock.fill")
                sortingButton(.toplist, title: model.t("popular"), icon: "flame.fill")
                sortingButton(.random, title: model.t("random"), icon: "shuffle")
            }

            Divider()

            Text(model.t("orientation"))
                .font(.headline)

            VStack(spacing: 10) {
                orientationRow(
                    title: model.t("landscape_wallpapers"),
                    icon: "rectangle",
                    isOn: model.filters.landscape,
                    toggle: {
                        model.setOrientationFilters(
                            landscape: !model.filters.landscape,
                            portrait: model.filters.portrait || model.filters.landscape
                        )
                    }
                )
                orientationRow(
                    title: model.t("portrait_wallpapers"),
                    icon: "rectangle.portrait",
                    isOn: model.filters.portrait,
                    toggle: {
                        model.setOrientationFilters(
                            landscape: model.filters.landscape || model.filters.portrait,
                            portrait: !model.filters.portrait
                        )
                    }
                )
            }
        }
        .padding(22)
        .frame(width: 360)
    }

    private func sortingButton(_ sorting: WallhavenSorting, title: String, icon: String) -> some View {
        let selected = model.filters.sorting == sorting
        return Button {
            model.setFeedSorting(sorting)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Color.accentColor : Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func orientationRow(title: String, icon: String, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 24)
                Text(title)
                    .font(.body.weight(.medium))
                Spacer()
                ZStack {
                    Circle()
                        .fill(isOn ? Color.accentColor : Color.secondary.opacity(0.15))
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct MacMasonryGallery: View {
    let wallpapers: [Wallpaper]
    @ObservedObject var model: AppModel
    var minimumColumnWidth: CGFloat = 240
    var showsLoadMore = false
    let loadMore: () -> Void
    var onOpen: ((Wallpaper) -> Void)? = nil
    @State private var measuredHeight: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let columnCount = max(2, min(5, Int((proxy.size.width + 14) / (minimumColumnWidth + 14))))
            let columnWidth = (proxy.size.width - CGFloat(columnCount - 1) * 14) / CGFloat(columnCount)
            let columns = distribute(wallpapers, count: columnCount, width: columnWidth)

            HStack(alignment: .top, spacing: 14) {
                ForEach(columns.indices, id: \.self) { index in
                    LazyVStack(spacing: 14) {
                        ForEach(columns[index]) { wallpaper in
                            MacWallpaperTile(wallpaper: wallpaper, width: columnWidth, model: model, onOpen: onOpen)
                                .onAppear {
                                    if showsLoadMore, isNearLoadedEnd(wallpaper, columnCount: columnCount) {
                                        loadMore()
                                    }
                                }
                        }
                    }
                    .frame(width: columnWidth)
                }
            }
            .background {
                GeometryReader { contentProxy in
                    Color.clear.preference(key: MacMasonryHeightPreferenceKey.self, value: contentProxy.size.height)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: max(1, measuredHeight))
        .onPreferenceChange(MacMasonryHeightPreferenceKey.self) { height in
            guard height.isFinite, height > 0, abs(height - measuredHeight) > 0.5 else { return }
            measuredHeight = height
        }
    }

    private func isNearLoadedEnd(_ wallpaper: Wallpaper, columnCount: Int) -> Bool {
        let threshold = max(columnCount, 3)
        return wallpapers.suffix(threshold).contains(where: { $0.id == wallpaper.id })
    }

    private func distribute(_ items: [Wallpaper], count: Int, width: CGFloat) -> [[Wallpaper]] {
        guard count > 0 else { return [] }
        var result = Array(repeating: [Wallpaper](), count: count)
        if items.count < count {
            let start = items.count == 1 ? count / 2 : max(0, (count - items.count) / 2)
            for (offset, wallpaper) in items.enumerated() {
                result[min(count - 1, start + offset)].append(wallpaper)
            }
            return result
        }
        var heights = Array(repeating: CGFloat.zero, count: count)
        for wallpaper in items {
            let index = heights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            result[index].append(wallpaper)
            let ratio = max(0.42, min(2.4, wallpaper.previewAspectRatio))
            heights[index] += width / ratio + 14
        }
        return result
    }

}

struct MacWallpaperTile: View {
    let wallpaper: Wallpaper
    let width: CGFloat
    @ObservedObject var model: AppModel
    var onOpen: ((Wallpaper) -> Void)? = nil

    private var height: CGFloat {
        let ratio = max(0.42, min(2.4, wallpaper.previewAspectRatio))
        return width / ratio
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: MacDesign.imageRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.1))

            CachedRemoteImage(
                url: wallpaper.gridPreviewURL,
                contentMode: .fit,
                maxPixelSize: max(720, width * 2.2)
            ) {
                ZStack {
                    Color.secondary.opacity(0.08)
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: width, height: height)

            if model.isMultiSelecting {
                Color.black.opacity(model.selectedWallpaperIDs.contains(wallpaper.id) ? 0.16 : 0.04)
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: model.selectedWallpaperIDs.contains(wallpaper.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 24, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .shadow(radius: 5)
                            .padding(10)
                    }
                    Spacer()
                }
            } else if model.downloads.isDownloaded(wallpaper) {
                VStack {
                    HStack {
                        Spacer()
                        Label(model.t("downloaded"), systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .foregroundStyle(.white)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(10)
                    }
                    Spacer()
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: MacDesign.imageRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: MacDesign.imageRadius, style: .continuous))
        .onTapGesture {
            if model.isMultiSelecting {
                model.toggleWallpaperSelection(wallpaper)
            } else {
                if let onOpen { onOpen(wallpaper) } else { model.select(wallpaper) }
            }
        }
        .onLongPressGesture(minimumDuration: 0.42) {
            model.beginMultiSelection(with: wallpaper)
        }
        .contextMenu {
            Button {
                model.download(wallpaper)
            } label: {
                Label(model.t("download_original"), systemImage: "arrow.down.circle")
            }
            Button {
                model.toggleFavorite(wallpaper)
            } label: {
                Label(model.isFavorite(wallpaper) ? model.t("favorites") : model.t("favorites"), systemImage: model.isFavorite(wallpaper) ? "heart.slash" : "heart")
            }
            Divider()
            Button {
                model.beginMultiSelection(with: wallpaper)
            } label: {
                Label(model.t("select_all"), systemImage: "checkmark.circle")
            }
        }
    }
}

struct MacCenteredState: View {
    let icon: String
    let title: String
    let message: String
    let isLoading: Bool
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            if isLoading {
                ProgressView()
                    .controlSize(.large)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 54, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.title2.weight(.semibold))
            if !message.isEmpty {
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: "arrow.clockwise")
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

private struct MacMasonryHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 1
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MacScrollOffsetObserver: NSViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attach(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onChange = onChange
        if context.coordinator.scrollView == nil {
            DispatchQueue.main.async {
                context.coordinator.attach(from: nsView)
            }
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject {
        var onChange: (CGFloat) -> Void
        weak var scrollView: NSScrollView?
        private var observer: NSObjectProtocol?

        init(onChange: @escaping (CGFloat) -> Void) {
            self.onChange = onChange
        }

        func attach(from view: NSView) {
            var current: NSView? = view
            while let candidate = current {
                if let scrollView = candidate as? NSScrollView {
                    attach(to: scrollView)
                    return
                }
                current = candidate.superview
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak view] in
                guard let self, let view, self.scrollView == nil else { return }
                self.attach(from: view)
            }
        }

        func detach() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            observer = nil
            scrollView = nil
        }

        private func attach(to scrollView: NSScrollView) {
            guard self.scrollView !== scrollView else { return }
            detach()
            self.scrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let self, let scrollView else { return }
                self.onChange(max(0, scrollView.contentView.bounds.origin.y))
            }
            onChange(max(0, scrollView.contentView.bounds.origin.y))
        }
    }
}
