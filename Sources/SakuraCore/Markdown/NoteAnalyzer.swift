import Foundation
import Markdown

/// A heading in the document outline.
public struct OutlineEntry: Equatable, Identifiable {
    public var id: Int { lineIndex }
    public let level: Int
    public let title: String
    /// 0-based source line where the heading starts.
    public let lineIndex: Int
}

/// A task parsed from `- [ ]` / `- [x]` list items.
public struct TaskItem: Equatable, Identifiable {
    public var id: String { "\(lineIndex):\(text)" }
    public let text: String
    public let isCompleted: Bool
    /// 0-based source line of the containing list item.
    public let lineIndex: Int
    /// Optional due date parsed from `@due(YYYY-MM-DD)` or `@due(YYYY-MM-DD HH:mm)`.
    public let dueDate: Date?
}

/// A wiki-style or standard link found in the document.
public struct LinkRef: Equatable, Identifiable {
    public var id: String { "\(lineIndex):\(target)" }
    public enum Kind: Equatable {
        case wikiLink(target: String, anchor: String?)
        case external(URL)
        case internalFile(path: String)
    }
    public let kind: Kind
    /// Display text, if any.
    public let display: String?
    public let lineIndex: Int

    public var target: String {
        switch kind {
        case .wikiLink(let target, _): return target
        case .external(let url): return url.absoluteString
        case .internalFile(let path): return path
        }
    }
}

/// The analysis result for a note: everything derived from its Markdown source.
public struct NoteFacts: Equatable {
    public var title: String?
    public var outline: [OutlineEntry]
    public var tasks: [TaskItem]
    public var inlineTags: [String]
    public var frontMatter: FrontMatter
    public var links: [LinkRef]
    public var wordCount: Int
    public var characterCount: Int
    public var readingMinutes: Int
    public var excerpt: String

    public var allTags: [String] {
        var combined = inlineTags
        for tag in frontMatter.tags where !combined.contains(tag) {
            combined.append(tag)
        }
        return combined
    }

    public var openTaskCount: Int { tasks.filter { !$0.isCompleted }.count }
}

public enum NoteAnalyzer {
    /// Analyzes Markdown source. `fileName` (without extension) is used as the
    /// fallback title and for resolving wiki-link identity.
    public static func analyze(markdown source: String, fileName: String) -> NoteFacts {
        let (matter, bodyRange) = FrontMatter.extract(from: source)
        let body = bodyRange.map { String(source[$0]) } ?? source

        let document = Document(parsing: body)
        var outline: [OutlineEntry] = []
        var tasks: [TaskItem] = []
        var inlineTags = Set<String>()
        var links: [LinkRef] = []
        var firstHeading: String? = nil
        var firstParagraph: String? = nil

        var plainTextParts: [String] = []

        // Walk top-level blocks and their children, tracking source lines.
        walk(document) { node, insideCode, insideLink in
            if let heading = node as? Heading, let range = node.range {
                let text = plainText(of: heading)
                outline.append(OutlineEntry(level: heading.level, title: text, lineIndex: range.lowerBound.line - 1))
                if firstHeading == nil && !text.isEmpty { firstHeading = text }
            }
            if let item = node as? ListItem, let range = node.range {
                // Checkbox tasks: first child Paragraph starting with [ ]/[x].
                if let task = parseTask(from: item) {
                    tasks.append(TaskItem(text: task.0, isCompleted: task.1, lineIndex: range.lowerBound.line - 1, dueDate: parseDueDate(task.0)))
                }
            }
            if !insideCode, let textNode = node as? Text {
                extractInlineFacts(from: textNode.string, lineIndex: (node.range?.lowerBound.line ?? 1) - 1) { tag, link in
                    if let tag { inlineTags.insert(tag) }
                    if let link { links.append(link) }
                }
                plainTextParts.append(textNode.string)
            }
            if !insideCode, !insideLink, node is InlineHTML, let range = node.range {
                _ = range // raw HTML is deliberately not interpreted
            }
            if let link = node as? Link, let range = node.range {
                if let url = URL(string: link.destination ?? "") {
                    if url.scheme == "http" || url.scheme == "https" {
                        links.append(LinkRef(kind: .external(url), display: plainText(of: link), lineIndex: range.lowerBound.line - 1))
                    } else if url.scheme == nil || url.scheme == "file" {
                        let path = url.scheme == "file" ? url.path : (link.destination ?? "")
                        links.append(LinkRef(kind: .internalFile(path: path), display: plainText(of: link), lineIndex: range.lowerBound.line - 1))
                    }
                }
            }
            if firstParagraph == nil, let para = node as? Paragraph {
                let text = plainText(of: para)
                if !text.isEmpty { firstParagraph = text }
            }
        }

        // Wiki links need a second pass over text because they are plain text to cmark.
        // (Handled inside extractInlineFacts via regex.)

        let plain = plainTextParts.joined(separator: " ")
        let words = StringUtilities.wordCount(plain)
        let title = matter.title ?? firstHeading ?? fileName

        return NoteFacts(
            title: title.isEmpty ? fileName : title,
            outline: outline,
            tasks: tasks,
            inlineTags: inlineTags.sorted(),
            frontMatter: matter,
            links: links,
            wordCount: words,
            characterCount: source.count,
            readingMinutes: StringUtilities.readingTime(minutesForWords: words),
            excerpt: StringUtilities.excerpt(firstParagraph ?? plain)
        )
    }

