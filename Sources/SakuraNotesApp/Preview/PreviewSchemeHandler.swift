import WebKit
import SakuraCore
import SakuraStorage

/// Serves the preview document, bundled assets, and vault files over the
/// custom `sakura-preview:` scheme. This keeps the preview fully sandboxed:
/// the web view never gets raw file:// access; it can only reach assets the
/// handler explicitly serves.
final class PreviewSchemeHandler: NSObject, WKURLSchemeHandler {

    static let scheme = "sakura-preview"

    /// Provides the current HTML for `sakura-preview://doc/content.html`.
    var htmlProvider: (() -> String)?
    /// Resolves `sakura-preview://file/<relative path>` inside the vault.
    var vault: VaultStore?
    /// Resolves `sakura-preview://bundle/<subpath>` to app resources.
    private let bundleBase = "Resources/"

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        switch url.host {
        case "doc":
            let html = htmlProvider?() ?? "<html><body></body></html>"
            let response = URLResponse(
                url: url,
                mimeType: "text/html",
                expectedContentLength: html.utf8.count,
                textEncodingName: "utf-8"
            )
            task.didReceive(response)
            task.didReceive(Data(html.utf8))
            task.didFinish()
        case "bundle":
            serveBundle(url: url, task: task)
        case "file":
            serveVaultFile(url: url, task: task)
        default:
            task.didFailWithError(URLError(.fileDoesNotExist))
        }
    }

    private func serveBundle(url: URL, task: WKURLSchemeTask) {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.contains("..") else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let directory = (path as NSString).deletingLastPathComponent
        let fileName = (path as NSString).lastPathComponent
        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        guard let resourceURL = Bundle.module.url(
            forResource: name,
            withExtension: ext,
            subdirectory: bundleBase + directory
        ), let data = try? Data(contentsOf: resourceURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = URLResponse(url: url, mimeType: Self.mimeType(for: ext), expectedContentLength: data.count, textEncodingName: ext == "css" || ext == "js" ? "utf-8" : nil)
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func serveVaultFile(url: URL, task: WKURLSchemeTask) {
        guard let vault else {
            task.didFailWithError(URLError(.noPermissionsToReadFile))
            return
        }
        // URL-decode the path segments.
        let relative = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).removingPercentEncoding ?? url.path
        guard !relative.contains("..") else {
            task.didFailWithError(URLError(.noPermissionsToReadFile))
            return
        }
        // Only serve recognized attachment/media types.
        let ext = (relative as NSString).pathExtension.lowercased()
        guard TextFileKind.classify(fileExtension: ext) == .image || ext == "pdf" else {
            task.didFailWithError(URLError(.noPermissionsToReadFile))
            return
        }
        guard let data = try? vault.readData(relative) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = URLResponse(url: url, mimeType: Self.mimeType(for: ext), expectedContentLength: data.count, textEncodingName: nil)
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    static func mimeType(for ext: String) -> String {
        switch ext {
        case "html": return "text/html"
        case "css": return "text/css"
        case "js": return "application/javascript"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }

    /// Rewrites relative image srcs in the rendered HTML to
    /// `sakura-preview://file/<vault-relative path>`.
    static func rewriteImageSources(_ html: String, noteFolder: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"src="([^":]+)""#) else { return html }
        let ns = html as NSString
        var result = html
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).reversed() {
            let raw = ns.substring(with: match.range(at: 1))
            let decoded = raw.removingPercentEncoding ?? raw
            if decoded.isEmpty || decoded.hasPrefix("data:") || decoded.hasPrefix("http") { continue }
            let resolved = resolvePath(base: noteFolder, relative: decoded)
            let replacement = "src=\"\(scheme)://file/\(StringUtilities.urlPathEncoded(resolved))\""
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        return result
    }

    /// Resolves `relative` against `base` without touching the filesystem,
    /// handling `..` and `.` segments.
    static func resolvePath(base: String, relative: String) -> String {
        var components = base.split(separator: "/").map(String.init)
        for part in relative.split(separator: "/") {
            switch part {
            case "..": components.removeLast()
            case ".", "": continue
            default: components.append(String(part))
            }
        }
        return components.joined(separator: "/")
    }
}
