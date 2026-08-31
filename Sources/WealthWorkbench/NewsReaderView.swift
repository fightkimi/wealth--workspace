import AppKit
import SwiftUI
import WebKit

struct NewsReaderView: View {
    let item: NewsItem
    let onClose: () -> Void

    @StateObject private var browser = NewsWebReaderState()

    var body: some View {
        VStack(spacing: 0) {
            readerToolbar
            loadingIndicator

            if let notice = browser.noticeMessage {
                securityNotice(notice)
            }

            ZStack {
                EmbeddedNewsWebView(url: item.link, state: browser)
                    .clipShape(RoundedRectangle(cornerRadius: WorkbenchLayout.panelRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: WorkbenchLayout.panelRadius, style: .continuous)
                            .stroke(WorkbenchTheme.border, lineWidth: 1)
                    )

                if let message = browser.errorMessage {
                    readerError(message)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color.clear)
    }

    private var readerToolbar: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Label("返回资讯", systemImage: "chevron.left")
            }
            .workbenchActionButton(.secondary)
            .keyboardShortcut("[", modifiers: .command)

            Rectangle()
                .fill(WorkbenchTheme.border)
                .frame(width: 1, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(.custom("PingFangSC-Semibold", size: 15))
                    .foregroundStyle(WorkbenchTheme.text)
                    .lineLimit(1)

                HStack(spacing: 7) {
                    Text(item.source)
                    if let host = browser.currentURL?.host {
                        Text("·")
                        Text(host)
                    }
                }
                .font(.custom("PingFangSC-Regular", size: 10))
                .foregroundStyle(WorkbenchTheme.muted)
                .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button { browser.goBack() } label: {
                    Image(systemName: "chevron.left")
                }
                .workbenchActionButton(.icon)
                .disabled(!browser.canGoBack)
                .help("网页后退")

                Button { browser.goForward() } label: {
                    Image(systemName: "chevron.right")
                }
                .workbenchActionButton(.icon)
                .disabled(!browser.canGoForward)
                .help("网页前进")

                Button { browser.reload() } label: {
                    Image(systemName: browser.isLoading ? "xmark" : "arrow.clockwise")
                }
                .workbenchActionButton(.icon)
                .help(browser.isLoading ? "停止加载" : "重新加载")

                Button(action: openInDefaultBrowser) {
                    Label("浏览器打开", systemImage: "safari")
                }
                .workbenchActionButton(.secondary)
                .help("使用默认浏览器打开当前网页")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(WorkbenchTheme.surface)
    }

    @ViewBuilder
    private var loadingIndicator: some View {
        if browser.isLoading {
            ProgressView()
                .progressViewStyle(.linear)
                .tint(WorkbenchTheme.accent)
                .frame(height: 2)
        } else {
            Color.clear.frame(height: 2)
        }
    }

    private func securityNotice(_ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "lock.shield")
                .foregroundStyle(WorkbenchTheme.warning)
            Text(message)
                .font(.custom("PingFangSC-Regular", size: 11))
                .foregroundStyle(WorkbenchTheme.secondary)
            Spacer()
            Button { browser.dismissNotice() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(WorkbenchTheme.muted)
            .help("关闭提示")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 34)
        .background(WorkbenchTheme.warning.opacity(0.08))
        .overlay(alignment: .bottom) {
            Rectangle().fill(WorkbenchTheme.warning.opacity(0.20)).frame(height: 1)
        }
    }