    /// Recursively walks the document. `visit` receives each node plus context
    /// about whether it is inside code or a link.
    private static func walk(_ node: Markup, _ visit: (Markup, Bool, Bool) -> Void) {
        walk(node, insideCode: false, insideLink: false, visit)
    }

    private static func walk(_ node: Markup, insideCode: Bool, insideLink: Bool, _ visit: (Markup, Bool, Bool) -> Void) {
        var inCode = insideCode
        if node is CodeBlock || node is InlineCode { inCode = true }
        var inLink = insideLink
        if node is Link || node is Image { inLink = true }
        visit(node, inCode, inLink)
        for child in node.children {
            walk(child, insideCode: inCode, insideLink: inLink, visit)
        }
    }

    private static func plainText(of node: Markup) -> String {
        var parts: [String] = []
        collectText(node, into: &parts)
        return parts.joined()
    }

    private static func collectText(_ node: Markup, into parts: inout [String]) {
        if let code = node as? InlineCode {
            parts.append(code.code)
            return
        }
        if node is SoftBreak || node is LineBreak { parts.append(" ") }
        if let text = node as? Text { parts.append(text.string) }
        for child in node.children { collectText(child, into: &parts) }
    }

    /// Parses `- [ ] text` / `- [x] text` from a list item.
    private static func parseTask(from item: ListItem) -> (String, Bool)? {
        guard let paragraph = item.child(at: 0) else { return nil }
        let text = plainText(of: paragraph)
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("[ ]") {
            return (String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces), false)
        }
        if trimmed.hasPrefix("[x]") || trimmed.hasPrefix("[X]") {
            return (String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces), true)
        }
        return nil
    }

    static func parseDueDate(_ text: String) -> Date? {
        guard let range = text.range(of: "@due\\(([^)]+)\\)", options: .regularExpression) else { return nil }
        let inner = text[range].replacingOccurrences(of: "@due(", with: "").replacingOccurrences(of: ")", with: "")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: inner) {
                return date
            }
        }
        return nil
    }

    /// Extracts #tags and [[wiki links]] from a plain-text run.
    private static func extractInlineFacts(
        from text: String,
        lineIndex: Int,
        collect: (String?, LinkRef?) -> Void
    ) {
        // Wiki links: [[Target]], [[Target|Display]], [[Target#Anchor]]
        let wikiPattern = #"\[\[([^\]\|#]+)(?:#([^\]\|]+))?(?:\|([^\]]+))?\]\]"#
        if let regex = try? NSRegularExpression(pattern: wikiPattern) {
            let ns = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let target = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                guard !target.isEmpty else { continue }
                let anchor = match.range(at: 2).location != NSNotFound
                    ? ns.substring(with: match.range(at: 2)) : nil
                let display = match.range(at: 3).location != NSNotFound
                    ? ns.substring(with: match.range(at: 3)) : nil
                collect(nil, LinkRef(kind: .wikiLink(target: target, anchor: anchor), display: display, lineIndex: lineIndex))
            }
        }
        // Tags: #word, #hierarchical/tag — not preceded by word char or another #,
        // not immediately followed by more '#' (to skip headings).
        let tagPattern = #"(?<![\w#/&])#([\p{L}\p{N}][\p{L}\p{N}_\-/]*[^\s,:;.!?]|[\p{L}\p{N}_\-/])"#
        if let regex = try? NSRegularExpression(pattern: tagPattern) {
            let ns = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                var tag = ns.substring(with: match.range(at: 1))
                tag = String(tag.drop(while: { $0 == "#" }))
                if tag.isEmpty || tag.hasPrefix("#") { continue }
                collect(tag, nil)
            }
        }
    }
}
