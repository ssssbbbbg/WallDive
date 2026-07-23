import SwiftUI
import UIKit

struct IOSContentView: View {
    @StateObject private var model = IOSAppModel()
    @State private var showingDownloads = false
    @State private var selectedTab: IOSRootTab = .launchDefault
    @State private var lastHomeTap = Date.distantPast
#if DEBUG
    @State private var showingLaunchSettings = ProcessInfo.processInfo.arguments.contains("-showSettings")
#endif

	    var body: some View {
	        NavigationStack {
	            ZStack(alignment: .bottom) {
	                Color(.systemBackground).opacity(0.001)
	                    .ignoresSafeArea(.container, edges: [.top, .bottom])

	                IOSRootPager(selectedTab: $selectedTab) {
	                    IOSHomeRootView(model: model)
	                } following: {
	                    IOSFollowingRootView(model: model, selectedTab: $selectedTab)
                } me: {
                    IOSUserProfileView(model: model, profile: .me, showsSelectionDock: false)
                        .padding(.bottom, 104)
                }

                if model.isMultiSelecting {
                    IOSSelectionDownloadDock(
                        count: model.selectedWallpaperIDs.count,
                        language: model.languageMode,
                        downloadAction: {
                            model.downloadSelected()
                            model.exitMultiSelection()
                            showingDownloads = true
                        },
                        cancelAction: {
                            model.exitMultiSelection()
                        }
                    )
                    .padding(.horizontal, 38)
                    .padding(.bottom, selectedTab == .home ? 58 : 104)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
                }

                if !(selectedTab == .home && model.isMultiSelecting) {
                    IOSFloatingTabBar(
                        selectedTab: $selectedTab,
                        isHomeGalleryScrolling: selectedTab == .home && model.isHomeGalleryScrolling,
                        homeRefreshAnimationToken: model.homeRefreshAnimationToken
                    ) { tab in
                        handleTabSelection(tab)
                    }
                    .padding(.horizontal, 38)
                    .padding(.bottom, 58)
                    .transition(
                        .move(edge: .bottom)
                            .combined(with: .scale(scale: 0.82, anchor: .bottom))
                            .combined(with: .opacity)
                    )
                    .zIndex(2)
                }

	                IOSDownloadFeedbackOverlay(downloads: model.downloads)
	                    .padding(.top, 10)
	                    .zIndex(3)
	            }
	            .iosGlassHomeIndicatorArea()
	            .ignoresSafeArea(.container, edges: [.top, .bottom])
	            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .animation(IOSMotion.tabSwitch, value: selectedTab)
            .animation(IOSMotion.selection, value: model.isMultiSelecting)
            .sheet(isPresented: $showingDownloads) {
                IOSDownloadsView(downloads: model.downloads, language: model.languageMode)
                    .presentationCornerRadius(IOSDesign.cardCornerRadius)
            }
            .sheet(item: $model.selectedWallpaper) { wallpaper in
                IOSWallpaperDetailView(model: model, wallpaper: wallpaper) { _ in
                    moveToTab(.home)
                }
                .presentationCornerRadius(IOSDesign.cardCornerRadius)
            }
#if DEBUG
            .sheet(isPresented: $showingLaunchSettings) {
                IOSSettingsView(model: model)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(IOSDesign.cardCornerRadius)
            }
#endif
            .preferredColorScheme(model.themeMode.preferredColorScheme)
            .dismissKeyboardOnOutsideTap()
            .onChange(of: selectedTab) { _, tab in
                if tab != .home {
                    model.clearHomeGalleryScrolling()
                }
            }
            .onAppear {
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-forceCollapsedHeader") {
                    model.setHeaderCollapsed(true)
                }
#endif
            }
	        }
	        .ignoresSafeArea(.container, edges: [.top, .bottom])
	    }

    private func handleTabSelection(_ tab: IOSRootTab) {
        if tab == .home, selectedTab == .home {
            if model.isHomeGalleryScrolling {
                lastHomeTap = .distantPast
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                model.refreshCurrentSearch(showFeedback: true)
                return
            }

            let now = Date()
            if now.timeIntervalSince(lastHomeTap) < 0.45 {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                model.refreshCurrentSearch(showFeedback: true)
                lastHomeTap = .distantPast
            } else {
                lastHomeTap = now
            }
            return
        }

        moveToTab(tab)
        if tab == .home {
            lastHomeTap = Date()
        }
    }

	    private func moveToTab(_ tab: IOSRootTab) {
	        withAnimation(IOSMotion.tabSwitch) {
	            selectedTab = tab
	        }
	    }
	}

extension View {
    func iosGlassHomeIndicatorArea() -> some View {
        modifier(IOSGlassHomeIndicatorArea())
    }

    func dismissKeyboardOnOutsideTap() -> some View {
        background(IOSKeyboardDismissRecognizer())
    }
}

private struct IOSGlassHomeIndicatorArea: ViewModifier {
    func body(content: Content) -> some View {
        content
            .ignoresSafeArea(.container, edges: .bottom)
    }
}

private struct IOSKeyboardDismissRecognizer: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.attach(to: uiView.window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var window: UIWindow?
        private weak var recognizer: UITapGestureRecognizer?

        func attach(to window: UIWindow?) {
            guard self.window !== window else { return }
            if let recognizer {
                self.window?.removeGestureRecognizer(recognizer)
            }

            self.window = window
            guard let window else { return }

            let recognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)
            self.recognizer = recognizer
        }

        @objc private func dismissKeyboard() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView || current is UIControl {
                    return false
                }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

private struct IOSRootPager<Home: View, Following: View, Me: View>: View {
    @Binding var selectedTab: IOSRootTab
    @ViewBuilder let home: () -> Home
    @ViewBuilder let following: () -> Following
    @ViewBuilder let me: () -> Me

    var body: some View {
        TabView(selection: $selectedTab) {
            home()
                .tag(IOSRootTab.home)
            following()
                .tag(IOSRootTab.following)
            me()
                .tag(IOSRootTab.me)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(IOSMotion.tabSwitch, value: selectedTab)
        .ignoresSafeArea(.container, edges: .top)
    }
}

private struct IOSDownloadFeedbackOverlay: View {
    @ObservedObject var downloads: IOSDownloadManager

    var body: some View {
        VStack {
            if let feedback = downloads.feedback {
                HStack(spacing: 8) {
                    Image(systemName: feedback.state.systemImage)
                    Text(feedback.state.message)
                        .lineLimit(1)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(foregroundColor(for: feedback.state))
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    let id = feedback.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) {
                        downloads.clearFeedback(id: id)
                    }
                }
            }

            Spacer()
        }
        .animation(IOSMotion.quick, value: downloads.feedback)
    }

    private func foregroundColor(for state: IOSDownloadFeedback.State) -> Color {
        switch state {
        case .failed:
            return .red
        case .success, .already:
            return .green
        case .running:
            return .primary
        }
    }
}

private enum IOSRootTab: String, CaseIterable, Identifiable {
    case home
    case following
    case me

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .following: "Following"
        case .me: "Me"
        }
    }

    var icon: String {
        icon(isHomeGalleryScrolling: false)
    }

    func icon(isHomeGalleryScrolling: Bool) -> String {
        switch self {
        case .home: isHomeGalleryScrolling ? "arrow.clockwise" : "house.fill"
        case .following: "person.wave.2.fill"
        case .me: "person.crop.circle.fill"
        }
    }

    var sortIndex: Int {
        switch self {
        case .home: 0
        case .following: 1
        case .me: 2
        }
    }

    init?(index: Int) {
        switch index {
        case 0: self = .home
        case 1: self = .following
        case 2: self = .me
        default: return nil
        }
    }

    static var launchDefault: IOSRootTab {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-startTab"),
              arguments.indices.contains(index + 1) else {
            return .home
        }
        return IOSRootTab(rawValue: arguments[index + 1]) ?? .home
    }
}

private struct IOSFloatingTabBar: View {
    @Binding var selectedTab: IOSRootTab
    let isHomeGalleryScrolling: Bool
    let homeRefreshAnimationToken: Int
    let onSelect: (IOSRootTab) -> Void
    @Namespace private var selectionNamespace
    @State private var homeRefreshAngle: Double = 0
    @State private var isAnimatingHomeRefresh = false

    private var showsHomeRefresh: Bool {
        isHomeGalleryScrolling || isAnimatingHomeRefresh
    }

