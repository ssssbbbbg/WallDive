import SwiftUI
import WebKit

struct WebSubscriptionSyncSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var webState = WebSubscriptionBrowserState()
    @State private var isImporting = false
    @State private var message = "如果页面要求登录，请先在这里登录 Wallhaven，然后打开订阅页并导入。"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("同步网页订阅")
                        .font(.title2.weight(.semibold))
                    Text("读取网页端 USER UPLOADS 里的订阅用户")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    webState.loadSubscriptionsPage()
                } label: {
                    Label("订阅页", systemImage: "bell")
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            WebSubscriptionBrowser(webView: webState.webView)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.separator.opacity(0.5), lineWidth: 1)
                }

            HStack(spacing: 10) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer()

                Button {
                    webState.webView.reload()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }

                Button {
                    importCurrentPage()
                } label: {
                    if isImporting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("导入当前网页订阅", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(isImporting)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 960, height: 720)
        .onAppear {
            webState.loadSubscriptionsPage()
        }
    }

    private func importCurrentPage() {
        isImporting = true
        message = "正在识别当前网页里的订阅用户..."

        webState.extractSubscribedUsers { result in
            Task { @MainActor in
                isImporting = false

                switch result {
                case .success(let users):
                    guard !users.isEmpty else {
                        message = "没有识别到 USER UPLOADS 用户。请确认当前页是 Wallhaven 订阅页，并且网页账号处于在线状态。"
                        return
                    }

                    model.importWebSubscriptions(users)
                    message = model.subscriptionSyncMessage ?? "已导入网页订阅。"
                case .failure(let error):
                    message = error.localizedDescription
                }
            }
        }
    }
}

@MainActor
final class WebSubscriptionBrowserState: ObservableObject {
    let webView: WKWebView

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    }

    func loadSubscriptionsPage() {
        guard let url = URL(string: "https://wallhaven.cc/subscriptions") else { return }
        webView.load(URLRequest(url: url))
    }

    func extractSubscribedUsers(completion: @escaping (Result<[WebSubscribedUser], Error>) -> Void) {
        webView.evaluateJavaScript(Self.extractionScript) { value, error in
            if let error {
                completion(.failure(WebSubscriptionSyncError.javascript(error.localizedDescription)))
                return
            }

            guard let json = value as? String, let data = json.data(using: .utf8) else {
                completion(.failure(WebSubscriptionSyncError.emptyResult))
                return
            }

            do {
                let users = try JSONDecoder().decode([WebSubscribedUser].self, from: data)
                completion(.success(users))
            } catch {
                completion(.failure(WebSubscriptionSyncError.decoding(error.localizedDescription)))
            }
        }
    }

    private static let extractionScript = """
    (() => {
      const clean = (value) => (value || '').replace(/\\s+/g, ' ').trim();
      const decode = (value) => {
        try { return decodeURIComponent(value || ''); } catch (error) { return value || ''; }
      };
      const normalizeUsername = (value) => {
        let username = clean(decode(value)).replace(/^@/, '');
        username = username.replace(/^[0-9,]+\\s+/, '');
        username = username.split(/\\s+/)[0] || '';
        return /^[A-Za-z0-9_-]{1,64}$/.test(username) ? username : null;
      };
      const extractCount = (value) => {
        const match = clean(value).match(/^([0-9,]+)/);
        return match ? parseInt(match[1].replace(/,/g, ''), 10) : null;
      };
      const users = new Map();

      const addUser = (username, text) => {
        username = normalizeUsername(username);
        if (!username) return;
        const key = username.toLowerCase();
        if (users.has(key)) return;
        users.set(key, {
          username,
          displayName: username,
          count: extractCount(text)
        });
      };

      Array.from(document.querySelectorAll('a[href]')).forEach((anchor) => {
        const href = decode(anchor.href || anchor.getAttribute('href') || '');
        const text = clean(anchor.textContent || anchor.innerText || '');
        const queryMatch = href.match(/[?&]q=@([A-Za-z0-9_-]+)/i);
        const encodedQueryMatch = href.match(/[?&]q=%40([A-Za-z0-9_-]+)/i);
        if (queryMatch) addUser(queryMatch[1], text);
        if (encodedQueryMatch) addUser(encodedQueryMatch[1], text);
      });

      const bodyText = (document.body && document.body.innerText) ? document.body.innerText : '';
      const sectionMatch = bodyText.match(/USER UPLOADS[\\s\\S]*?(?:Clear All)?([\\s\\S]*?)(?:USER COLLECTIONS|TAGS|TIPS!|$)/i);
      if (sectionMatch) {
        sectionMatch[1].split(/\\n+/).forEach((line) => {
          const match = clean(line).match(/^([0-9,]+)\\s+([A-Za-z0-9_-]{1,64})$/);
          if (match) addUser(match[2], line);
        });
      }

      return JSON.stringify(Array.from(users.values()));
    })();
    """
}

struct WebSubscriptionBrowser: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

enum WebSubscriptionSyncError: LocalizedError {
    case javascript(String)
    case decoding(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .javascript(let message):
            "无法读取当前网页：\(message)"
        case .decoding(let message):
            "无法解析订阅数据：\(message)"
        case .emptyResult:
            "当前网页没有返回可导入的订阅数据。"
        }
    }
}
