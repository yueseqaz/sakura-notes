import Foundation
import SakuraCore
import SakuraStorage
import SakuraSearch

/// Rewrites wiki links and relative markdown links after a note or folder is
/// renamed/moved, so internal links follow the file.
///
/// Rewrites are conservative and exact:
/// - `[[Old Title]]`, `[[Old Title|alias]]`, `[[Old Title#anchor]]` become
///   `[[New Title…]]` when the moved note's title changed.
/// - Markdown links/images whose target resolves to the moved file's old
///   path are rewritten to the new path.
/// Every changed note is snapshotted first, and the caller can report the
/// count of updated files.
enum LinkUpdater {

    struct Report {
        var notesScanned = 0
        var notesUpdated = 0
        var linksRewritten = 0
    }

    @MainActor
    static func updateLinksAfterMove(
        vault: VaultStore,
        search: SearchCoordinator?,
        snapshots: SnapshotStore,
        from oldPath: String,
        to newPath: String
    ) -> Report {
        var report = Report()
        let oldTitle = (((oldPath as NSString).lastPathComponent) as NSString).deletingPathExtension
        let newTitle = (((newPath as NSString).lastPathComponent) as NSString).deletingPathExtension
        let movedIsFolder = vault.isFolder(newPath)

        // Notes to inspect: those mentioning the old title, plus (for path
        // rewrites) notes under the old folder when a folder moved.
        var candidates = Set<String>()
        if let search, !oldTitle.isEmpty {
            candidates.formUnion(search.notesContaining(text: oldTitle, excludingPath: newPath))
        }
        if movedIsFolder || oldPath.contains("/") {
            let prefix = oldPath + "/"
            candidates.formUnion(vault.notes.filter { $0.relativePath.hasPrefix(prefix) }.map(\.relativePath))
        }
        candidates.remove(oldPath)
        candidates.remove(newPath)

        for notePath in candidates.sorted() {
            guard vault.isMarkdown(notePath), var content = try? vault.readNote(notePath) else { continue }
            report.notesScanned += 1
            let original = content

            // 1. Wiki link rewrites (title change only, for file moves).
            if oldTitle != newTitle {
                content = rewriteWikiLinks(content, oldTitle: oldTitle, newTitle: newTitle)
            }

            // 2. Relative path rewrites for markdown links/images.
            content = rewriteRelativeLinks(
                content,
                noteFolder: (notePath as NSString).deletingLastPathComponent,
                oldPath: oldPath,
                newPath: newPath
            )

            if content != original {
                _ = snapshots.capture(vaultRoot: vault.rootURL, relativePath: notePath, content: original)
                do {
                    try vault.writeNote(notePath, content: content)
                    report.notesUpdated += 1
                } catch {
                    // Never let link maintenance break a rename; leave the
                    // note untouched and continue.
                    continue
                }
            }
        }
        return report
    }

    /// Rewrites `[[Old Title…]]` forms. Exact title matches only.
    static func rewriteWikiLinks(_ content: String, oldTitle: String, newTitle: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[("# + NSRegularExpression.escapedPattern(for: oldTitle) + #")(\]\]|\||#)"#) else {
            return content
        }
        let ns = content as NSString
        var result = content
        for match in regex.matches(in: content, range: NSRange(location: 0, length: ns.length)).reversed() {
            let suffix = ns.substring(with: match.range(at: 2))
            let replacement = "[[\(newTitle)\(suffix)"
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        return result
    }

    /// Rewrites `](target)` / `](target "title")` when the target, resolved
    /// relative to the note, equals the moved item's old path.
    static func rewriteRelativeLinks(_ content: String, noteFolder: String, oldPath: String, newPath: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#) else {
            return content
        }
        let ns = content as NSString
        var result = content
        for match in regex.matches(in: content, range: NSRange(location: 0, length: ns.length)).reversed() {
            let raw = ns.substring(with: match.range(at: 1))
            if raw.hasPrefix("http://") || raw.hasPrefix("https://") || raw.hasPrefix("#") || raw.hasPrefix("data:") { continue }
            let decoded = raw.removingPercentEncoding ?? raw
            let resolved = PreviewPathResolver.resolve(base: noteFolder, relative: decoded)
            guard resolved == oldPath || resolved == oldPath + "/" || resolved.hasPrefix(oldPath + "/") else { continue }
            let suffixInOld = resolved.dropFirst(oldPath.count)
            let newResolved = newPath + suffixInOld
            let relative = relativeFrom(noteFolder: noteFolder, to: newResolved)
            let encoded = StringUtilities.urlPathEncoded(relative)
            let replacementRange = match.range(at: 1)
            result = (result as NSString).replacingCharacters(in: replacementRange, with: encoded)
        }
        return result
    }

    /// Relative path from a folder to a target vault path.
    static func relativeFrom(noteFolder: String, to targetPath: String) -> String {
        let base = noteFolder.split(separator: "/").map(String.init)
        let target = targetPath.split(separator: "/").map(String.init)
        var common = 0
        while common < base.count && common < target.count && base[common] == target[common] {
            common += 1
        }
        var comps: [String] = []
        for _ in common..<base.count { comps.append("..") }
        comps.append(contentsOf: target[common...])
        return comps.joined(separator: "/")
    }
}

/// Path resolution shared with the preview scheme handler.
enum PreviewPathResolver {
    static func resolve(base: String, relative: String) -> String {
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
