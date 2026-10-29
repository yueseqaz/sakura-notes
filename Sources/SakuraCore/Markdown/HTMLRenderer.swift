import Foundation
import Markdown

/// Renders a Markdown document to sanitized HTML by walking the CommonMark AST.
///
/// Raw HTML blocks and inline HTML are intentionally omitted (not passed
/// through), making the output safe to display in a web view. Math (`$...$`,
/// `$$...$$`) is left as literal text for KaTeX auto-render, and `mermaid`
/// code fences are emitted as `<div class="mermaid">` blocks for Mermaid.js.
public enum HTMLRenderer {

    /// Options controlling rendering.
    public struct Options {
        /// Include a `<h1 id="...">` anchor for each heading (used by TOC links).
        public var headingAnchors: Bool = true
        /// Render task list checkboxes as disabled `<input type="checkbox">`.
        public var renderCheckboxes: Bool = true
        /// Base heading offset: H1 maps to this level (for embedding, e.g. export).
        public var headingOffset: Int = 0

        public init() {}
    }

    public static func render(_ markdown: String, options: Options = Options()) -> String {
        let document = Document(parsing: markdown)
        var html = ""
        for child in document.children {
            html += renderBlock(child, options: options)
        }
        return html
    }

    /// Builds a table of contents (heading hierarchy, flattened with levels).
    public static func tableOfContents(_ markdown: String) -> [(level: Int, title: String, anchor: String)] {
        let document = Document(parsing: markdown)
        var toc: [(Int, String, String)] = []
        for child in document.children {
            walkHeadings(child) { heading in
                let title = plainText(heading)
                toc.append((heading.level, title, anchor(for: title)))
            }
        }
        return toc
    }

    private static func walkHeadings(_ node: Markup, _ visit: (Heading) -> Void) {
        if let heading = node as? Heading { visit(heading) }
        // Do not descend into block quotes that repeat note headings.
        if node is Heading { return }
        for child in node.children { walkHeadings(child, visit) }
    }

    // MARK: - Blocks

    private static func renderBlock(_ node: Markup, options: Options) -> String {
        switch node {
        case let heading as Heading:
            let level = min(6, max(1, heading.level + options.headingOffset))
            let text = renderChildren(heading, options: options)
            if options.headingAnchors {
                let anchor = anchor(for: plainText(heading))
                return "<h\(level) id=\"\(anchor)\">\(text)</h\(level)>\n"
            }
            return "<h\(level)>\(text)</h\(level)>\n"

        case let paragraph as Paragraph:
            let text = renderChildren(paragraph, options: options)
            if paragraph.parent is ListItem { return text }
            return "<p>\(text)</p>\n"

        case let code as CodeBlock:
            return renderCodeBlock(code, options: options)

        case let blockquote as BlockQuote:
            return "<blockquote>\n\(renderBlocks(blockquote.children, options: options))</blockquote>\n"

        case let list as UnorderedList:
            return renderList(list, options: options)

        case let list as OrderedList:
            return "<ol>\n\(renderListItems(list.children, options: options))</ol>\n"

        case let table as Table:
            return renderTable(table, options: options)

        case is ThematicBreak:
            return "<hr />\n"

        case let html as HTMLBlock:
            _ = html // raw HTML is dropped for safety
            return ""

        default:
            return renderChildren(node, options: options) + "\n"
        }
    }

    private static func renderBlocks<S: Sequence>(_ nodes: S, options: Options) -> String where S.Element == Markup {
        nodes.map { renderBlock($0, options: options) }.joined()
    }

