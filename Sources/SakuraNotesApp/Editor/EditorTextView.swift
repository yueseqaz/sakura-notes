import AppKit
import SakuraCore
import SakuraStorage

/// The editor's NSTextView: plain-text markdown editing with syntax
/// highlighting, automatic list continuation, image paste/drop, formatting
/// selectors (target of menu shortcuts), and wikilink autocomplete.
final class EditorTextView: NSTextView {

    /// Called when the user pastes/drops an image. The app layer stores it
    /// and returns the relative markdown link to insert.
    var onImageDropped: ((NSImage, String?) -> Void)?
    /// Called when the user Cmd-clicks a wiki link.
    var onWikiLinkActivated: ((String) -> Void)?
    /// Suggestions provider for "[[" autocomplete.
    var wikiLinkSuggestionProvider: ((String) -> [String])?
    /// Attachments folder relative path (for drag & drop paths).
    var attachmentsFolder: String = "Attachments"

    // MARK: - Setup

    func configure(base: MarkdownHighlighter.BaseStyle, dark: Bool, writingWidth: CGFloat, spellCheck: Bool) {
        isRichText = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticLinkDetectionEnabled = false
        smartInsertDeleteEnabled = false
        isContinuousSpellCheckingEnabled = spellCheck
        isGrammarCheckingEnabled = false
        drawsBackground = false

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = base.lineSpacing
        defaultParagraphStyle = paragraph
        typingAttributes = [
            .font: base.font,
            .foregroundColor: base.textColor,
            .paragraphStyle: paragraph,
        ]
        insertionPointColor = dark ? NSColor(red: 0.95, green: 0.72, blue: 0.78, alpha: 1) : .controlAccentColor
        self.writingWidth = writingWidth
        recomputeInsets()
        highlightAll()
    }

    private var storedWritingWidth: CGFloat = 680

    var writingWidth: CGFloat {
        get { storedWritingWidth }
        set {
            storedWritingWidth = max(320, newValue)
            recomputeInsets()
        }
    }

    override func layout() {
        super.layout()
        recomputeInsetsIfNeeded()
    }

    private var lastLayoutWidth: CGFloat = -1

    private func recomputeInsetsIfNeeded() {
        if abs(bounds.width - lastLayoutWidth) > 1 {
            recomputeInsets()
        }
    }

    private func recomputeInsets() {
        lastLayoutWidth = bounds.width
        let horizontalMargin = max(0, (bounds.width - storedWritingWidth) / 2)
        textContainerInset = NSSize(width: horizontalMargin, height: 14)
    }

