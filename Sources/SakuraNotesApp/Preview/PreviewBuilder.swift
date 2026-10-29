import Foundation
import SakuraCore

/// Builds complete, self-contained HTML documents for the preview pane and
/// HTML export. All scripts and styles are bundled locally — nothing is
/// fetched from the network.
enum PreviewBuilder {

    enum FontResolution {
        /// Font URLs point at the app bundle (preview, which loads with the
        /// note folder as base URL).
        case absoluteBundleURLs
        /// Fonts are embedded as base64 data URLs (portable HTML export).
        case embedded
    }

    /// - Parameters:
    ///   - markdown: raw note content
    ///   - dark: render in dark mode
    ///   - writingWidth: maximum content width in points (0 = no limit)
    ///   - title: document title
    static func build(
        markdown rawMarkdown: String,
        dark: Bool,
        writingWidth: CGFloat,
        includeMath: Bool = true,
        includeMermaid: Bool = true,
        includeHighlight: Bool = true,
        title: String = "Preview",
        fontResolution: FontResolution = .absoluteBundleURLs
    ) -> String {
        // The front matter block is metadata, not content; render the body only.
        let markdown = FrontMatter.extract(from: rawMarkdown).bodyRange.map { String(rawMarkdown[$0]) } ?? rawMarkdown
        let body = HTMLRenderer.render(markdown)
        let css = Self.resourceString("style.css", subdirectory: "Resources/Preview") ?? ""
        let lightHighlight = Self.resourceString("highlight-github.min.css", subdirectory: "Resources/Preview/vendor") ?? ""
        let darkHighlight = Self.resourceString("highlight-github-dark.min.css", subdirectory: "Resources/Preview/vendor") ?? ""
        let highlightJS = Self.resourceString("highlight.min.js", subdirectory: "Resources/Preview/vendor") ?? ""
        let katexCSS = Self.katexCSS(fontResolution: fontResolution)
        let katexJS = Self.resourceString("katex.min.js", subdirectory: "Resources/Preview/vendor/katex") ?? ""
        let autoRenderJS = Self.resourceString("auto-render.min.js", subdirectory: "Resources/Preview/vendor/katex") ?? ""
        let mermaidJS = Self.resourceString("mermaid.min.js", subdirectory: "Resources/Preview/vendor") ?? ""

        let widthCSS = writingWidth > 0
            ? "#content { max-width: \(Int(writingWidth))pt; margin: 0 auto; }"
            : ""

        let headParts: [String] = [
            "<meta charset=\"utf-8\">",
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
            "<title>\(StringUtilities.htmlEscaped(title))</title>",
            "<style>\(css)</style>",
            "<style>\(dark ? darkHighlight : lightHighlight)</style>",
            includeMath ? "<style>\(katexCSS)</style>" : "",
            "<style>\(widthCSS)</style>",
        ]
        let bodyParts: [String] = [
            "<div id=\"content\">\(body)</div>",
            includeHighlight
                ? "<script>\(highlightJS)</script><script>if (window.hljs) { document.querySelectorAll('pre code:not(.language-mermaid)').forEach(b => { try { hljs.highlightElement(b); } catch (e) {} }); }</script>"
                : "",
            includeMath
                ? "<script>\(katexJS)</script><script>\(autoRenderJS)</script><script>if (window.renderMathInElement) { renderMathInElement(document.body, { delimiters: [ {left: '$$', right: '$$', display: true}, {left: '$', right: '$', display: false}, {left: '\\\\(', right: '\\\\)', display: false}, {left: '\\\\[', right: '\\\\]', display: true} ], throwOnError: false }); }</script>"
                : "",
            includeMermaid
                ? "<script>\(mermaidJS)</script><script>if (window.mermaid) { mermaid.initialize({ startOnLoad: true, securityLevel: 'strict', theme: '\(dark ? "dark" : "default")', fontFamily: '-apple-system, sans-serif' }); }</script>"
                : "",
        ]

        return """
        <!DOCTYPE html>
        <html class="\(dark ? "dark" : "light")">
        <head>
        \(headParts.filter { !$0.isEmpty }.joined(separator: "\n"))
        </head>
        <body>
        \(bodyParts.filter { !$0.isEmpty }.joined(separator: "\n"))
        </body>
        </html>
        """
    }

    /// Standalone export: fonts embedded so the HTML file works anywhere.
    static func buildForExport(markdown: String, title: String, dark: Bool = false) -> String {
        build(markdown: markdown, dark: dark, writingWidth: 720, title: title, fontResolution: .embedded)
    }

    // MARK: - Resource helpers

    private static func katexCSS(fontResolution: FontResolution) -> String {
        guard let css = resourceString("katex.min.css", subdirectory: "Resources/Preview/vendor/katex") else {
            return ""
        }
        let dir = Bundle.module.url(forResource: "katex.min.css", withExtension: nil, subdirectory: "Resources/Preview/vendor/katex")?
            .deletingLastPathComponent()
        switch fontResolution {
        case .absoluteBundleURLs:
            guard let dir else { return css }
            return css.replacingOccurrences(
                of: "url(fonts/",
                with: "url(\(dir.appendingPathComponent("fonts", isDirectory: true).absoluteString)"
            )
        case .embedded:
            var result = css
            // Replace each fonts/X.woff2 reference with a data URL.
            guard let regex = try? NSRegularExpression(pattern: #"url\(fonts/([^)]+?\.woff2)\)"#) else { return result }
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() {
                let fileName = ns.substring(with: match.range(at: 1))
                let fontURL = Bundle.module.url(
                    forResource: (fileName as NSString).deletingPathExtension,
                    withExtension: (fileName as NSString).pathExtension,
                    subdirectory: "Resources/Preview/vendor/katex/fonts"
                )
                guard let fontURL, let data = try? Data(contentsOf: fontURL) else { continue }
                let dataURL = "url(data:font/woff2;base64,\(data.base64EncodedString()))"
                result = ns.replacingCharacters(in: match.range, with: dataURL)
            }
            return result
        }
    }

    static func resourceString(_ name: String, subdirectory: String) -> String? {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: subdirectory) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