    private static func renderCodeBlock(_ code: CodeBlock, options: Options) -> String {
        let codeText = code.code.trimmingCharacters(in: .newlines)
        let language = (code.language ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        if language == "mermaid" {
            return "<div class=\"mermaid\">\(StringUtilities.htmlEscaped(codeText))</div>\n"
        }
        let cls = language.isEmpty ? "" : " class=\"language-\(StringUtilities.htmlEscaped(language))\""
        return "<pre><code\(cls)>\(StringUtilities.htmlEscaped(codeText))\n</code></pre>\n"
    }

    private static func renderList(_ list: UnorderedList, options: Options) -> String {
        // Task list items (containing a checkbox) render in a ul.task-list.
        let isTaskList = list.children.contains { listItemContainsCheckbox($0) }
        let cls = isTaskList ? " class=\"task-list\"" : ""
        return "<ul\(cls)>\n\(renderListItems(list.children, options: options))</ul>\n"
    }

    private static func listItemContainsCheckbox(_ node: Markup) -> Bool {
        guard let item = node as? ListItem, let paragraph = item.child(at: 0) else { return false }
        let text = plainText(paragraph).trimmingCharacters(in: .whitespaces)
        return text.hasPrefix("[ ]") || text.hasPrefix("[x]") || text.hasPrefix("[X]")
    }

    private static func renderListItems<S: Sequence>(_ items: S, options: Options) -> String where S.Element == Markup {
        items.map { item in
            guard let listItem = item as? ListItem else { return "<li></li>" }
            let firstChild = listItem.child(at: 0)
            if let firstChild, let text = firstChild as? Paragraph {
                let raw = plainText(text).trimmingCharacters(in: .whitespaces)
                if raw.hasPrefix("[ ]") || raw.hasPrefix("[x]") || raw.hasPrefix("[X]") {
                    let checked = raw.hasPrefix("[x]") || raw.hasPrefix("[X]")
                    let body = renderChildren(text, options: options, stripTaskPrefix: true)
                    let checkbox = options.renderCheckboxes
                        ? "<input type=\"checkbox\" disabled\(checked ? " checked" : "") /> "
                        : (checked ? "☑ " : "☐ ")
                    let rest = renderBlocks(listItem.children.dropFirst(), options: options)
                    return "<li class=\"task-item\(checked ? " done" : "")\">\(checkbox)\(body)\(rest)</li>\n"
                }
            }
            return "<li>\(renderBlocks(listItem.children, options: options))</li>\n"
        }.joined()
    }

    private static func renderTable(_ table: Table, options: Options) -> String {
        var html = "<table>\n<thead>\n<tr>\n"
        let columnAlignments = table.columnAlignments
        func alignment(_ index: Int) -> Table.ColumnAlignment? {
            columnAlignments.indices.contains(index) ? columnAlignments[index] : nil
        }
        for (index, cell) in table.head.cells.enumerated() {
            html += "<th\(alignmentAttribute(alignment(index)))>\(renderChildren(cell, options: options))</th>\n"
        }
        html += "</tr>\n</thead>\n<tbody>\n"
        for row in table.body.rows {
            html += "<tr>\n"
            for (index, cell) in row.cells.enumerated() {
                html += "<td\(alignmentAttribute(alignment(index)))>\(renderChildren(cell, options: options))</td>\n"
            }
            html += "</tr>\n"
        }
        html += "</tbody>\n</table>\n"
        return html
    }

    private static func alignmentAttribute(_ alignment: Table.ColumnAlignment?) -> String {
        switch alignment {
        case .center: return " style=\"text-align:center\""
        case .right: return " style=\"text-align:right\""
        default: return ""
        }
    }

    // MARK: - Inlines

    private static func renderChildren(_ node: Markup, options: Options, stripTaskPrefix: Bool = false) -> String {
        var out = ""
        for (index, child) in node.children.enumerated() {
            if stripTaskPrefix && index == 0, let text = child as? Text {
                out += renderInlineTextStrippingTaskPrefix(text)
            } else {
                out += renderInline(child, options: options)
            }
        }
        return out
    }

    private static func renderInlineTextStrippingTaskPrefix(_ text: Text) -> String {
        var string = text.string
        if string.hasPrefix("[ ]") || string.hasPrefix("[x]") || string.hasPrefix("[X]") {
            string = String(string.dropFirst(3))
        }
        return StringUtilities.htmlEscaped(string)
    }

    private static func renderInline(_ node: Markup, options: Options) -> String {
        switch node {
        case let text as Text:
            return StringUtilities.htmlEscaped(text.string)

        case let code as InlineCode:
            return "<code>\(StringUtilities.htmlEscaped(code.code))</code>"

        case let strong as Strong:
            return "<strong>\(renderChildren(strong, options: options))</strong>"

        case let emphasis as Emphasis:
            return "<em>\(renderChildren(emphasis, options: options))</em>"

        case let strikethrough as Strikethrough:
            return "<del>\(renderChildren(strikethrough, options: options))</del>"

        case let link as Link:
            let destination = link.destination ?? ""
            let inner = renderChildren(link, options: options)
            if let url = URL(string: destination), url.scheme == "http" || url.scheme == "https" || url.scheme == "mailto" {
                return "<a href=\"\(StringUtilities.htmlEscaped(destination))\" class=\"external-link\">\(inner)</a>"
            }
            // Internal/relative links become anchors the app can intercept.
            return "<a href=\"\(StringUtilities.htmlEscaped(destination))\" class=\"internal-link\">\(inner)</a>"

        case let image as Image:
            let src = image.source ?? ""
            let alt = StringUtilities.htmlEscaped(plainText(image))
            return "<img src=\"\(StringUtilities.htmlEscaped(src))\" alt=\"\(alt)\" loading=\"lazy\" />"

        case let softBreak as SoftBreak:
            _ = softBreak
            return "\n"

        case let lineBreak as LineBreak:
            _ = lineBreak
            return "<br />\n"

        case is InlineHTML:
            return "" // dropped for safety

        default:
            return renderChildren(node, options: options)
        }
    }

    // MARK: - Helpers

    static func plainText(_ node: Markup) -> String {
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

    public static func anchor(for title: String) -> String {
        let lowered = title.lowercased()
        var out = ""
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
            } else if out.last != "-" {
                out.append("-")
            }
        }
        return String(out.drop(while: { $0 == "-" })).trimmingCharacters(in: CharacterSet(charactersIn: "-")).isEmpty
            ? "section" : out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