    var body: some View {
        HStack(spacing: 24) {
            ForEach(IOSRootTab.allCases) { tab in
                Button {
                    onSelect(tab)
                } label: {
                    ZStack {
                        if selectedTab == tab {
                            Circle()
                                .fill(.regularMaterial)
                                .matchedGeometryEffect(id: "selectedTab", in: selectionNamespace)
                                .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 6)
                        }

                        tabIcon(for: tab)
                    }
                    .frame(width: 56, height: 56, alignment: .center)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 24, x: 0, y: 10)
        .animation(IOSMotion.tabIndicator, value: selectedTab)
        .animation(IOSMotion.quick, value: isHomeGalleryScrolling)
        .onChange(of: homeRefreshAnimationToken) { _, token in
            isAnimatingHomeRefresh = true
            withAnimation(.linear(duration: 0.72)) {
                homeRefreshAngle += 360
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.74) {
                guard token == homeRefreshAnimationToken else { return }
                withAnimation(IOSMotion.quick) {
                    isAnimatingHomeRefresh = false
                }
            }
        }
    }

    @ViewBuilder
    private func tabIcon(for tab: IOSRootTab) -> some View {
        if tab == .home {
            ZStack {
                Image(systemName: "house.fill")
                    .opacity(showsHomeRefresh ? 0 : 1)
                    .scaleEffect(showsHomeRefresh ? 0.82 : 1)

                Image(systemName: "arrow.triangle.2.circlepath")
                    .frame(width: 28, height: 28, alignment: .center)
                    .rotationEffect(.degrees(homeRefreshAngle), anchor: .center)
                    .opacity(showsHomeRefresh ? 1 : 0)
                    .scaleEffect(showsHomeRefresh ? 1 : 0.82)
            }
            .animation(IOSMotion.quick, value: showsHomeRefresh)
            .font(.system(size: 25, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
            .frame(width: 56, height: 56, alignment: .center)
        } else {
            Image(systemName: tab.icon)
                .font(.system(size: 25, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                .frame(width: 56, height: 56, alignment: .center)
        }
    }
}

private struct IOSSelectionDownloadDock: View {
    let count: Int
    let language: IOSAppLanguage
    let downloadAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: cancelAction) {
                Image(systemName: "xmark")
                    .font(.headline.weight(.bold))
                    .frame(width: 42, height: 42)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)

            Button(action: downloadAction) {
                Label(
                    count > 0 ? String(format: IOSL10n.t("download_selected", language), "\(count)") : IOSL10n.t("select_images", language),
                    systemImage: "arrow.down.circle.fill"
                )
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(count > 0 ? Color.accentColor : Color.gray, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(count == 0)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 22, x: 0, y: 10)
    }
}

private struct IOSHomeRootView: View {
    @ObservedObject var model: IOSAppModel
    @State private var showingOrientationFilter = false

    var body: some View {
        ZStack(alignment: .top) {
            if model.isLoading && model.visibleWallpapers.isEmpty {
                ProgressView(model.t("loading"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 120)
            } else if model.visibleWallpapers.isEmpty {
                if model.galleryMode == .favorites {
                    IOSHomeEmptyScrollView {
                        ContentUnavailableView(model.t("no_favorites"), systemImage: "heart")
                    } refresh: {
                        withAnimation(IOSMotion.refresh) {
                            model.refreshCurrentSearch(showFeedback: true)
                        }
                    }
                } else {
                    IOSHomeEmptyScrollView {
                        ContentUnavailableView {
                            Label(model.networkUnavailable ? model.t("no_network") : model.t("no_wallpapers"), systemImage: model.networkUnavailable ? "wifi.exclamationmark" : "photo.stack")
                        } description: {
                            Text(model.errorMessage ?? model.t("try_another_keyword"))
                        } actions: {
                            Button {
                                withAnimation(IOSMotion.refresh) {
                                    model.refreshCurrentSearch(showFeedback: true)
                                }
                            } label: {
                                Label(model.t("reload"), systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } refresh: {
                        withAnimation(IOSMotion.refresh) {
                            model.refreshCurrentSearch(showFeedback: true)
                        }
                    }
                }
            } else {
                IOSMasonryGallery(model: model)
            }

            if showingOrientationFilter {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(IOSMotion.filterPanel) {
                            showingOrientationFilter = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
            }

            IOSHomeFloatingHeader(
                model: model,
                showingOrientationFilter: $showingOrientationFilter
            )
            .zIndex(2)

            if let feedback = model.homeRefreshFeedback {
                IOSHomeRefreshFeedbackToast(
                    feedback: feedback,
                    language: model.languageMode
                )
                .padding(.top, 76)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(3)
            }
        }
        .animation(IOSMotion.quick, value: model.homeRefreshFeedback)
        .onAppear {
            model.initialLoad()
        }
        .task {
            model.initialLoad()
        }
    }
}

private struct IOSHomeRefreshFeedbackToast: View {
    let feedback: IOSHomeRefreshFeedback
    let language: IOSAppLanguage

    var body: some View {
        HStack(spacing: 9) {
            switch feedback {
            case .refreshing:
                ProgressView()
                    .controlSize(.small)
                Text(IOSL10n.t("refreshing", language))
            case .success(let count):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(String(format: IOSL10n.t("refresh_complete", language), "\(count)"))
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text(IOSL10n.t("refresh_failed", language))
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 8)
    }
}

private struct IOSHomeEmptyScrollView<Content: View>: View {
    @ViewBuilder let content: () -> Content
    let refresh: () -> Void

    var body: some View {
        ScrollView {
            content()
                .frame(maxWidth: .infinity)
                .frame(minHeight: UIScreen.main.bounds.height * 0.72)
                .padding(.top, 120)
        }
        .refreshable {
            refresh()
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct IOSHomeFloatingHeader: View {
    @ObservedObject var model: IOSAppModel
    @Binding var showingOrientationFilter: Bool
    @FocusState private var isSearchFocused: Bool
    @State private var forceExpandedSearch = false

    private var collapseProgress: CGFloat {
        forceExpandedSearch || isSearchFocused ? 0 : model.headerCollapseProgress
    }

    var body: some View {
        GeometryReader { proxy in
            let progress = collapseProgress
            let horizontalPadding = lerp(14, 18, progress)
            let availableWidth = max(48, proxy.size.width - horizontalPadding * 2)
            let searchWidth = lerp(availableWidth, 48, progress)
            let searchHeight = lerp(52, 48, progress)

            ZStack(alignment: .topLeading) {
                expandedSearchIsland(progress: progress)
                    .frame(width: searchWidth, height: searchHeight, alignment: .leading)
                    .clipShape(Capsule(style: .continuous))
                    .opacity(1 - progress)
                    .allowsHitTesting(progress < 0.7)

                collapsedSearchButton
                    .opacity(progress)
                    .scaleEffect(lerp(0.86, 1, progress), anchor: .center)
                    .allowsHitTesting(progress > 0.7)
                    .onTapGesture {
                        expandAndFocus()
                    }

                orientationButton(size: 48, iconSize: 22)
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.12 * progress), radius: 18, x: 0, y: 8)
                    .opacity(progress)
                    .scaleEffect(lerp(0.82, 1, progress))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 10)
            .overlay(alignment: .topTrailing) {
                if showingOrientationFilter {
                    IOSFeedFilterPanel(model: model)
                        .frame(width: 286)
                        .padding(.top, 68)
                        .padding(.trailing, 18)
                        .transition(
                            .scale(scale: 0.06, anchor: .topTrailing)
                                .combined(with: .opacity)
                        )
                }
            }
        }
        .frame(height: 64)
        .animation(IOSMotion.header, value: forceExpandedSearch)
        .onChange(of: isSearchFocused) { _, focused in
            if !focused {
                withAnimation(IOSMotion.header) {
                    forceExpandedSearch = false
                }
            }
        }
    }

    private var collapsedSearchButton: some View {
        ZStack {
            Image(systemName: "magnifyingglass")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(width: 48, height: 48)
        .background(.ultraThinMaterial, in: Circle())
        .contentShape(Circle())
        .shadow(color: .black.opacity(0.08), radius: 22, x: 0, y: 8)
    }

    private func expandedSearchIsland(progress: CGFloat) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)

            TextField("", text: $model.filters.query)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    model.submitSearch()
                    if model.isHeaderCollapsed {
                        isSearchFocused = false
                        forceExpandedSearch = false
                    }
                }
                .frame(minWidth: 0)

            if !model.filters.query.isEmpty {
                Button {
                    model.filters.query = ""
                    model.submitSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            orientationButton(size: 34, iconSize: 20)
                .opacity(1 - progress)
        }
        .padding(.horizontal, 14)
        .frame(height: lerp(52, 48, progress))
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 22, x: 0, y: 8)
    }

    private func orientationButton(size: CGFloat, iconSize: CGFloat) -> some View {
        Button {
            isSearchFocused = false
            withAnimation(IOSMotion.filterPanel) {
                showingOrientationFilter.toggle()
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: iconSize, weight: .semibold))

                if model.filters.ratiosParameter != nil || model.filters.sorting != .dateAdded || model.filters.hasCategoryFilter {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .offset(x: 4, y: -2)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(model.t("menu"))
    }

    private func expandAndFocus() {
        withAnimation(IOSMotion.header) {
            forceExpandedSearch = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            isSearchFocused = true
        }
    }

    private func lerp(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
        start + (end - start) * min(max(progress, 0), 1)
    }

}

private struct IOSFeedFilterPanel: View {
    @ObservedObject var model: IOSAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.t("feed_mode"))
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 8)

            HStack(spacing: 8) {
                modeOption(.dateAdded, icon: "clock.fill")
                modeOption(.toplist, icon: "flame.fill")
                modeOption(.random, icon: "shuffle")
            }

            Divider()
                .padding(.horizontal, 8)
                .padding(.vertical, 2)

            Text(model.t("content_type"))
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 8)

            option(
                title: model.t("anime"),
                isSelected: model.filters.anime,
                isDisabled: model.filters.anime && !model.filters.photosEnabled
            ) {
                model.setContentCategoryFilters(
                    anime: !model.filters.anime,
                    photos: model.filters.photosEnabled
                )
            }

            option(
                title: model.t("photos"),
                isSelected: model.filters.photosEnabled,
                isDisabled: model.filters.photosEnabled && !model.filters.anime
            ) {
                model.setContentCategoryFilters(
                    anime: model.filters.anime,
                    photos: !model.filters.photosEnabled
                )
            }

            Divider()
                .padding(.horizontal, 8)
                .padding(.vertical, 2)

            Text(model.t("orientation"))
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 8)

            option(
                title: model.t("landscape_wallpapers"),
                isSelected: model.filters.landscape,
                isDisabled: model.filters.landscape && !model.filters.portrait
            ) {
                model.setOrientationFilters(
                    landscape: !model.filters.landscape,
                    portrait: model.filters.portrait
                )
            }

            option(
                title: model.t("portrait_wallpapers"),
                isSelected: model.filters.portrait,
                isDisabled: model.filters.portrait && !model.filters.landscape
            ) {
                model.setOrientationFilters(
                    landscape: model.filters.landscape,
                    portrait: !model.filters.portrait
                )
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: IOSDesign.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IOSDesign.cardCornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 12)
    }

    private func modeOption(_ sorting: IOSWallhavenSorting, icon: String) -> some View {
        let isSelected = model.filters.sorting == sorting

        return Button {
            model.setFeedSorting(sorting)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                }
                .frame(width: 42, height: 42)

                Text(sorting.title(language: model.languageMode))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func option(
        title: String,
        isSelected: Bool,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))

                Text(title)
                    .font(.subheadline.weight(.medium))

                Spacer(minLength: 0)
            }
            .frame(height: 42)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct IOSFollowingRootView: View {
    @ObservedObject var model: IOSAppModel
    @Binding var selectedTab: IOSRootTab

    private var subscriptionCount: Int {
        model.subscribedUsers.count + model.followedTags.count
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(model.t("your_subscriptions"))
                        .font(.largeTitle.weight(.bold))

                    Spacer(minLength: 12)

                    Text("\(subscriptionCount)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .background(.thinMaterial, in: Capsule(style: .continuous))
                }

                if subscriptionCount == 0 {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: UIScreen.main.bounds.height * 0.58)
                } else {
                    if !model.subscribedUsers.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionTitle(model.t("subscribed_users"), icon: "person.2.fill")

                            ForEach(model.subscribedUsers) { user in
                                NavigationLink {
                                    IOSUserProfileView(model: model, profile: .user(user))
                                } label: {
                                    HStack(spacing: 13) {
                                        IOSRemoteAvatarView(url: user.avatarURL, fallback: user.username, size: 50)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(user.username)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            if let group = user.group?.nilIfEmpty {
                                                Text(group)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }

                                        Spacer(minLength: 8)

                                        Image(systemName: "chevron.right")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(12)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: IOSDesign.cardCornerRadius, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: IOSDesign.cardCornerRadius, style: .continuous)
                                            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !model.followedTags.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionTitle(model.t("followed_tags"), icon: "tag.fill")

                            ForEach(model.followedTags) { tag in
                                NavigationLink {
                                    IOSTagFeedView(model: model, tagName: tag.name)
                                } label: {
                                    HStack(spacing: 13) {
                                        Image(systemName: "tag.fill")
                                            .font(.headline.weight(.semibold))
                                            .foregroundStyle(Color.accentColor)
                                            .frame(width: 46, height: 46)
                                            .background(Color.accentColor.opacity(0.12), in: Circle())

                                        Text(tag.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)

                                        Spacer(minLength: 8)

                                        Image(systemName: "chevron.right")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(12)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: IOSDesign.cardCornerRadius, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: IOSDesign.cardCornerRadius, style: .continuous)
                                            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 26)
            .padding(.bottom, 132)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemBackground).opacity(0.001).ignoresSafeArea(.container, edges: [.top, .bottom]))
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 82, height: 82)
                .background(.thinMaterial, in: Circle())

            Text(model.t("no_subscriptions"))
                .font(.title3.weight(.bold))

            Text(model.t("subscription_empty"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                withAnimation(IOSMotion.tabSwitch) {
                    selectedTab = .home
                }
            } label: {
                Label(model.t("discover"), systemImage: "magnifyingglass")
                    .font(.headline.weight(.semibold))
                    .padding(.horizontal, 24)
                    .frame(height: 50)
                    .background(Color.accentColor, in: Capsule(style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
    }
}

private struct IOSHeaderView: View {
    @ObservedObject var model: IOSAppModel
    @Binding var showingDownloads: Bool

    var body: some View {
        VStack(spacing: model.isHeaderCollapsed ? 6 : 10) {
            if model.isHeaderCollapsed || model.galleryMode == .favorites {
                compactHeader
            } else {
                expandedHeader
            }

            if model.isMultiSelecting {
                IOSBatchBar(model: model, showingDownloads: $showingDownloads)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack {
                Text(model.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingDownloads = true
                } label: {
                    Label("\(model.downloads.activeCount)", systemImage: "arrow.down.circle")
                        .labelStyle(.titleAndIcon)
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, model.isHeaderCollapsed ? 6 : 10)
        .background(.bar)
        .onChange(of: model.filters.general) { _, _ in model.refreshCurrentSearch() }
        .onChange(of: model.filters.anime) { _, _ in model.refreshCurrentSearch() }
        .onChange(of: model.filters.people) { _, _ in model.refreshCurrentSearch() }
        .onChange(of: model.filters.sfw) { _, _ in model.refreshCurrentSearch() }
        .onChange(of: model.filters.sketchy) { _, _ in model.refreshCurrentSearch() }
        .onChange(of: model.filters.nsfw) { _, _ in model.refreshCurrentSearch() }
        .onChange(of: model.filters.sorting) { _, _ in model.refreshCurrentSearch() }
        .onChange(of: model.filters.order) { _, _ in model.refreshCurrentSearch() }
    }

    private var compactHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text(model.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if model.galleryMode != .favorites {
                Button {
                    model.refreshCurrentSearch()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var expandedHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("", text: $model.filters.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit {
                        model.submitSearch()
                    }

                if !model.filters.query.isEmpty {
                    Button {
                        model.filters.query = ""
                        model.submitSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: IOSDesign.cardCornerRadius, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    IOSPillToggle(title: model.t("general"), isOn: $model.filters.general)
                    IOSPillToggle(title: model.t("anime"), isOn: $model.filters.anime)
                    IOSPillToggle(title: model.t("people"), isOn: $model.filters.people)
                    IOSPillToggle(title: model.t("safe"), isOn: $model.filters.sfw)
                    IOSPillToggle(title: model.t("sketchy"), isOn: $model.filters.sketchy)
                    IOSPillToggle(title: model.t("restricted"), isOn: $model.filters.nsfw)
                        .disabled(!model.canUseNSFW)
                        .opacity(model.canUseNSFW ? 1 : 0.45)
                }
            }

            HStack(spacing: 8) {
                Picker(model.t("sort"), selection: $model.filters.sorting) {
                    ForEach(IOSWallhavenSorting.allCases) { sorting in
                        Text(sorting.title(language: model.languageMode)).tag(sorting)
                    }
                }
                .pickerStyle(.menu)

                Picker(model.t("order"), selection: $model.filters.order) {
                    ForEach(IOSWallhavenOrder.allCases) { order in
                        Text(order.title(language: model.languageMode)).tag(order)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    model.refreshCurrentSearch()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct IOSBatchBar: View {
    @ObservedObject var model: IOSAppModel
    @Binding var showingDownloads: Bool

    var body: some View {
        HStack(spacing: 8) {
            Label("\(model.selectedWallpaperIDs.count)", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.semibold))
                .monospacedDigit()

            Spacer()

            Button(model.t("select_all")) {
                model.selectAllLoadedWallpapers()
            }
            .disabled(model.visibleWallpapers.isEmpty)

            Button(model.t("clear_selection")) {
                model.clearWallpaperSelection()
            }
            .disabled(model.selectedWallpaperIDs.isEmpty)

            Button {
                model.downloadSelected()
                showingDownloads = true
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .disabled(model.selectedLoadedWallpapers.isEmpty)

            Button(model.t("done")) {
                model.exitMultiSelection()
            }
        }
        .font(.footnote)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: IOSDesign.cardCornerRadius, style: .continuous))
    }
}

private struct IOSPillToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isOn ? .white : .primary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(isOn ? Color.accentColor : Color(.secondarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct IOSMasonryGallery: View {
    @ObservedObject var model: IOSAppModel
    private let spacing: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let items = model.visibleWallpapers
            let layout = makeLayout(width: proxy.size.width, wallpapers: items)

            ScrollView {
                IOSScrollViewOffsetObserver(restoreOffsetY: model.homeScrollOffsetY) { contentOffsetY, deltaY in
                    model.rememberHomeScrollOffset(contentOffsetY)
                    updateHeaderState(contentOffsetY: contentOffsetY, deltaY: deltaY)
                    loadMoreIfNeeded(
                        contentOffsetY: contentOffsetY,
                        viewportHeight: proxy.size.height,
                        contentHeight: layout.contentHeight
                    )
                }
                .frame(width: 0, height: 0)

                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(layout.columns.enumerated()), id: \.offset) { _, column in
                        LazyVStack(spacing: spacing) {
                            ForEach(column) { wallpaper in
                                IOSWallpaperCard(
                                    wallpaper: wallpaper,
                                    imageURL: wallpaper.gridPreviewURL,
                                    maxPixelSize: 1200,
                                    isDownloaded: model.downloads.isDownloaded(wallpaper),
                                    isDownloading: model.downloads.isDownloading(wallpaper),
                                    isSelectionMode: model.isMultiSelecting,
                                    isSelected: model.selectedWallpaperIDs.contains(wallpaper.id),
                                    language: model.languageMode,
                                    downloadAction: { model.download(wallpaper) }
                                )
                                .id(wallpaper.id)
                                .onTapGesture {
                                    if model.isMultiSelecting {
                                        model.toggleWallpaperSelection(wallpaper)
                                    } else {
                                        model.select(wallpaper)
                                    }
                                }
                                .onLongPressGesture(minimumDuration: 0.35) {
                                    model.beginMultiSelection(with: wallpaper)
                                }
                            }
                            .frame(width: layout.columnWidth)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 92)

                if model.isLoading {
                    ProgressView(model.t("refreshing"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 18)
                } else if model.isLoadingMore {
                    ProgressView()
                        .padding(.vertical, 18)
                } else if model.canLoadMore {
                    Button {
                        model.loadMore()
                    } label: {
                        Text(model.t("continue_load_more"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Color.clear.frame(height: 112)
            }
            .refreshable {
                model.setHeaderCollapseProgress(0, animated: true)
                model.refreshCurrentSearch(showFeedback: true)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                loadMoreIfNeeded(
                    contentOffsetY: model.homeScrollOffsetY,
                    viewportHeight: proxy.size.height,
                    contentHeight: layout.contentHeight
                )
            }
            .onChange(of: items.count) { _, _ in
                DispatchQueue.main.async {
                    loadMoreIfNeeded(
                        contentOffsetY: model.homeScrollOffsetY,
                        viewportHeight: proxy.size.height,
                        contentHeight: layout.contentHeight
                    )
                }
            }
            .onDisappear {
                model.clearHomeGalleryScrolling()
            }
        }
    }

    private func updateHeaderState(contentOffsetY: CGFloat, deltaY _: CGFloat) {
        if contentOffsetY <= 1 {
            model.setHeaderCollapseProgress(0)
            return
        }

        model.markHomeGalleryScrolling()
        model.setHeaderCollapseProgress(min(max(contentOffsetY / 44, 0), 1))
    }

    private func loadMoreIfNeeded(
        contentOffsetY: CGFloat,
        viewportHeight: CGFloat,
        contentHeight: CGFloat
    ) {
        guard model.canLoadMore, !model.isLoading, !model.isLoadingMore else { return }
        let preloadDistance = max(320, viewportHeight * 0.42)
        let visualBottom = 92 + contentHeight
        guard contentOffsetY + viewportHeight >= visualBottom - preloadDistance else { return }
        model.loadMore()
    }

    private func makeLayout(width: CGFloat, wallpapers: [IOSWallpaper]) -> IOSMasonryLayout {
        let columnCount = max(2, min(Int(width / 180), 3))
        let availableWidth = width - 20
        let columnWidth = (availableWidth - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
        var columns = Array(repeating: [IOSWallpaper](), count: columnCount)
        var heights = Array(repeating: CGFloat.zero, count: columnCount)

        for wallpaper in wallpapers {
            let target = heights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            columns[target].append(wallpaper)
            heights[target] += columnWidth / max(wallpaper.previewAspectRatio, 0.35) + spacing
        }

        return IOSMasonryLayout(columns: columns, columnWidth: columnWidth, contentHeight: heights.max() ?? 0)
    }
}

private struct IOSScrollViewOffsetObserver: UIViewRepresentable {
    let restoreOffsetY: CGFloat
    let onChange: (CGFloat, CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(restoreOffsetY: restoreOffsetY, onChange: onChange)
    }

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: ObserverView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.restoreOffsetY = restoreOffsetY
        uiView.coordinator = context.coordinator
        uiView.attachWhenReady()
    }

    final class ObserverView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attachWhenReady()
        }

        func attachWhenReady() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.coordinator?.attach(to: self.enclosingScrollView)
            }
        }

        private var enclosingScrollView: UIScrollView? {
            var view = superview
            while let current = view {
                if let scrollView = current as? UIScrollView {
                    return scrollView
                }
                view = current.superview
            }
            return nil
        }
    }

    final class Coordinator: NSObject {
        var restoreOffsetY: CGFloat
        var onChange: (CGFloat, CGFloat) -> Void
        private weak var scrollView: UIScrollView?
        private var contentOffsetObservation: NSKeyValueObservation?
        private var lastContentOffsetY: CGFloat?
        private var didRestoreOffset = false

        init(restoreOffsetY: CGFloat, onChange: @escaping (CGFloat, CGFloat) -> Void) {
            self.restoreOffsetY = restoreOffsetY
            self.onChange = onChange
        }

        func attach(to scrollView: UIScrollView?) {
            guard self.scrollView !== scrollView else { return }
            contentOffsetObservation = nil
            self.scrollView = scrollView
            lastContentOffsetY = scrollView?.contentOffset.y
            didRestoreOffset = false

            contentOffsetObservation = scrollView?.observe(\.contentOffset, options: [.new]) { [weak self, weak scrollView] _, _ in
                guard let self, let scrollView else { return }
                let offsetY = scrollView.contentOffset.y
                let previous = self.lastContentOffsetY ?? offsetY
                self.lastContentOffsetY = offsetY
                let deltaY = offsetY - previous
                DispatchQueue.main.async {
                    self.onChange(offsetY, deltaY)
                }
            }

            restoreOffsetWhenReady(attempt: 0)
        }

        private func restoreOffsetWhenReady(attempt: Int) {
            guard !didRestoreOffset, let scrollView else { return }
            guard restoreOffsetY > 8 else {
                didRestoreOffset = true
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.06 : 0.12)) { [weak self, weak scrollView] in
                guard let self, let scrollView, !self.didRestoreOffset else { return }
                let minimumY = -scrollView.adjustedContentInset.top
                let maximumY = max(
                    minimumY,
                    scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
                )

                if maximumY + 1 < self.restoreOffsetY, attempt < 4 {
                    self.restoreOffsetWhenReady(attempt: attempt + 1)
                    return
                }

                let targetY = min(max(self.restoreOffsetY, minimumY), maximumY)
                scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: targetY), animated: false)
                self.lastContentOffsetY = targetY
                self.didRestoreOffset = true
            }
        }
    }
}

private struct IOSMasonryLayout {
    let columns: [[IOSWallpaper]]
    let columnWidth: CGFloat
    let contentHeight: CGFloat
}

private struct IOSWallpaperCard: View {
    let wallpaper: IOSWallpaper
    var imageURL: URL? = nil
    var maxPixelSize: CGFloat = 1200
    let isDownloaded: Bool
    let isDownloading: Bool
    let isSelectionMode: Bool
    let isSelected: Bool
    let language: IOSAppLanguage
    let downloadAction: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Rectangle()
                .fill(Color(.secondarySystemBackground))

            IOSCachedRemoteImage(url: imageURL ?? wallpaper.gridPreviewURL, contentMode: .fit, maxPixelSize: maxPixelSize) {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

        }
        .aspectRatio(wallpaper.previewAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: IOSDesign.imagePreviewCornerRadius, style: .continuous))
        .overlay(alignment: .topLeading) {
            if isDownloaded || isDownloading {
                Label(isDownloaded ? IOSL10n.t("downloaded", language) : IOSL10n.t("downloading", language), systemImage: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background((isDownloaded ? Color.green : Color.accentColor).opacity(0.92), in: Capsule())
                    .padding(8)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2.weight(.semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.95), isSelected ? Color.accentColor : .black.opacity(0.35))
                    .padding(8)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: IOSDesign.imagePreviewCornerRadius, style: .continuous)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
        }
    }
}

private struct IOSWallpaperDetailView: View {
    @ObservedObject var model: IOSAppModel
    let wallpaper: IOSWallpaper
    var onOpenTag: (IOSWallpaperTag) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var loadedWallpaper: IOSWallpaper?
    @State private var showingImmersiveViewer = false

    private var activeWallpaper: IOSWallpaper {
        if let loadedWallpaper {
            return loadedWallpaper
        }
        if let selected = model.selectedWallpaper, selected.id == wallpaper.id {
            return selected
        }
        return wallpaper
    }

    var body: some View {
        let item = activeWallpaper

        NavigationStack {
            ZStack(alignment: .top) {
                Color(.systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        IOSCachedRemoteImage(url: item.detailPreviewURL, contentMode: .fit, maxPixelSize: 2800) {
                            ZStack {
                                Color(.secondarySystemBackground)
                                ProgressView()
                            }
                            .frame(maxWidth: .infinity, minHeight: 300)
                        }
                        .frame(maxWidth: .infinity)
                        .aspectRatio(item.previewAspectRatio, contentMode: .fit)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: IOSDesign.imagePreviewCornerRadius, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showingImmersiveViewer = true
                        }
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial, in: Circle())
                                .padding(10)
                                .allowsHitTesting(false)
                        }

                        IOSWallpaperMetadataStrip(model: model, wallpaper: item)

                        if let uploader = item.uploader {
                            IOSUploaderRow(model: model, uploader: uploader)
                        }

                        if !item.tags.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(model.t("tags"))
                                    .font(.headline)
                                FlowTags(model: model, tags: item.tags)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 74)
                    .padding(.bottom, 34)
                }

                HStack(spacing: 10) {
                    Button {
                        model.selectedWallpaper = nil
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        model.toggleFavorite(item)
                    } label: {
                        Image(systemName: model.isFavorite(item) ? "heart.fill" : "heart")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(model.isFavorite(item) ? Color.red : Color.primary)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.download(item)
                    } label: {
                        Group {
                            if model.downloads.isDownloading(item) {
                                ProgressView()
                            } else {
                                Image(systemName: model.downloads.isDownloaded(item) ? "checkmark" : "arrow.down")
                                    .font(.headline.weight(.bold))
                                    .contentTransition(.symbolEffect(.replace))
                            }
                        }
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.downloads.isDownloaded(item) || model.downloads.isDownloading(item))
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .task(id: wallpaper.id) {
                let current = activeWallpaper
                guard current.tags.isEmpty || current.uploader == nil else { return }
                loadedWallpaper = await model.loadDetail(for: wallpaper)
            }
            .fullScreenCover(isPresented: $showingImmersiveViewer) {
                IOSImmersiveWallpaperView(wallpaper: activeWallpaper)
            }
            .iosGlassHomeIndicatorArea()
        }
    }
}

private struct IOSWallpaperMetadataStrip: View {
    @ObservedObject var model: IOSAppModel
    let wallpaper: IOSWallpaper

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                metric(wallpaper.resolution, icon: "aspectratio")
                metric(wallpaper.displayCategory(language: model.languageMode), icon: "photo")
                metric(wallpaper.displayPurity(language: model.languageMode), icon: "shield")
            }

            VStack(alignment: .leading, spacing: 8) {
                metric(wallpaper.resolution, icon: "aspectratio")
                HStack(spacing: 8) {
                    metric(wallpaper.displayCategory(language: model.languageMode), icon: "photo")
                    metric(wallpaper.displayPurity(language: model.languageMode), icon: "shield")
                }
            }
        }
    }

    private func metric(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Color(.secondarySystemFill), in: Capsule(style: .continuous))
    }
}

private struct IOSImmersiveWallpaperView: View {
    let wallpaper: IOSWallpaper
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            IOSZoomableRemoteImage(
                url: wallpaper.detailPreviewURL,
                maxPixelSize: 4200
            ) {
                dismiss()
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}

private struct IOSUploaderRow: View {
    @ObservedObject var model: IOSAppModel
    let uploader: IOSWallhavenUploader

    private var subscribedUser: IOSSubscribedUser {
        IOSSubscribedUser(uploader: uploader)
    }

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink {
                IOSUserProfileView(model: model, profile: .user(subscribedUser))
            } label: {
                HStack(spacing: 12) {
                    IOSRemoteAvatarView(url: uploader.bestAvatarURL, fallback: uploader.username, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(uploader.username)
                            .font(.headline)
                        if let group = uploader.group {
                            Text(group)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                model.toggleSubscription(subscribedUser)
            } label: {
                Label(
                    model.t(model.isSubscribed(username: uploader.username) ? "subscribed" : "subscribe"),
                    systemImage: model.isSubscribed(username: uploader.username) ? "checkmark" : "plus"
                )
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(model.isSubscribed(username: uploader.username) ? .secondary : .accentColor)
            .animation(.easeInOut(duration: 0.2), value: model.isSubscribed(username: uploader.username))
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: IOSDesign.cardCornerRadius, style: .continuous))
    }

}

private struct IOSTagFeedView: View {
    @ObservedObject var model: IOSAppModel
    let tagName: String
    @StateObject private var feed = IOSTagFeedModel()
    @State private var showingDownloads = false
    @State private var detailWallpaper: IOSWallpaper?

    private var cleanTagName: String {
        tagName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            if feed.isLoading && feed.wallpapers.isEmpty {
                ProgressView(model.t("loading"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if feed.wallpapers.isEmpty {
                ScrollView {
                    ContentUnavailableView {
                        Label(feed.networkUnavailable ? model.t("no_network") : model.t("no_wallpapers"), systemImage: feed.networkUnavailable ? "wifi.exclamationmark" : "photo.stack")
                    } description: {
                        Text(feed.networkUnavailable ? model.t("network_unavailable_message") : (feed.errorMessage ?? model.t("empty_tag_result")))
                    } actions: {
                        Button {
                            feed.refresh(apiKey: model.apiKey, includeAdultContent: model.effectiveAdultContentEnabled, language: model.languageMode)
                        } label: {
                            Label(model.t("reload"), systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                .frame(maxWidth: .infinity)
                .frame(minHeight: UIScreen.main.bounds.height * 0.68)
            }
            .refreshable {
                feed.refresh(apiKey: model.apiKey, includeAdultContent: model.effectiveAdultContentEnabled, language: model.languageMode)
            }
            .scrollDismissesKeyboard(.interactively)
            } else {
                IOSTagMasonryGallery(
                    model: model,
                    feed: feed,
                    detailWallpaper: $detailWallpaper
                )
            }
        }
        .navigationTitle("#\(cleanTagName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingDownloads = true
                } label: {
                    Image(systemName: "arrow.down.circle")
                }

                Button {
                    model.toggleFollowedTag(cleanTagName)
                } label: {
                    Image(systemName: model.isFollowingTag(cleanTagName) ? "bell.fill" : "bell")
                }
            }
        }
        .task(id: "\(cleanTagName)-\(model.apiKey)-\(model.effectiveAdultContentEnabled)") {
            await feed.load(tagName: cleanTagName, apiKey: model.apiKey, includeAdultContent: model.effectiveAdultContentEnabled, language: model.languageMode)
        }
        .safeAreaInset(edge: .bottom) {
            if model.isMultiSelecting {
                IOSSelectionDownloadDock(
                    count: model.selectedWallpaperIDs.count,
                    language: model.languageMode,
                    downloadAction: {
                        model.downloadSelected()
                        model.exitMultiSelection()
                        showingDownloads = true
                    },
                    cancelAction: {
                        model.exitMultiSelection()
                    }
                )
                .padding(.horizontal, 38)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showingDownloads) {
            IOSDownloadsView(downloads: model.downloads, language: model.languageMode)
                .presentationCornerRadius(IOSDesign.cardCornerRadius)
        }
        .sheet(item: $detailWallpaper) { wallpaper in
            IOSWallpaperDetailView(model: model, wallpaper: wallpaper)
                .presentationCornerRadius(IOSDesign.cardCornerRadius)
        }
	        .overlay(alignment: .top) {
	            IOSDownloadFeedbackOverlay(downloads: model.downloads)
	                .padding(.top, 8)
	        }
	        .iosGlassHomeIndicatorArea()
	    }
	}

private struct IOSTagMasonryGallery: View {
    @ObservedObject var model: IOSAppModel
    @ObservedObject var feed: IOSTagFeedModel
    @Binding var detailWallpaper: IOSWallpaper?
    private let spacing: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let items = feed.wallpapers
            let layout = makeLayout(width: proxy.size.width, wallpapers: items)

            ScrollView {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(layout.columns.enumerated()), id: \.offset) { _, column in
                        LazyVStack(spacing: spacing) {
                            ForEach(column) { wallpaper in
                                IOSWallpaperCard(
                                    wallpaper: wallpaper,
                                    imageURL: wallpaper.gridPreviewURL,
                                    maxPixelSize: 1200,
                                    isDownloaded: model.downloads.isDownloaded(wallpaper),
                                    isDownloading: model.downloads.isDownloading(wallpaper),
                                    isSelectionMode: model.isMultiSelecting,
                                    isSelected: model.selectedWallpaperIDs.contains(wallpaper.id),
                                    language: model.languageMode,
                                    downloadAction: { model.download(wallpaper) }
                                )
                                .frame(width: layout.columnWidth)
                                .onTapGesture {
                                    if model.isMultiSelecting {
                                        model.toggleWallpaperSelection(wallpaper)
                                    } else {
                                        detailWallpaper = wallpaper
                                    }
                                }
                                .onLongPressGesture(minimumDuration: 0.35) {
                                    model.beginMultiSelection(with: wallpaper)
                                }
                                .onAppear {
                                    if wallpaper.id == items.suffix(6).first?.id {
                                        feed.loadMore(apiKey: model.apiKey, includeAdultContent: model.effectiveAdultContentEnabled, language: model.languageMode)
	            }
	        }
	        .iosGlassHomeIndicatorArea()
	    }
	}
                        .frame(width: layout.columnWidth)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 12)

                if feed.isLoading {
                    ProgressView(model.t("refreshing"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 18)
                } else if feed.isLoadingMore {
                    ProgressView()
                        .padding(.vertical, 18)
                } else if feed.canLoadMore {
                    Text(model.t("continue_load_more"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 18)
                }

                Color.clear.frame(height: 112)
            }
            .refreshable {
                feed.refresh(apiKey: model.apiKey, includeAdultContent: model.effectiveAdultContentEnabled, language: model.languageMode)
            }
            .scrollDismissesKeyboard(.interactively)
            .animation(IOSMotion.contentUpdate, value: feed.wallpapers.count)
        }
    }

    private func makeLayout(width: CGFloat, wallpapers: [IOSWallpaper]) -> IOSMasonryLayout {
        let columnCount = max(2, min(Int(width / 180), 3))
        let horizontalPadding: CGFloat = 20
        let availableWidth = width - horizontalPadding
        let columnWidth = (availableWidth - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
        var columns = Array(repeating: [IOSWallpaper](), count: columnCount)
        var heights = Array(repeating: CGFloat.zero, count: columnCount)

        for wallpaper in wallpapers {
            let target = heights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            columns[target].append(wallpaper)
            heights[target] += columnWidth / max(wallpaper.previewAspectRatio, 0.35) + spacing
        }

        return IOSMasonryLayout(columns: columns, columnWidth: columnWidth, contentHeight: heights.max() ?? 0)
    }
}

@MainActor
private final class IOSTagFeedModel: ObservableObject {
    @Published private(set) var wallpapers: [IOSWallpaper] = []
    @Published private(set) var meta: IOSSearchMeta?
    @Published var errorMessage: String?
    @Published var networkUnavailable = false
    @Published var isLoading = false
    @Published var isLoadingMore = false

    private let api = IOSWallhavenAPI()
    private var tagName = ""
    private var loadTask: Task<Void, Never>?

    var canLoadMore: Bool {
        guard !wallpapers.isEmpty else { return false }
        guard let meta else { return false }
        return meta.currentPage < meta.lastPage
    }

    func load(tagName: String, apiKey: String, includeAdultContent: Bool, language: IOSAppLanguage) async {
        let trimmed = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.tagName = trimmed
        fetch(page: 1, reset: true, apiKey: apiKey, includeAdultContent: includeAdultContent, language: language)
    }

    func refresh(apiKey: String, includeAdultContent: Bool, language: IOSAppLanguage) {
        fetch(page: 1, reset: true, apiKey: apiKey, includeAdultContent: includeAdultContent, language: language)
    }

    func loadMore(apiKey: String, includeAdultContent: Bool, language: IOSAppLanguage) {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }
        fetch(page: (meta?.currentPage ?? 0) + 1, reset: false, apiKey: apiKey, includeAdultContent: includeAdultContent, language: language)
    }

    private func fetch(page: Int, reset: Bool, apiKey: String, includeAdultContent: Bool, language: IOSAppLanguage) {
        guard !tagName.isEmpty else { return }
        if reset {
            loadTask?.cancel()
            isLoading = true
            isLoadingMore = false
            if wallpapers.isEmpty {
                networkUnavailable = false
            }
        } else {
            isLoadingMore = true
        }

        errorMessage = nil
        let tagName = tagName

        loadTask = Task {
            do {
                var filters = IOSSearchFilters()
                filters.query = tagName
                filters.sfw = true
                filters.sketchy = includeAdultContent
                filters.nsfw = includeAdultContent
                let requestAPIKey = includeAdultContent ? apiKey.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty : nil
                let result = try await api.searchWithFallback(filters: filters, page: page, apiKey: requestAPIKey)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.meta = result.meta
                    self.isLoading = false
                    self.isLoadingMore = false
                    self.networkUnavailable = false
                    if reset {
                        var seen = Set<String>()
                        self.wallpapers = result.data.filter { wallpaper in
                            seen.insert(wallpaper.id).inserted
                        }
                        if result.data.isEmpty {
                            self.errorMessage = nil
                        }
                    } else {
                        let existing = Set(self.wallpapers.map(\.id))
                        self.wallpapers.append(contentsOf: result.data.filter { !existing.contains($0.id) })
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isLoading = false
                    self.isLoadingMore = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.isLoadingMore = false
                    if reset, self.wallpapers.isEmpty {
                        self.meta = nil
                    }
                    self.networkUnavailable = IOSIsNetworkUnavailable(error)
                    self.errorMessage = IOSDisplayMessage(for: error, language: language)
                }
            }
        }
    }
}

private struct FlowTags: View {
    @ObservedObject var model: IOSAppModel
    let tags: [IOSWallpaperTag]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(tags.prefix(24)) { tag in
                HStack(spacing: 6) {
                    NavigationLink {
                        IOSTagFeedView(model: model, tagName: tag.name)
                    } label: {
                        Text(tag.name)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    Button {
                        model.toggleFollowedTag(tag.name)
                    } label: {
                        Image(systemName: model.isFollowingTag(tag.name) ? "bell.fill" : "bell")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Color(.secondarySystemFill), in: Capsule())
            }
        }
    }
}

private struct IOSLibraryMenuView: View {
    @ObservedObject var model: IOSAppModel
    @Binding var showingDownloads: Bool
    @Environment(\.dismiss) private var dismiss

	    var body: some View {
	        NavigationStack {
	            List {
	                Section {
	                    NavigationLink {
                        IOSUserProfileView(model: model, profile: .me)
                    } label: {
                        HStack(spacing: 12) {
                            IOSLocalAvatarView(model: model, size: 46)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(model.displayName)
                                    .font(.headline)
                                Text(model.t("online"))
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        model.openMyUploads()
                        dismiss()
                    } label: {
                        Label(model.t("my_uploads"), systemImage: "square.and.arrow.up")
                    }

                    Button {
                        model.openFavorites()
                        dismiss()
                    } label: {
                        Label(model.t("favorites"), systemImage: "heart")
                    }

                    NavigationLink {
                        IOSSubscriptionsView(model: model)
                    } label: {
                        Label(model.t("subscriptions"), systemImage: "person.2")
                    }

                    NavigationLink {
                        IOSTagCenterView(model: model)
                    } label: {
                        Label(model.t("tags"), systemImage: "tag")
                    }

                    Button {
                        dismiss()
                        showingDownloads = true
                    } label: {
	                        Label(model.t("download_queue"), systemImage: "arrow.down.circle")
	                    }
	                }
	            }
	            .scrollContentBackground(.hidden)
	            .scrollDismissesKeyboard(.interactively)
	            .navigationTitle(model.t("menu"))
	            .navigationBarTitleDisplayMode(.inline)
	            .toolbar {
	                ToolbarItem(placement: .topBarTrailing) {
	                    Button(model.t("done")) {
	                        dismiss()
	                    }
	                }
	            }
	            .iosGlassHomeIndicatorArea()
	        }
	    }
	}

private enum IOSProfileKind: Hashable {
    case me
    case user(IOSSubscribedUser)

    var username: String {
        switch self {
        case .me: ""
        case .user(let user): user.username
        }
    }
}

private enum IOSProfileTab: String, CaseIterable, Identifiable {
    case uploads
    case favorites
    case comments

    var id: String { rawValue }

    func title(language: IOSAppLanguage) -> String {
        switch self {
        case .uploads:
            IOSL10n.t("uploads", language)
        case .favorites:
            IOSL10n.t("favorites", language)
        case .comments:
            IOSL10n.t("profile_comments", language)
        }
    }
}

private struct IOSUserProfileView: View {
    @ObservedObject var model: IOSAppModel
    let profile: IOSProfileKind
    var showsSelectionDock = true
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: IOSProfileTab = .uploads
    @State private var showingSettings = false
    @State private var showingDownloads = false
    @StateObject private var profileData = IOSUserProfileDataModel()

    private var isMe: Bool {
        if case .me = profile { return true }
        return false
    }

    private var availableTabs: [IOSProfileTab] {
        isMe ? IOSProfileTab.allCases : [.uploads, .comments]
    }

    private var username: String {
        switch profile {
        case .me: model.displayName
        case .user(let user): user.username
        }
    }

    private var remoteAvatarURL: URL? {
        if let avatarURL = profileData.profile?.avatarURL {
            return avatarURL
        }
        if case .user(let user) = profile {
            return user.avatarURL
        }
        return nil
    }

    var body: some View {
        ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        if isMe {
                            Button {
                                showingSettings = true
                            } label: {
                                if model.avatarImageData != nil {
                                    IOSLocalAvatarView(model: model, size: 86)
                                } else {
                                    IOSRemoteAvatarView(url: remoteAvatarURL, fallback: username, size: 86)
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            IOSRemoteAvatarView(url: remoteAvatarURL, fallback: username, size: 86)
                        }

                    Text(username)
                        .font(.title2.weight(.bold))

                    if isMe {
                        Button {
                            openURL(URL(string: "https://wallhaven.cc/upload")!)
                        } label: {
                            Text(model.t("publish"))
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                    } else if case .user(let user) = profile {
                        Button {
                            model.toggleSubscription(
                                IOSSubscribedUser(
                                    username: user.username,
                                    group: user.group,
                                    avatarURL: remoteAvatarURL ?? user.avatarURL
                                )
                            )
                        } label: {
                            Label(
                                model.t(model.isSubscribed(username: user.username) ? "subscribed" : "subscribe"),
                                systemImage: model.isSubscribed(username: user.username) ? "checkmark" : "plus"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(model.isSubscribed(username: user.username) ? .secondary : .accentColor)
                        .animation(.easeInOut(duration: 0.2), value: model.isSubscribed(username: user.username))
                    }

                    if let profile = profileData.profile {
                        IOSProfileStatsView(profile: profile, language: model.languageMode)
                            .padding(.top, 4)
                    } else if profileData.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.top, 4)
                    } else if let errorMessage = profileData.errorMessage {
                        Button {
                            profileData.reload(username: username, language: model.languageMode)
                        } label: {
                            Label(errorMessage, systemImage: profileData.networkUnavailable ? "wifi.exclamationmark" : "arrow.clockwise")
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)

                Picker(model.t("profile_home"), selection: $tab) {
                    ForEach(availableTabs) { tab in
                        Text(tab.title(language: model.languageMode)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Group {
                    switch tab {
                    case .uploads:
                        IOSProfileUploadFeed(model: model, username: username)
                    case .favorites:
                        IOSProfileFavoritesGrid(model: model, username: isMe ? nil : username)
                    case .comments:
                        IOSProfileCommentsView(
                            comments: profileData.profile?.comments ?? [],
                            isLoading: profileData.isLoading,
                            language: model.languageMode,
                            writeAction: {
                                openURL(wallhavenProfileURL.appending(fragment: "comments"))
                            }
                        )
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if showsSelectionDock, model.isMultiSelecting {
                IOSSelectionDownloadDock(
                    count: model.selectedWallpaperIDs.count,
                    language: model.languageMode,
                    downloadAction: {
                        model.downloadSelected()
                        model.exitMultiSelection()
                        showingDownloads = true
                    },
                    cancelAction: {
                        model.exitMultiSelection()
                    }
                )
                .padding(.horizontal, 38)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showingSettings) {
            IOSSettingsView(model: model)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(IOSDesign.cardCornerRadius)
        }
        .sheet(isPresented: $showingDownloads) {
            IOSDownloadsView(downloads: model.downloads, language: model.languageMode)
                .presentationCornerRadius(IOSDesign.cardCornerRadius)
        }
		.task(id: "\(username)-\(model.languageMode.rawValue)") {
			await profileData.load(username: username, language: model.languageMode)
		}
		.onChange(of: scenePhase) { _, phase in
			if phase == .active {
				profileData.reload(username: username, language: model.languageMode)
			}
		}
	        .overlay(alignment: .top) {
	            IOSDownloadFeedbackOverlay(downloads: model.downloads)
	                .padding(.top, 8)
	        }
	        .iosGlassHomeIndicatorArea()
	    }

	private var wallhavenProfileURL: URL {
		var url = URL(string: "https://wallhaven.cc/user")!
		url.appendPathComponent(username)
		return url
	}
	}

private struct IOSProfileStatsView: View {
    let profile: IOSWallhavenUserProfile
    let language: IOSAppLanguage

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: columns, spacing: 8) {
                stat(value: profile.uploadCount.formatted(), label: IOSL10n.t("uploads", language))
                stat(value: profile.favoriteCount.formatted(), label: IOSL10n.t("favorites", language))
                stat(value: profile.subscriberCount.formatted(), label: IOSL10n.t("subscribers", language))
            }

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                Text("\(IOSL10n.t("joined", language)) \(profile.joinedYearText(language: language))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: IOSDesign.cardCornerRadius, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct IOSProfileCommentsView: View {
    let comments: [IOSWallhavenProfileComment]
    let isLoading: Bool
    let language: IOSAppLanguage
    let writeAction: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: writeAction) {
                Label(IOSL10n.t("wallhaven_comment", language), systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 16)

            if isLoading && comments.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if comments.isEmpty {
                ContentUnavailableView(IOSL10n.t("no_profile_comments", language), systemImage: "bubble.left.and.bubble.right")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(comments) { comment in
                        HStack(alignment: .top, spacing: 11) {
                            IOSRemoteAvatarView(url: comment.avatarURL, fallback: comment.author, size: 38)

                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(comment.author)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(comment.postedAt)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                Text(comment.message)
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Divider()
                            .padding(.leading, 65)
                    }
                }
            }
        }
    }
}

private extension URL {
    func appending(fragment: String) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.fragment = fragment
        return components.url ?? self
    }
}

@MainActor
private final class IOSUserProfileDataModel: ObservableObject {
    @Published private(set) var profile: IOSWallhavenUserProfile?
    @Published private(set) var isLoading = false
    @Published private(set) var networkUnavailable = false
    @Published private(set) var errorMessage: String?

    private let api = IOSWallhavenAPI()
    private var loadedUsername = ""
    private var loadTask: Task<Void, Never>?

    func load(username: String, language: IOSAppLanguage) async {
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUsername.isEmpty else { return }
        if loadedUsername.caseInsensitiveCompare(cleanUsername) == .orderedSame, profile != nil {
            return
        }
        reload(username: cleanUsername, language: language)
    }

    func reload(username: String, language: IOSAppLanguage) {
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUsername.isEmpty else { return }
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil
        networkUnavailable = false

        loadTask = Task {
            do {
                let result = try await api.userProfile(username: cleanUsername)
                guard !Task.isCancelled else { return }
                self.profile = result
                self.loadedUsername = cleanUsername
                self.isLoading = false
            } catch is CancellationError {
                self.isLoading = false
            } catch {
                self.isLoading = false
                self.networkUnavailable = IOSIsNetworkUnavailable(error)
                self.errorMessage = self.networkUnavailable
                    ? IOSL10n.t("no_network", language)
                    : IOSL10n.t("profile_data_unavailable", language)
            }
        }
    }
}

private struct IOSProfileUploadFeed: View {
    @ObservedObject var model: IOSAppModel
    let username: String
    @StateObject private var feed = IOSProfileFeedModel()

    private var wallpapers: [IOSWallpaper] {
        feed.wallpapers
    }

    var body: some View {
        Group {
            if feed.isLoading && wallpapers.isEmpty {
                ProgressView(model.t("loading"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if wallpapers.isEmpty {
                ContentUnavailableView {
                    Label(
                        feed.networkUnavailable
                            ? model.t("no_network")
                            : (feed.errorMessage == nil ? model.t("no_uploads") : model.t("profile_data_unavailable")),
                        systemImage: feed.networkUnavailable ? "wifi.exclamationmark" : "photo.stack"
                    )
                } description: {
                    Text(feed.networkUnavailable ? model.t("network_unavailable_message") : (feed.errorMessage ?? ""))
                } actions: {
                    if feed.errorMessage != nil || feed.networkUnavailable {
                        Button(model.t("reload")) {
                            feed.reload(
                                username: username,
                                apiKey: model.apiKey,
                                includeAdultContent: model.effectiveAdultContentEnabled,
                                language: model.languageMode
                            )
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                IOSProfileWallpaperGrid(
                    model: model,
                    wallpapers: wallpapers,
                    canLoadMore: feed.canLoadMore,
                    isLoadingMore: feed.isLoadingMore,
                    loadMore: {
                        feed.loadMore(apiKey: model.apiKey, includeAdultContent: model.effectiveAdultContentEnabled, language: model.languageMode)
                    }
                )
            }
        }
        .task(id: "\(username)-\(model.apiKey)-\(model.effectiveAdultContentEnabled)") {
            await feed.load(username: username, apiKey: model.apiKey, includeAdultContent: model.effectiveAdultContentEnabled, language: model.languageMode)
        }
    }
}

private struct IOSProfileFavoritesGrid: View {
    @ObservedObject var model: IOSAppModel
    let username: String?

    private var wallpapers: [IOSWallpaper] {
        model.favoriteWallpapers.values
            .filter { wallpaper in
                guard let username else { return true }
                return wallpaper.uploader?.username.caseInsensitiveCompare(username) == .orderedSame
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        if wallpapers.isEmpty {
            ContentUnavailableView(model.t("no_favorites"), systemImage: "heart")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else {
            IOSProfileWallpaperGrid(
                model: model,
                wallpapers: wallpapers,
                canLoadMore: false,
                isLoadingMore: false,
                loadMore: {}
            )
        }
    }
}

private struct IOSProfileWallpaperGrid: View {
    @ObservedObject var model: IOSAppModel
    let wallpapers: [IOSWallpaper]
    let canLoadMore: Bool
    let isLoadingMore: Bool
    let loadMore: () -> Void
    @State private var detailWallpaper: IOSWallpaper?
    @State private var contentHeight: CGFloat = 1
    private let spacing: CGFloat = 10

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let layout = makeLayout(width: proxy.size.width)

                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(layout.columns.enumerated()), id: \.offset) { _, column in
                        LazyVStack(spacing: spacing) {
                            ForEach(column) { wallpaper in
                                IOSWallpaperCard(
                                    wallpaper: wallpaper,
                                    imageURL: wallpaper.gridPreviewURL,
                                    maxPixelSize: 1200,
                                    isDownloaded: model.downloads.isDownloaded(wallpaper),
                                    isDownloading: model.downloads.isDownloading(wallpaper),
                                    isSelectionMode: model.isMultiSelecting,
                                    isSelected: model.selectedWallpaperIDs.contains(wallpaper.id),
                                    language: model.languageMode,
                                    downloadAction: { model.download(wallpaper) }
                                )
                                .frame(width: layout.columnWidth)
                                .onTapGesture {
                                    if model.isMultiSelecting {
                                        model.toggleWallpaperSelection(wallpaper)
                                    } else {
                                        detailWallpaper = wallpaper
                                    }
                                }
                                .onLongPressGesture(minimumDuration: 0.35) {
                                    model.beginMultiSelection(with: wallpaper)
                                }
                                .onAppear {
                                    if wallpaper.id == wallpapers.suffix(4).first?.id {
                                        loadMore()
                                    }
                                }
                            }
                        }
                        .frame(width: layout.columnWidth)
                    }
                }
                .padding(.horizontal, 12)
                .onAppear {
                    updateContentHeight(layout.contentHeight)
                }
                .onChange(of: layout.contentHeight) { _, height in
                    updateContentHeight(height)
                }
            }
            .frame(height: contentHeight)

            if isLoadingMore {
                ProgressView()
                    .padding(.vertical, 18)
            } else if canLoadMore {
                Text(model.t("continue_load_more"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 18)
            }
        }
        .sheet(item: $detailWallpaper) { wallpaper in
            IOSWallpaperDetailView(model: model, wallpaper: wallpaper)
                .presentationCornerRadius(IOSDesign.cardCornerRadius)
        }
    }

    private func makeLayout(width: CGFloat) -> IOSMasonryLayout {
        let horizontalPadding: CGFloat = 24
        let columnWidth = max(120, (width - horizontalPadding - spacing) / 2)
        var columns = Array(repeating: [IOSWallpaper](), count: 2)
        var heights = Array(repeating: CGFloat.zero, count: 2)

        for wallpaper in wallpapers {
            let target = heights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            columns[target].append(wallpaper)
            heights[target] += columnWidth / max(wallpaper.previewAspectRatio, 0.35) + spacing
        }

        return IOSMasonryLayout(columns: columns, columnWidth: columnWidth, contentHeight: heights.max() ?? 0)
    }

    private func updateContentHeight(_ height: CGFloat) {
        guard height > 0, abs(height - contentHeight) > 0.5 else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            contentHeight = height
        }
    }
}

@MainActor
private final class IOSProfileFeedModel: ObservableObject {
    @Published private(set) var wallpapers: [IOSWallpaper] = []
    @Published private(set) var meta: IOSSearchMeta?
    @Published var errorMessage: String?
    @Published var networkUnavailable = false
    @Published var isLoading = false
    @Published var isLoadingMore = false

    private let api = IOSWallhavenAPI()
    private var username = ""
    private var loadSignature = ""
    private var loadTask: Task<Void, Never>?

    private struct CacheEntry {
        let wallpapers: [IOSWallpaper]
        let meta: IOSSearchMeta?
        let storedAt: Date
    }

    private static var cache: [String: CacheEntry] = [:]

    var canLoadMore: Bool {
        guard !wallpapers.isEmpty else { return false }
        guard let meta else { return false }
        return meta.currentPage < meta.lastPage
    }

    func load(username: String, apiKey: String, includeAdultContent: Bool, language: IOSAppLanguage) async {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let signature = Self.cacheKey(username: trimmed, apiKey: apiKey, includeAdultContent: includeAdultContent)
        if loadSignature == signature, (!wallpapers.isEmpty || meta != nil) {
            return
        }

        self.username = trimmed
        loadSignature = signature

        if let cached = Self.cache[signature] {
            wallpapers = cached.wallpapers
            meta = cached.meta
            networkUnavailable = false
            errorMessage = nil
            if Date().timeIntervalSince(cached.storedAt) < 180 {
                return
            }
        }

        fetch(page: 1, reset: true, apiKey: apiKey, includeAdultContent: includeAdultContent, language: language)
    }

    func loadMore(apiKey: String, includeAdultContent: Bool, language: IOSAppLanguage) {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }
        fetch(page: (meta?.currentPage ?? 0) + 1, reset: false, apiKey: apiKey, includeAdultContent: includeAdultContent, language: language)
    }

    func reload(username: String, apiKey: String, includeAdultContent: Bool, language: IOSAppLanguage) {
        loadSignature = ""
        Task {
            await load(
                username: username,
                apiKey: apiKey,
                includeAdultContent: includeAdultContent,
                language: language
            )
        }
    }

    private func fetch(page: Int, reset: Bool, apiKey: String, includeAdultContent: Bool, language: IOSAppLanguage) {
        if reset {
            loadTask?.cancel()
            isLoading = true
            isLoadingMore = false
            if wallpapers.isEmpty {
                networkUnavailable = false
            }
        } else {
            isLoadingMore = true
        }

        errorMessage = nil
        let username = username

        loadTask = Task {
            do {
                let requestAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                let result = try await api.userUploads(username: username, page: page, apiKey: requestAPIKey)
                guard !Task.isCancelled else { return }
                let visibleData = includeAdultContent
                    ? result.data
                    : result.data.filter { $0.purity.caseInsensitiveCompare("sfw") == .orderedSame }

                await MainActor.run {
                    self.meta = result.meta
                    self.isLoading = false
                    self.isLoadingMore = false
                    self.networkUnavailable = false
                    if reset {
                        var seen = Set<String>()
                        let updated = visibleData.filter { wallpaper in
                            seen.insert(wallpaper.id).inserted
                        }
                        if !updated.isEmpty || result.meta.total == 0 || self.wallpapers.isEmpty {
                            self.wallpapers = updated
                        }
                    } else {
                        let existing = Set(self.wallpapers.map(\.id))
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            self.wallpapers.append(contentsOf: visibleData.filter { !existing.contains($0.id) })
                        }
                    }
                    Self.cache[self.loadSignature] = CacheEntry(
                        wallpapers: self.wallpapers,
                        meta: self.meta,
                        storedAt: Date()
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isLoading = false
                    self.isLoadingMore = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.isLoadingMore = false
                    if reset, self.wallpapers.isEmpty {
                        self.meta = nil
                    }
                    self.networkUnavailable = IOSIsNetworkUnavailable(error)
                    self.errorMessage = IOSDisplayMessage(for: error, language: language)
                }
            }
        }
    }

    private static func cacheKey(username: String, apiKey: String, includeAdultContent: Bool) -> String {
        let hasAPIKey = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return "\(username.lowercased())|\(hasAPIKey)|\(includeAdultContent)"
    }
}

private struct IOSSubscriptionsView: View {
    @ObservedObject var model: IOSAppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if model.subscribedUsers.isEmpty {
                ContentUnavailableView(model.t("no_subscriptions"), systemImage: "person.2")
            } else {
                ForEach(model.subscribedUsers) { user in
                    NavigationLink {
                        IOSUserProfileView(model: model, profile: .user(user))
                    } label: {
	                        HStack(spacing: 12) {
	                            IOSRemoteAvatarView(url: user.avatarURL, fallback: user.username, size: 40)
	                            Text(user.username)
	                                .font(.headline)
	                            Spacer()
	                        }
	                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        model.toggleSubscription(model.subscribedUsers[index])
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(model.t("subscriptions"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct IOSTagCenterView: View {
    @ObservedObject var model: IOSAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var tagName = ""

    var body: some View {
        List {
            Section(model.t("followed_tags")) {
                HStack {
                    TextField(model.t("input_tag"), text: $tagName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(model.t("follow")) {
                        model.toggleFollowedTag(tagName)
                        tagName = ""
                    }
                    .disabled(tagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section(model.t("tags")) {
                if model.followedTags.isEmpty {
                    ContentUnavailableView(model.t("no_tags"), systemImage: "tag")
                } else {
                    ForEach(model.followedTags) { tag in
                        NavigationLink {
                            IOSTagFeedView(model: model, tagName: tag.name)
                        } label: {
                            HStack {
                                Label(tag.name, systemImage: "tag")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            model.toggleFollowedTag(model.followedTags[index].name)
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(model.t("tags"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct IOSLocalAvatarView: View {
    @ObservedObject var model: IOSAppModel
    let size: CGFloat

    var body: some View {
        Group {
            if let data = model.avatarImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let url = model.avatarURL {
                IOSCachedRemoteImage(url: url, contentMode: .fill, maxPixelSize: size * 3) {
                    IOSAvatarFallback(text: model.displayName, size: size)
                }
            } else {
                IOSAvatarFallback(text: model.displayName, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.28), lineWidth: 1)
        }
    }
}

struct IOSRemoteAvatarView: View {
    let url: URL?
    let fallback: String
    let size: CGFloat

    var body: some View {
        IOSCachedRemoteImage(url: url, contentMode: .fill, maxPixelSize: size * 3) {
            IOSAvatarFallback(text: fallback, size: size)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.28), lineWidth: 1)
        }
    }
}

private struct IOSAvatarFallback: View {
    let text: String
    let size: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.85), .pink.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(initial)
                .font(.system(size: max(12, size * 0.42), weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var initial: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first.map { String($0).uppercased() } ?? "W"
    }
}