    func setBaseStyle(_ base: MarkdownHighlighter.BaseStyle, dark: Bool) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = base.lineSpacing
        defaultParagraphStyle = paragraph
        typingAttributes = [
            .font: base.font,
            .foregroundColor: base.textColor,
            .paragraphStyle: paragraph,
        ]
        highlightAll()
    }

    // MARK: - Highlighting

    /// A custom text storage would be cleaner, but attaching a lightweight
    /// pass on didChangeText keeps behavior transparent and undo-safe.
    func highlightAll() {
        guard let storage = textStorage else { return }
        let base = currentBaseStyle()
        let storageMutable = storage as NSMutableAttributedString
        MarkdownHighlighter.highlight(
            storageMutable,
            range: NSRange(location: 0, length: storageMutable.length),
            base: base,
            dark: effectiveAppearance.isDark
        )
    }

    /// Highlights only the paragraphs overlapping `range`, expanded a little.
    func highlightAround(_ range: NSRange) {
        guard let storage = textStorage else { return }
        let string = storage.string as NSString
        let expanded = string.lineRange(for: MarkdownHighlighter.safeRange(range, in: string.length))
        // Include one extra line before/after for multi-line constructs.
        let withBefore = string.lineRange(for: NSRange(location: max(0, expanded.location - 1), length: 0))
        let start = withBefore.location
        let endLocation = min(string.length, expanded.location + expanded.length + 200)
        let length = endLocation - start
        guard length > 0 else { return }
        MarkdownHighlighter.highlight(
            storage as NSMutableAttributedString,
            range: NSRange(location: start, length: length),
            base: currentBaseStyle(),
            dark: effectiveAppearance.isDark
        )
    }

    private func currentBaseStyle() -> MarkdownHighlighter.BaseStyle {
        MarkdownHighlighter.BaseStyle(
            font: font ?? .systemFont(ofSize: 15),
            textColor: .textColor,
            lineSpacing: defaultParagraphStyle?.lineSpacing ?? 6
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        highlightAll()
    }

    override func didChangeText() {
        super.didChangeText()
        let editedRange = selectedRange()
        highlightAround(NSRange(location: max(0, editedRange.location - 2), length: editedRange.length + 4))
    }

    // MARK: - List continuation

    struct ListMarker {
        let indentation: String
        let marker: String   // "-", "1.", "- [ ]"
        var isEmpty: Bool    // marker with no content following
    }

    /// Parses the list marker (if any) at the start of the line containing `location`.
    func listMarker(atLocation location: Int) -> ListMarker? {
        guard let storage = textStorage else { return nil }
        let string = storage.string as NSString
        guard location <= string.length else { return nil }
        let lineRange = string.lineRange(for: NSRange(location: min(location, string.length), length: 0))
        let line = string.substring(with: lineRange)
        let pattern = #"^(\s*)(?:([-*+])|(\d+)(\.))\s+(\[[ xX]\]\s+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: (line as NSString).length)
        guard let match = regex.firstMatch(in: line, range: range) else { return nil }
        let nsLine = line as NSString
        let indentation = nsLine.substring(with: match.range(at: 1))
        let bullet = match.range(at: 2).location != NSNotFound
            ? nsLine.substring(with: match.range(at: 2))
            : "\(nsLine.substring(with: match.range(at: 3)))."
        var marker = bullet
        if match.range(at: 5).location != NSNotFound {
            marker += " " + nsLine.substring(with: match.range(at: 5)).trimmingCharacters(in: .whitespaces) + " "
        }
        let rest = nsLine.substring(from: match.range.upperBound).trimmingCharacters(in: .whitespaces)
        return ListMarker(indentation: indentation, marker: marker, isEmpty: rest.isEmpty)
    }

    override func insertNewline(_ sender: Any?) {
        guard let marker = listMarker(atLocation: selectedRange().location) else {
            super.insertNewline(sender)
            return
        }
        if marker.isEmpty {
            // Empty list item: remove the marker and exit the list.
            guard let storage = textStorage else { return }
            let string = storage.string as NSString
            let location = selectedRange().location
            let lineRange = string.lineRange(for: NSRange(location: min(location, string.length), length: 0))
            let line = string.substring(with: lineRange)
            if let regex = try? NSRegularExpression(pattern: #"^(\s*)(?:[-*+]|\d+\.)\s+(\[[ xX]\]\s+)?"#),
               let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let removalRange = NSRange(location: lineRange.location + match.range.location, length: match.range.length)
                setSelectedRange(NSRange(location: removalRange.location, length: 0))
                insertText("", replacementRange: removalRange)
            } else {
                super.insertNewline(sender)
            }
            return
        }
        // Continue the list. Ordered lists increment their number.
        var nextMarker = marker.marker
        if let numberOnly = nextMarker.matchFirst(#"^(\d+)\."#) {
            let incremented = (Int(numberOnly) ?? 1) + 1
            nextMarker = nextMarker.replacingOccurrences(of: #"^\d+\."#, with: "\(incremented).", options: .regularExpression)
        }
        super.insertNewline(sender)
        insertText("\(marker.indentation)\(nextMarker) ", replacementRange: selectedRange())
    }

    override func insertTab(_ sender: Any?) {
        // Tab inside a list indents the item; otherwise default behavior.
        if listMarker(atLocation: selectedRange().location) != nil {
            insertText("  ", replacementRange: selectedRange())
        } else {
            super.insertTab(sender)
        }
    }

    // MARK: - Formatting selectors (menu/keyboard targets)

    @objc func toggleBold(_ sender: Any?) { wrapSelection("**") }
    @objc func toggleItalic(_ sender: Any?) { wrapSelection("*") }
    @objc func toggleStrikethrough(_ sender: Any?) { wrapSelection("~~") }
    @objc func toggleInlineCode(_ sender: Any?) { wrapSelection("`") }

    @objc func makeLink(_ sender: Any?) {
        let selection = selectedString()
        if let url = selection.firstURLIfAny() {
            // Selection is a URL: wrap as []()
            let text = "[Markdown](\(url))"
            insertText(text, replacementRange: selectedRange())
            setSelectedRange(NSRange(location: selectedRange().location + 1, length: 8))
        } else {
            let text = "[\(selection)](url)"
            insertText(text, replacementRange: selectedRange())
            let urlStart = selectedRange().location + (selection as NSString).length + 3
            setSelectedRange(NSRange(location: urlStart, length: 3))
        }
    }

    @objc func insertWikiLink(_ sender: Any?) {
        let selection = selectedString()
        let text = "[[\(selection)]]"
        insertText(text, replacementRange: selectedRange())
        let inner = NSRange(location: selectedRange().location + 2, length: (selection as NSString).length)
        setSelectedRange(inner)
        triggerWikiLinkSuggestions()
    }

    @objc func insertCodeBlock(_ sender: Any?) {
        let text = "\n```swift\n\n```\n"
        insertText(text, replacementRange: selectedRange())
        let start = selectedRange().location + 3 + 6 + 1
        setSelectedRange(NSRange(location: start, length: 0))
    }

    @objc func toggleTaskItem(_ sender: Any?) {
        guard let storage = textStorage else { return }
        let string = storage.string as NSString
        let location = selectedRange().location
        let lineRange = string.lineRange(for: NSRange(location: min(location, string.length), length: 0))
        let line = string.substring(with: lineRange)
        let pattern = #"^(\s*(?:[-*+]|\d+\.)\s+)\[([ xX])\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else {
            // No checkbox: add one after the list marker (or create a task line).
            let barePattern = #"^(\s*(?:[-*+]|\d+\.)\s+)"#
            if let bareRegex = try? NSRegularExpression(pattern: barePattern),
               let bareMatch = bareRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let insertLocation = lineRange.location + bareMatch.range(at: 1).upperBound
                insertText("[ ] ", replacementRange: NSRange(location: insertLocation, length: 0))
            } else {
                insertText("- [ ] ", replacementRange: NSRange(location: lineRange.location, length: 0))
            }
            return
        }
        let bracketRange = NSRange(location: lineRange.location + match.range(at: 2).location, length: 1)
        let current = string.substring(with: bracketRange)
        let replacement = current == " " ? "x" : " "
        insertText(replacement, replacementRange: bracketRange)
    }

    @objc func toggleHeading(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem else { return }
        let level = menuItem.tag // 1...6, 0 = plain
        guard let storage = textStorage else { return }
        let string = storage.string as NSString
        let location = selectedRange().location
        let lineRange = string.lineRange(for: NSRange(location: min(location, string.length), length: 0))
        let line = string.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = String(repeating: "#", count: level) + " "
        var newLine: String
        if level == 0 {
            newLine = line.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
        } else if let existing = line.matchFirst(#"^#{1,6}\s+(.*)$"#) {
            newLine = prefix + existing
        } else {
            newLine = prefix + line
        }
        insertText(newLine, replacementRange: lineRange)
    }

    @objc func insertTable(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem else { return }
        let dims = menuItem.representedObject as? String ?? "3x3"
        let parts = dims.components(separatedBy: "x")
        let rows = Int(parts.first ?? "3") ?? 3
        let cols = Int(parts.last ?? "3") ?? 3
        var table = "\n"
        table += "| " + Array(repeating: "Column", count: cols).enumerated().map { "\($0.offset + 1)" }.joined(separator: " | ") + " |\n"
        table += "|" + Array(repeating: " --- ", count: cols).joined(separator: "|") + "|\n"
        for _ in 0..<max(1, rows - 1) {
            table += "| " + Array(repeating: " ", count: cols).joined(separator: " | ") + " |\n"
        }
        insertText(table, replacementRange: selectedRange())
    }

    // MARK: - Selection helpers

    private func selectedString() -> String {
        guard let storage = textStorage else { return "" }
        let range = selectedRange()
        guard range.location != NSNotFound, range.length > 0 else { return "" }
        return (storage.string as NSString).substring(with: MarkdownHighlighter.safeRange(range, in: (storage.string as NSString).length))
    }

    private func wrapSelection(_ delimiter: String) {
        let selection = selectedString()
        guard !selection.isEmpty else {
            insertText(delimiter + delimiter, replacementRange: selectedRange())
            let cursor = selectedRange().location + (delimiter as NSString).length
            setSelectedRange(NSRange(location: cursor, length: 0))
            return
        }
        // Toggle off when already wrapped.
        let full = (textStorage?.string as NSString?) ?? ""
        let range = selectedRange()
        let beforeStart = range.location - delimiter.count
        if beforeStart >= 0 && range.location + range.length + delimiter.count <= full.length {
            let before = full.substring(with: NSRange(location: beforeStart, length: delimiter.count))
            let after = full.substring(with: NSRange(location: range.location + range.length, length: delimiter.count))
            if before == delimiter && after == delimiter {
                let expanded = NSRange(location: beforeStart, length: range.length + 2 * delimiter.count)
                insertText(selection, replacementRange: expanded)
                return
            }
        }
        insertText(delimiter + selection + delimiter, replacementRange: range)
    }

    // MARK: - Image paste & drop

    override func paste(_ sender: Any?) {
        if handleImageFromPasteboard() { return }
        super.paste(sender)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Cmd+V with an image on the pasteboard.
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" {
            if handleImageFromPasteboard() { return true }
        }
        return super.performKeyEquivalent(with: event)
    }

    private func handleImageFromPasteboard() -> Bool {
        let pasteboard = NSPasteboard.general
        if pasteboard.data(forType: .png) != nil || pasteboard.data(forType: .tiff) != nil {
            guard let image = NSImage(pasteboard: pasteboard) else { return false }
            onImageDropped?(image, nil)
            return true
        }
        // File URLs that are images.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls where Self.isImageURL(url) {
                if let image = NSImage(contentsOf: url) {
                    onImageDropped?(image, url.lastPathComponent)
                    return true
                }
            }
        }
        return false
    }

    static func isImageURL(_ url: URL) -> Bool {
        TextFileKind.classify(fileExtension: url.pathExtension) == .image
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            var insertedAny = false
            for url in urls {
                if Self.isImageURL(url), let image = NSImage(contentsOf: url) {
                    onImageDropped?(image, url.lastPathComponent)
                    insertedAny = true
                } else if url.isFileURL && !Self.isImageURL(url) {
                    // Markdown or other file: insert a relative link.
                    let name = url.lastPathComponent
                    insertText("[\(name)](\(name))", replacementRange: selectedRange())
                    insertedAny = true
                }
            }
            return insertedAny
        }
        if let image = NSImage(pasteboard: pasteboard) {
            onImageDropped?(image, nil)
            return true
        }
        return super.performDragOperation(sender)
    }

    // MARK: - Wiki link activation (Cmd-click)

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let clicked = wikiLinkUnderCursor(with: event) {
            onWikiLinkActivated?(clicked)
            return
        }
        super.mouseDown(with: event)
    }

    private func wikiLinkUnderCursor(with event: NSEvent) -> String? {
        guard let storage = textStorage else { return nil }
        let string = storage.string as NSString
        let windowPoint = convert(event.locationInWindow, from: nil)
        guard let layoutManager = layoutManager, let container = textContainer else { return nil }
        let characterIndex = layoutManager.characterIndex(for: windowPoint, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
        guard characterIndex < string.length else { return nil }
        // Search backwards and forwards for [[...]] boundaries.
        var start = characterIndex
        while start > 0 && string.character(at: start - 1) != 0x5B { start -= 1 }
        var end = characterIndex
        while end < string.length - 1 && string.character(at: end + 1) != 0x5D { end += 1 }
        guard start >= 1, end <= string.length - 2,
              string.character(at: start - 1) == 0x5B, string.character(at: start - 2) == 0x5B,
              string.character(at: end + 1) == 0x5D, string.character(at: end + 2) == 0x5D else { return nil }
        let inner = string.substring(with: NSRange(location: start, length: end - start + 1))
        let target = inner.components(separatedBy: "|").first?.components(separatedBy: "#").first ?? ""
        return target.isEmpty ? nil : target.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Outline navigation

    /// Scrolls to the given 0-based line and places the caret there.
    func jumpToLine(_ line: Int) {
        guard let storage = textStorage else { return }
        let string = storage.string as NSString
        var location = 0
        var currentLine = 0
        while currentLine < line && location < string.length {
            let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
            location = lineRange.location + lineRange.length
            currentLine += 1
        }
        let target = min(location, string.length)
        setSelectedRange(NSRange(location: target, length: 0))
        scrollRangeToVisible(NSRange(location: target, length: min(300, max(0, string.length - target))))
        window?.makeFirstResponder(self)
    }

    // MARK: - Wiki link autocomplete

    private(set) var isShowingCompletions = false
    private var completionItems: [String] = []
    private var completionOriginalQuery = ""
    private var completionInsertStart: Int = 0

    func triggerWikiLinkSuggestions() {
        guard let storage = textStorage, let provider = wikiLinkSuggestionProvider else { return }
        let string = storage.string as NSString
        let location = selectedRange().location
        // Find the last "[[" before the caret with no closing "]]" or newline between.
        let searchStart = max(0, location - 80)
        let range = NSRange(location: searchStart, length: location - searchStart)
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]\n]*)$"#) else { return }
        guard let match = regex.firstMatch(in: string as String, range: range),
              match.range(at: 1).location != NSNotFound else {
            hideCompletions()
            return
        }
        let queryStart = match.range(at: 1).location
        let query = string.substring(with: NSRange(location: queryStart, length: location - queryStart))
        completionOriginalQuery = query
        completionInsertStart = queryStart
        let suggestions = provider(query)
        completionItems = suggestions
        if suggestions.isEmpty {
            hideCompletions()
        } else {
            showCompletionWindow()
        }
    }

    private var completionPanel: NSPanel?

    private func showCompletionWindow() {
        isShowingCompletions = true
        NotificationCenter.default.post(name: .editorCompletionsChanged, object: self, userInfo: [
            "items": completionItems,
            "query": completionOriginalQuery,
        ])
    }

    func hideCompletions() {
        guard isShowingCompletions else { return }
        isShowingCompletions = false
        NotificationCenter.default.post(name: .editorCompletionsChanged, object: self, userInfo: nil)
    }

    func acceptCompletion(_ item: String) {
        let text = item + "]]"
        let length = selectedRange().location - completionInsertStart
        let replaceRange = NSRange(location: completionInsertStart, length: length)
        hideCompletions()
        insertText(text, replacementRange: replaceRange)
        setSelectedRange(NSRange(location: completionInsertStart + (text as NSString).length, length: 0))
    }

    override func keyDown(with event: NSEvent) {
        if isShowingCompletions {
            switch event.keyCode {
            case 53: // Escape
                hideCompletions()
                return
            case 125, 126: // Down / Up — handled by the completion list UI
                NotificationCenter.default.post(name: .editorCompletionNavigate, object: self, userInfo: ["keyCode": Int(event.keyCode)])
                return
            case 36: // Return
                NotificationCenter.default.post(name: .editorCompletionAccept, object: self, userInfo: nil)
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
        if isShowingCompletions || selectedRange().location > 0 {
            triggerWikiLinkSuggestionsIfNeededAfterKey()
        }
    }

    private func triggerWikiLinkSuggestionsIfNeededAfterKey() {
        guard let storage = textStorage else { return }
        let string = storage.string as NSString
        let location = selectedRange().location
        guard location >= 2 else { hideCompletions(); return }
        let two = string.substring(with: NSRange(location: location - 2, length: 2))
        if two == "[[" {
            triggerWikiLinkSuggestions()
        } else if isShowingCompletions {
            triggerWikiLinkSuggestions() // refresh with the new query
        }
    }
}

extension String {
    func matchFirst(_ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = self as NSString
        guard let match = regex.firstMatch(in: self, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    func firstURLIfAny() -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let matches = detector.matches(in: self, range: NSRange(location: 0, length: (self as NSString).length))
        return matches.first?.url?.absoluteString
    }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

extension Notification.Name {
    static let editorCompletionsChanged = Notification.Name("com.sakuranotes.editorCompletionsChanged")
    static let editorCompletionNavigate = Notification.Name("com.sakuranotes.editorCompletionNavigate")
    static let editorCompletionAccept = Notification.Name("com.sakuranotes.editorCompletionAccept")
}
