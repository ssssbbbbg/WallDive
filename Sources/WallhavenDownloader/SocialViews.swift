import AppKit
import SwiftUI

struct ProfileAvatar: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(.quaternary)

            if let url, url.isFileURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let url {
                CachedRemoteImage(url: url, contentMode: .fill, maxPixelSize: max(96, size * 3)) {
                    ZStack {
                        Color.clear
                        ProgressView()
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.separator.opacity(0.65), lineWidth: 1)
        }
    }

    private var fallback: some View {
        Image(systemName: "person.crop.circle.fill")
            .font(.system(size: size * 0.72))
            .foregroundStyle(.secondary)
    }
}

struct SubscriptionsSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingWebSync = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("订阅动态")
                    .font(.title2.weight(.semibold))

                Spacer()

                Button {
                    showingWebSync = true
                } label: {
                    Label("同步网页订阅", systemImage: "safari")
                }

                Button {
                    model.refreshSubscriptions()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if let message = model.subscriptionSyncMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if model.subscriptions.isEmpty && !model.isLoadingSubscriptions {
                SubscriptionEmptyState()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.subscriptionMessages.isEmpty && model.isLoadingSubscriptions {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在读取订阅用户的最新上传")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !model.subscriptionMessages.isEmpty {
                        Section("订阅用户动态") {
                            ForEach(model.subscriptionMessages) { message in
                                Button {
                                    model.openSubscriptionMessage(message)
                                    dismiss()
                                } label: {
                                    SubscriptionMessageRow(message: message)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .overlay(alignment: .bottom) {
                    if model.isLoadingSubscriptions {
                        ProgressView()
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.bottom, 12)
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 620, height: 560)
        .onAppear {
            model.refreshSubscriptions()
        }
        .sheet(isPresented: $showingWebSync) {
            WebSubscriptionSyncSheet(model: model)
        }
    }
}

private struct SubscriptionEmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "bell.slash")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.secondary)

            Text("还没有订阅用户")
                .font(.headline)

            Text("在用户主页订阅，或点击右上角同步网页订阅导入 Wallhaven 网页端 USER UPLOADS。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .padding(24)
    }
}

private struct SubscriptionMessageRow: View {
    let message: SubscriptionMessage

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 12) {
                ProfileAvatar(url: message.user.avatarURL, size: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(message.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)

                    Text(message.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                StackedWallpaperPreview(wallpapers: message.recentWallpapers)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 7)
            .padding(.trailing, message.newCount > 0 ? 18 : 0)

            if message.newCount > 0 {
                UpdateCountBadge(count: message.newCount)
                    .offset(x: 3, y: -5)
            }
        }
    }
}

private struct UpdateCountBadge: View {
    let count: Int

    var body: some View {
        Text(countText)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, count > 9 ? 6 : 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(.red, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.7), lineWidth: 1)
            }
            .shadow(color: .red.opacity(0.28), radius: 5, x: 0, y: 2)
            .accessibilityLabel("更新 \(countText) 张")
    }

    private var countText: String {
        count > 99 ? "99+" : "\(count)"
    }
}

private struct StackedWallpaperPreview: View {
    let wallpapers: [Wallpaper]

    private let cardSize = CGSize(width: 54, height: 36)

    var body: some View {
        ZStack(alignment: .center) {
            if wallpapers.isEmpty {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: cardSize.width, height: cardSize.height)
            } else {
                ForEach(Array(wallpapers.prefix(5).enumerated()), id: \.element.id) { index, wallpaper in
                    SubscriptionPreviewCard(wallpaper: wallpaper)
                        .frame(width: cardSize.width, height: cardSize.height)
                        .rotationEffect(.degrees(rotation(for: index)))
                        .offset(x: xOffset(for: index), y: yOffset(for: index))
                        .zIndex(Double(5 - index))
                }
            }
        }
        .frame(width: 98, height: 48)
    }

    private func xOffset(for index: Int) -> CGFloat {
        CGFloat(index) * -10 + CGFloat(max(0, wallpapers.prefix(5).count - 1)) * 5
    }

    private func yOffset(for index: Int) -> CGFloat {
        CGFloat(index % 2 == 0 ? 0 : 4)
    }

    private func rotation(for index: Int) -> Double {
        [-5, -2, 1, 4, 7][min(index, 4)]
    }
}

private struct SubscriptionPreviewCard: View {
    let wallpaper: Wallpaper

    var body: some View {
        CachedRemoteImage(url: wallpaper.gridPreviewURL, contentMode: .fill, maxPixelSize: 220) {
            ZStack {
                Color.secondary.opacity(0.12)
                ProgressView()
                    .controlSize(.small)
            }
        }
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.white.opacity(0.75), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 4, x: 0, y: 2)
    }
}