    private func readerError(_ message: String) -> some View {
        VStack(spacing: 13) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(WorkbenchTheme.warning)
            Text("网页暂时无法打开")
                .font(.custom("PingFangSC-Semibold", size: 18))
                .foregroundStyle(WorkbenchTheme.text)
            Text(message)
                .font(.custom("PingFangSC-Regular", size: 12))
                .foregroundStyle(WorkbenchTheme.secondary)
                .multilineTextAlignment(.center)
            Button("重新加载") { browser.retry() }
                .workbenchActionButton(.primary)
        }
        .padding(24)
        .frame(width: 330)
        .workbenchCard()
        .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
    }

    private func openInDefaultBrowser() {
        guard let url = browser.currentURL ?? WebReaderURLPolicy.allowedURL(item.link) else {
            browser.showBlockedNavigation()
            return
        }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class NewsWebReaderState: ObservableObject {
    @Published fileprivate(set) var canGoBack = false
    @Published fileprivate(set) var canGoForward = false
    @Published fileprivate(set) var isLoading = false
    @Published fileprivate(set) var currentURL: URL?
    @Published fileprivate(set) var errorMessage: String?
    @Published fileprivate(set) var noticeMessage: String?

    private weak var webView: WKWebView?
    private var initialURL: URL?

    fileprivate func attach(_ webView: WKWebView, initialURL: URL) {
        self.webView = webView
        self.initialURL = initialURL
        currentURL = initialURL
        syncNavigationState(from: webView)
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        guard let webView else { return }
        if webView.isLoading {
            webView.stopLoading()
            isLoading = false
        } else {
            errorMessage = nil
            webView.reload()
        }
    }

    func retry() {
        guard let webView, let url = WebReaderURLPolicy.allowedURL(webView.url ?? initialURL) else {
            showBlockedNavigation()
            return
        }
        errorMessage = nil
        webView.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 25))
    }

    func dismissNotice() {
        noticeMessage = nil
    }

    fileprivate func navigationStarted(in webView: WKWebView) {
        isLoading = true
        errorMessage = nil
        syncNavigationState(from: webView)
    }

    fileprivate func navigationFinished(in webView: WKWebView) {
        isLoading = false
        syncNavigationState(from: webView)
    }

    fileprivate func navigationFailed(in webView: WKWebView, error: Error) {
        let nsError = error as NSError
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else {
            syncNavigationState(from: webView)
            return
        }
        isLoading = false
        errorMessage = "请检查网络连接，或稍后重试。应用不会用缓存页面冒充最新原文。"
        syncNavigationState(from: webView)
    }

    fileprivate func showBlockedNavigation() {
        noticeMessage = "为保护本地数据，内嵌阅读器只允许打开安全的 HTTPS 网页。"
    }

    private func syncNavigationState(from webView: WKWebView) {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        currentURL = WebReaderURLPolicy.allowedURL(webView.url) ?? currentURL
    }
}

private struct EmbeddedNewsWebView: NSViewRepresentable {
    let url: URL
    @ObservedObject var state: NewsWebReaderState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, articleURL: url)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        state.attach(webView, initialURL: url)
        context.coordinator.loadArticle(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.articleURL != url else { return }
        context.coordinator.articleURL = url
        state.attach(webView, initialURL: url)
        context.coordinator.loadArticle(in: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let state: NewsWebReaderState
        fileprivate var articleURL: URL

        init(state: NewsWebReaderState, articleURL: URL) {
            self.state = state
            self.articleURL = articleURL
        }

        fileprivate func loadArticle(in webView: WKWebView) {
            guard let safeURL = WebReaderURLPolicy.allowedURL(articleURL) else {
                state.showBlockedNavigation()
                return
            }
            webView.load(URLRequest(url: safeURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 25))
        }

        // Apple documents WKNavigationDelegate as the policy boundary for
        // accepting or rejecting web navigation:
        // https://developer.apple.com/documentation/webkit/wknavigationdelegate
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let requestedURL = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            let isSubframe = navigationAction.targetFrame?.isMainFrame == false
            if isSubframe && requestedURL.scheme?.lowercased() == "about" {
                decisionHandler(.allow)
                return
            }

            guard WebReaderURLPolicy.allowedURL(requestedURL) != nil else {
                if !isSubframe { state.showBlockedNavigation() }
                decisionHandler(.cancel)
                return
            }

            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            state.navigationStarted(in: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            state.navigationStarted(in: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.navigationFinished(in: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            state.navigationFailed(in: webView, error: error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            state.navigationFailed(in: webView, error: error)
        }
    }
}
