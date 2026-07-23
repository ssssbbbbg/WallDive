import SwiftUI

enum MacRootTab: Int, CaseIterable, Identifiable {
    case home
    case following
    case me

    var id: Int { rawValue }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .following: "person.wave.2.fill"
        case .me: "person.crop.circle.fill"
        }
    }
}

enum MacDesign {
    static let panelRadius: CGFloat = 24
    static let islandRadius: CGFloat = 30
    static let imageRadius: CGFloat = 14
    static let pagePadding: CGFloat = 28
    static let navigationHeight: CGFloat = 66
    static let navigationWidth: CGFloat = 236

    static let motion = Animation.spring(response: 0.42, dampingFraction: 0.88)
    static let quickMotion = Animation.spring(response: 0.28, dampingFraction: 0.9)
}

struct MacParityRootView: View {
    @ObservedObject var model: AppModel

    @State private var selectedTab: MacRootTab = .home
    @State private var showingSettings = false
    @State private var showingDownloads = false
    @State private var dragTranslation: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    MacHomeView(model: model)
                        .frame(width: proxy.size.width, height: proxy.size.height)

                    MacFollowingView(model: model)
                        .frame(width: proxy.size.width, height: proxy.size.height)

                    MacMeView(model: model, showingSettings: $showingSettings, showingDownloads: $showingDownloads)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .offset(x: (1 - CGFloat(selectedTab.rawValue)) * proxy.size.width + dragTranslation)
                .animation(MacDesign.motion, value: selectedTab)

                if !model.isMultiSelecting {
                    MacFloatingNavigation(
                        selectedTab: $selectedTab,
                        homeIsRefresh: selectedTab == .home && (model.isHomeGalleryScrolling || model.homeRefreshFeedback != nil),
                        isRefreshing: model.homeRefreshFeedback == .refreshing,
                        refreshHome: { model.refreshCurrentSearch(showFeedback: true) }
                    )
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                } else {
                    MacSelectionDock(model: model)
                        .padding(.bottom, 22)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let feedback = model.downloads.feedback {
                    MacFeedbackToast(feedback: feedback)
                        .padding(.bottom, 102)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: feedback.id) {
                            try? await Task.sleep(for: .seconds(2.2))
                            model.downloads.clearFeedback(id: feedback.id)
                        }
                }

                if let feedback = model.homeRefreshFeedback {
                    MacRefreshToast(feedback: feedback, model: model)
                        .padding(.bottom, 102)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
            .clipped()
            .background(Color(nsColor: .windowBackgroundColor))
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 48)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) * 1.35 else { return }
                        let atFirst = selectedTab == .home && value.translation.width > 0
                        let atLast = selectedTab == .me && value.translation.width < 0
                        dragTranslation = (atFirst || atLast) ? value.translation.width * 0.18 : value.translation.width * 0.52
                    }
                    .onEnded { value in
                        defer { withAnimation(MacDesign.motion) { dragTranslation = 0 } }
                        guard abs(value.translation.width) > abs(value.translation.height) * 1.3 else { return }
                        if value.translation.width < -90, let next = MacRootTab(rawValue: selectedTab.rawValue + 1) {
                            selectedTab = next
                        } else if value.translation.width > 90, let previous = MacRootTab(rawValue: selectedTab.rawValue - 1) {
                            selectedTab = previous
                        }
                    }
            )
        }
        .sheet(isPresented: $showingSettings) {
            MacSettingsView(model: model)
        }
        .sheet(isPresented: $showingDownloads) {
            MacDownloadsView(model: model)
        }
        .sheet(item: $model.selectedWallpaper) { wallpaper in
            MacWallpaperDetailView(model: model, fallbackWallpaper: wallpaper)
        }
        .sheet(item: $model.activeUserProfilePage) { page in
            MacUserProfileView(page: page, model: model)
        }
        .onChange(of: selectedTab) {
            if selectedTab != .home {
                model.isHomeGalleryScrolling = false
            }
        }
    }
}

private struct MacFloatingNavigation: View {
    @Binding var selectedTab: MacRootTab
    let homeIsRefresh: Bool
    let isRefreshing: Bool
    let refreshHome: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(MacRootTab.allCases) { tab in
                Button {
                    if tab == .home, selectedTab == .home, homeIsRefresh {
                        refreshHome()
                    } else {
                        selectedTab = tab
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(selectedTab == tab ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.clear))
                            .shadow(color: selectedTab == tab ? .black.opacity(0.12) : .clear, radius: 14, y: 6)

                        Image(systemName: tab == .home && homeIsRefresh ? "arrow.clockwise" : tab.systemImage)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                            .rotationEffect(.degrees(tab == .home && isRefreshing ? 360 : 0))
                            .animation(
                                tab == .home && isRefreshing
                                    ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                                    : .easeOut(duration: 0.2),
                                value: isRefreshing
                            )
                    }
                    .frame(width: 52, height: 52)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(helpText(for: tab))
            }
        }
        .frame(width: MacDesign.navigationWidth, height: MacDesign.navigationHeight)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.22), lineWidth: 0.8) }
        .shadow(color: .black.opacity(0.16), radius: 22, y: 10)
    }

    private func helpText(for tab: MacRootTab) -> String {
        switch tab {
        case .home: "Home"
        case .following: "Following"
        case .me: "Me"
        }
    }
}

private struct MacSelectionDock: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Button {
                model.exitMultiSelection()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .background(.thinMaterial, in: Circle())

            Text("\(model.selectedWallpaperIDs.count)")
                .font(.headline.monospacedDigit())
                .frame(minWidth: 34)

            Button {
                model.selectAllLoadedWallpapers()
            } label: {
                Image(systemName: "checkmark.circle")
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .help(model.t("select_all"))

            Button {
                model.downloadSelected()
                model.exitMultiSelection()
            } label: {
                Label(
                    String(format: model.t("download_selected"), "\(model.selectedWallpaperIDs.count)"),
                    systemImage: "arrow.down.circle.fill"
                )
                .font(.headline)
                .padding(.horizontal, 15)
                .frame(height: 42)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Color.accentColor, in: Capsule())
            .disabled(model.selectedWallpaperIDs.isEmpty)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.22), lineWidth: 0.8) }
        .shadow(color: .black.opacity(0.18), radius: 22, y: 9)
    }
}

private struct MacFeedbackToast: View {
    let feedback: DownloadFeedback

    var body: some View {
        Label(feedback.state.message, systemImage: feedback.state.systemImage)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 16)
            .frame(height: 42)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
    }
}

private struct MacRefreshToast: View {
    let feedback: HomeRefreshFeedback
    @ObservedObject var model: AppModel

    var body: some View {
        Label(text, systemImage: icon)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 16)
            .frame(height: 42)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
    }

    private var text: String {
        switch feedback {
        case .refreshing: model.t("refreshing")
        case .success(let count): String(format: model.t("refresh_complete"), "\(count)")
        case .failed: model.t("refresh_failed")
        }
    }

    private var icon: String {
        switch feedback {
        case .refreshing: "arrow.clockwise"
        case .success: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}
