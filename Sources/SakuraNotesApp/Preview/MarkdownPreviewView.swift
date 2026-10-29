import SwiftUI
import WebKit
import AppKit
import SakuraCore
import SakuraStorage

/// The live Markdown preview, rendered as sanitized HTML in a WebKit view
/// served through the sandboxed `sakura-preview:` scheme.
///
/// Security posture:
/// - Note HTML is sanitized at the AST level (raw HTML dropped by the renderer).
/// - All scripts and fonts are bundled with the app; nothing loads from the network.
/// - The web view has no file:// access; only the scheme handler can serve
///   vault media (images/PDFs) and bundle assets.
/// - External link navigation is redirected to the default browser; internal
///   links open the target note in the app.
struct MarkdownPreviewView: NSViewRepresentable {
    @ObservedObject var session: NoteSession
    @ObservedObject var settings: SettingsStore
    let environment: AppEnvironment

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all

        let handler = PreviewSchemeHandler()
        handler.vault = environment.vault
        let coordinator = context.coordinator
        handler.htmlProvider = { [weak coordinator] in
            coordinator?.currentHTML() ?? "<html><body></body></html>"
        }
        configuration.setURLSchemeHandler(handler, forURLScheme: PreviewSchemeHandler.scheme)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.underPageBackgroundColor = .clear
        context.coordinator.webView = webView
        context.coordinator.handler = handler
        context.coordinator.load()
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.handler?.vault = environment.vault
        context.coordinator.reload(force: false)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: MarkdownPreviewView
        var webView: WKWebView?
        fileprivate var handler: PreviewSchemeHandler?
        private var lastRenderedSignature: String = ""
        private var pendingWorkItem: DispatchWorkItem?
        private var scrollPositionBeforeReload: CGFloat = 0
        private var shouldRestoreScroll = false

        init(_ parent: MarkdownPreviewView) {
            self.parent = parent
        }

        /// Builds the full HTML for the current session state.
        func currentHTML() -> String {
            let session = parent.session
            let settings = parent.settings
            let dark: Bool
            switch settings.appearanceMode {
            case .light: dark = false
            case .dark: dark = true
            case .system: dark = NSApp.effectiveAppearance.isDark
            }
            let title = session.facts.title ?? session.displayTitle
            if session.fileKind == .plainText {
                let escaped = StringUtilities.htmlEscaped(session.text)
                return """
                <!DOCTYPE html><html><head><meta charset="utf-8"><style>body{font-family:-apple-system,sans-serif;white-space:pre-wrap;padding:28px 36px;color:#1d1d21;background:#fff}</style></head><body>\(escaped)</body></html>
                """
            }
            var html = PreviewBuilder.build(
                markdown: session.text,
                dark: dark,
                writingWidth: CGFloat(settings.writingWidth),
                title: title,
                fontResolution: .embedded
            )
            let noteFolder = ((session.path as NSString).deletingLastPathComponent)
            html = PreviewSchemeHandler.rewriteImageSources(html, noteFolder: noteFolder == session.path ? "" : noteFolder)
            return html
        }

        /// Loads the preview document through the scheme handler.
        func load() {
            guard let webView else { return }
            if let url = URL(string: "\(PreviewSchemeHandler.scheme)://doc/content.html") {
                webView.load(URLRequest(url: url))
            }
        }

        /// Debounced reload: only re-renders when content or style changed.
        func reload(force: Bool) {
            let session = parent.session
            let settings = parent.settings
            let dark: Bool
            switch settings.appearanceMode {
            case .light: dark = false
            case .dark: dark = true
            case .system: dark = NSApp.effectiveAppearance.isDark
            }
            let signature = "\(session.text.hashValue)-\(dark)-\(Int(settings.writingWidth))"
            if !force && signature == lastRenderedSignature { return }
            lastRenderedSignature = signature
            pendingWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, let webView = self.webView else { return }
                // Preserve scroll position across content updates.
                webView.evaluateJavaScript("window.scrollY") { result, _ in
                    if let number = result as? Double {
                        self.scrollPositionBeforeReload = CGFloat(number)
                    }
                    self.shouldRestoreScroll = true
                    DispatchQueue.main.async {
                        self.load()
                    }
                }
            }
            pendingWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if shouldRestoreScroll {
                shouldRestoreScroll = false
                webView.evaluateJavaScript("window.scrollTo(0, \(scrollPositionBeforeReload))", completionHandler: nil)
            }
        }

        // MARK: - Navigation policy

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if navigationAction.navigationType == .linkActivated {
                if url.scheme == "http" || url.scheme == "https" || url.scheme == "mailto" {
                    NSWorkspace.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            return nil
        }
    }
}
