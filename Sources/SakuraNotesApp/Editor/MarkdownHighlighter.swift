import AppKit
import SakuraCore

/// Applies lightweight Markdown syntax attributes to editor text.
///
/// Attributes are applied in paragraph-aligned ranges so incremental
/// re-highlighting during typing is O(edited paragraph), not O(document).
enum MarkdownHighlighter {

    struct Palette {
        let heading: NSColor
        let bold: NSColor
        let italic: NSColor
        let code: NSColor
        let codeBackground: NSColor
        let link: NSColor
        let url: NSColor
        let quote: NSColor
        let marker: NSColor
        let tag: NSColor
        let dim: NSColor
        let taskDone: NSColor

        static func standard(dark: Bool) -> Palette {
            if dark {
                return Palette(
                    heading: NSColor(red: 0.95, green: 0.72, blue: 0.78, alpha: 1),
                    bold: .textColor,
                    italic: .textColor,
                    code: NSColor(red: 0.85, green: 0.87, blue: 0.92, alpha: 1),
                    codeBackground: NSColor(white: 1, alpha: 0.07),
                    link: NSColor(red: 0.55, green: 0.72, blue: 1.0, alpha: 1),
                    url: NSColor(white: 1, alpha: 0.45),
                    quote: NSColor(white: 1, alpha: 0.55),
                    marker: NSColor(red: 0.95, green: 0.62, blue: 0.72, alpha: 1),
                    tag: NSColor(red: 0.95, green: 0.62, blue: 0.72, alpha: 1),
                    dim: NSColor(white: 1, alpha: 0.38),
                    taskDone: NSColor(white: 1, alpha: 0.45)
                )
            }
            return Palette(
                heading: NSColor(red: 0.72, green: 0.25, blue: 0.42, alpha: 1),
                bold: .textColor,
                italic: .textColor,
                code: NSColor(red: 0.2, green: 0.25, blue: 0.35, alpha: 1),
                codeBackground: NSColor(white: 0, alpha: 0.06),
                link: NSColor(red: 0.15, green: 0.35, blue: 0.85, alpha: 1),
                url: NSColor(white: 0, alpha: 0.45),
                quote: NSColor(white: 0, alpha: 0.5),
                marker: NSColor(red: 0.78, green: 0.3, blue: 0.48, alpha: 1),
                tag: NSColor(red: 0.78, green: 0.3, blue: 0.48, alpha: 1),
                dim: NSColor(white: 0, alpha: 0.38),
                taskDone: NSColor(white: 0, alpha: 0.45)
            )
        }
    }

    /// Base style information the highlighter needs from the text view.
    struct BaseStyle {
        let font: NSFont
        let textColor: NSColor
        let lineSpacing: CGFloat
    }

    /// Highlights the given paragraph-aligned character range in `storage`.
    static func highlight(_ storage: NSMutableAttributedString, range: NSRange, base: BaseStyle, dark: Bool) {
        let palette = Palette.standard(dark: dark)
        let fullString = storage.string as NSString

        // Reset the range to base attributes first.
        let baseParagraph = NSMutableParagraphStyle()
        baseParagraph.lineSpacing = base.lineSpacing
        storage.setAttributes([
            .font: base.font,
            .foregroundColor: base.textColor,
            .paragraphStyle: baseParagraph,
        ], range: range)
        guard range.length > 0, range.location != NSNotFound else { return }

        // Process line by line within the range.
        let lineStart = fullString.lineRange(for: NSRange(location: range.location, length: 0)).location
        let endLocation = range.location + range.length
        var lineRange = fullString.lineRange(for: NSRange(location: lineStart, length: 0))
        var inCodeFence = false

        while lineRange.location < endLocation && lineRange.location != NSNotFound {
            let line = fullString.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                applyFenceMark(storage, lineRange: lineRange, palette: palette, base: base)
                // Toggle code block state; highlight the whole fence line dim.
                storage.addAttribute(.foregroundColor, value: palette.dim, range: safeRange(lineRange, in: fullString.length))
                inCodeFence.toggle()
                lineRange = nextLine(fullString, from: lineRange)
                continue
            }
            if inCodeFence {
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: monoFont(from: base.font, size: base.font.pointSize - 1),
                    .foregroundColor: palette.code,
                    .backgroundColor: palette.codeBackground,
                ]
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = base.lineSpacing
                attributes[.paragraphStyle] = paragraph
                storage.setAttributes(attributes, range: safeRange(lineRange, in: fullString.length))
                lineRange = nextLine(fullString, from: lineRange)
                continue
            }
            // Front matter
            if trimmed == "---" && (lineRange.location == 0 || isWithinFrontMatter(fullString, at: lineRange.location)) {
                storage.addAttribute(.foregroundColor, value: palette.dim, range: safeRange(lineRange, in: fullString.length))
                lineRange = nextLine(fullString, from: lineRange)
                continue
            }

            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let headingFont = headingFont(from: base.font, level: min(level, 6))
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: headingFont,
                    .foregroundColor: palette.heading,
                ]
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = base.lineSpacing
                paragraph.paragraphSpacingBefore = level <= 2 ? 8 : 4
                attributes[.paragraphStyle] = paragraph
                storage.setAttributes(attributes, range: safeRange(lineRange, in: fullString.length))
            } else if trimmed.hasPrefix(">") {
                storage.addAttribute(.foregroundColor, value: palette.quote, range: safeRange(lineRange, in: fullString.length))
                storage.addAttribute(.font, value: italicFont(from: base.font), range: safeRange(lineRange, in: fullString.length))
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                storage.addAttribute(.foregroundColor, value: palette.dim, range: safeRange(lineRange, in: fullString.length))
            } else {
                // Inline highlighting for normal lines.
                highlightInline(storage, lineRange: lineRange, base: base, palette: palette, fullString: fullString)
                highlightListMarkers(storage, lineRange: lineRange, palette: palette, fullString: fullString, base: base)
            }
            lineRange = nextLine(fullString, from: lineRange)
        }
    }

    private static func isWithinFrontMatter(_ string: NSString, at location: Int) -> Bool {
        guard string.length >= 4 else { return false }
        guard string.substring(to: 4).hasPrefix("---") else { return false }
        // Treat a "---" line as front matter if it appears at or before the
        // closing delimiter within the first ~8 KB of the document.
        let searchLength = min(string.length - 4, 8000)
        guard searchLength > 0 else { return false }
        let closeRange = string.range(of: "\n---", options: [], range: NSRange(location: 4, length: searchLength))
        return location <= closeRange.location + 1
    }

    private static func highlightInline(_ storage: NSMutableAttributedString, lineRange: NSRange, base: BaseStyle, palette: Palette, fullString: NSString) {
        let line = fullString.substring(with: lineRange)
        let lineStart = lineRange.location
        guard line.count < 10_000 else { return }

        func apply(_ pattern: String, options: NSRegularExpression.Options = [], attributes: (NSTextCheckingResult) -> [NSAttributedString.Key: Any], groups: Int = 1) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            let range = NSRange(location: 0, length: (line as NSString).length)
            for match in regex.matches(in: line, range: range) {
                let attrs = attributes(match)
                let targetRange: NSRange
                if groups == 1, match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
                    targetRange = match.range(at: 1)
                } else {
                    targetRange = match.range
                }
                guard targetRange.location != NSNotFound else { continue }
                let absolute = NSRange(location: lineStart + targetRange.location, length: targetRange.length)
                storage.addAttributes(attrs, range: absolute)
                // Dim the delimiters themselves.
                let fullMatch = match.range
                let fullAbsolute = NSRange(location: lineStart + fullMatch.location, length: fullMatch.length)
                for (markerRange, color) in delimiterRanges(fullMatch: fullMatch, inner: targetRange) {
                    storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: lineStart + markerRange.location, length: markerRange.length))
                }
            }
        }

        func delimiterRanges(fullMatch: NSRange, inner: NSRange) -> [(NSRange, NSColor)] {
            var result: [(NSRange, NSColor)] = []
            let beforeLength = inner.location - fullMatch.location
            if beforeLength > 0 {
                result.append((NSRange(location: fullMatch.location, length: beforeLength), palette.dim))
            }
            let afterLocation = inner.location - fullMatch.location + inner.length
            let afterLength = fullMatch.length - afterLocation
            if afterLength > 0 {
                result.append((NSRange(location: fullMatch.location + afterLocation, length: afterLength), palette.dim))
            }
            return result
        }

        // Inline code
        apply(#"`([^`\n]+)`"#, attributes: { _ in
            [.font: monoFont(from: base.font, size: base.font.pointSize - 1),
             .foregroundColor: palette.code,
             .backgroundColor: palette.codeBackground]
        })
        // Bold
        apply(#"(\*\*|__)(?=\S)([\s\S]*?\S)\1"#, attributes: { _ in
            [.font: boldFont(from: base.font)]
        })
        // Italic
        apply(#"(?<![*_\w])(\*|_)(?=\S)([^*_\n]+)\1(?![*_\w])"#, attributes: { _ in
            [.font: italicFont(from: base.font)]
        })
        // Strikethrough
        apply(#"~~(?=\S)([\s\S]*?\S)~~"#, attributes: { _ in
            [.strikethroughStyle: NSUnderlineStyle.single.rawValue,
             .foregroundColor: palette.dim]
        })
        // Links [text](url)
        apply(#"(!?)\[([^\]\n]*)\]\(([^)\n]+)\)"#, attributes: { match in
            let isImage = (line as NSString).substring(with: match.range(at: 1)) == "!"
            return [
                .foregroundColor: isImage ? palette.url : palette.link,
                .underlineStyle: isImage ? 0 : NSUnderlineStyle.single.rawValue,
            ]
        }, groups: 3)
        // Wikilinks [[target]]
        apply(#"\[\[([^\]\n]+)\]\]"#, attributes: { _ in
            [.foregroundColor: palette.link,
             .underlineStyle: NSUnderlineStyle.single.rawValue]
        })
        // Bare URLs
        apply(#"(?<![\(\"'])(https?://[^\s\)>\]]+)"#, attributes: { _ in
            [.foregroundColor: palette.link,
             .underlineStyle: NSUnderlineStyle.single.rawValue]
        })
        // Tags
        apply(#"(?<![\w#&])#([\p{L}\p{N}_\-/]+)"#, attributes: { _ in
            [.foregroundColor: palette.tag]
        })
        // Checked / unchecked boxes
        apply(#"(\[x\])"#, options: [.caseInsensitive], attributes: { _ in
            [.foregroundColor: palette.taskDone,
             .strikethroughStyle: NSUnderlineStyle.single.rawValue]
        })
        apply(#"(\[ \])"#, attributes: { _ in
            [.foregroundColor: palette.marker]
        })
    }

    private static func highlightListMarkers(_ storage: NSMutableAttributedString, lineRange: NSRange, palette: Palette, fullString: NSString, base: BaseStyle) {
        let line = fullString.substring(with: lineRange)
        guard let regex = try? NSRegularExpression(pattern: #"^(\s*)([-*+]|\d+\.)\s+(\[[ xX]\])?\s?"#) else { return }
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: range) else { return }
        let marker = match.range(at: 2)
        if marker.location != NSNotFound {
            storage.addAttribute(.foregroundColor, value: palette.marker, range: NSRange(location: lineRange.location + marker.location, length: marker.length))
            storage.addAttribute(.font, value: boldFont(from: base.font), range: NSRange(location: lineRange.location + marker.location, length: marker.length))
        }
    }

    private static func applyFenceMark(_ storage: NSMutableAttributedString, lineRange: NSRange, palette: Palette, base: BaseStyle) {
        storage.addAttribute(.font, value: monoFont(from: base.font, size: base.font.pointSize - 1), range: safeRange(lineRange, in: (storage.string as NSString).length))
    }

    // MARK: - Fonts

    static func headingFont(from base: NSFont, level: Int) -> NSFont {
        let scale: [CGFloat] = [1.5, 1.3, 1.15, 1.05, 1.0, 0.95]
        let size = base.pointSize * scale[min(max(level, 1), 6) - 1]
        let resized = NSFontManager.shared.convert(base, toSize: size)
        return NSFontManager.shared.convert(resized, toHaveTrait: .boldFontMask)
    }

    static func boldFont(from base: NSFont) -> NSFont {
        NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
    }

    static func italicFont(from base: NSFont) -> NSFont {
        NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
    }

    static func monoFont(from base: NSFont, size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func safeRange(_ range: NSRange, in length: Int) -> NSRange {
        let clampedLocation = min(range.location, max(0, length))
        let clampedLength = min(range.length, max(0, length - clampedLocation))
        return NSRange(location: clampedLocation, length: clampedLength)
    }

    static func nextLine(_ string: NSString, from range: NSRange) -> NSRange {
        let end = range.location + range.length
        guard end < string.length else { return NSRange(location: string.length, length: 0) }
        return string.lineRange(for: NSRange(location: end, length: 0))
    }
}
