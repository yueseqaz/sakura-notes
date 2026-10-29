import SwiftUI
import AppKit
import SakuraCore
import SakuraStorage

/// SwiftUI wrapper around the AppKit editor text view.
struct MarkdownEditorView: NSViewRepresentable {
    @ObservedObject var session: NoteSession
    @ObservedObject var settings: SettingsStore
    let environment: AppEnvironment

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = EditorTextView()
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.allowsUndo = true

        scrollView.documentView = textView
        context.coordinator.textView = textView

        textView.onImageDropped = { image, suggestedName in
            context.coordinator.handleImageInsert(image: image, suggestedName: suggestedName)
        }
        textView.onWikiLinkActivated = { target in
            context.coordinator.activateWikiLink(target)
        }
        textView.wikiLinkSuggestionProvider = { query in
            context.coordinator.suggestions(for: query)
        }
        applyStyle(to: textView, context: context)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? EditorTextView else { return }
        context.coordinator.session = session
        context.coordinator.environment = environment
        // Sync external text changes (reload, conflict resolution, AI edits)
        // without disturbing the text view when the text matches.
        if textView.string != session.text {
            let selection = textView.selectedRange()
            textView.string = session.text
            textView.highlightAll()
            let maxLocation = (session.text as NSString).length
            if selection.location != NSNotFound && selection.location <= maxLocation {
                textView.setSelectedRange(selection)
            }
        }
        if context.coordinator.lastAppliedFontName != settings.editorFontName
            || context.coordinator.lastAppliedFontSize != settings.editorFontSize
            || context.coordinator.lastAppliedLineSpacing != settings.editorLineSpacing {
            applyStyle(to: textView, context: context)
        }
        if abs(textView.writingWidth - settings.writingWidth) > 1 {
            textView.writingWidth = CGFloat(settings.writingWidth)
        }
        textView.isContinuousSpellCheckingEnabled = settings.spellCheckEnabled
    }

    private func applyStyle(to textView: EditorTextView, context: Context) {
        let font = Self.editorFont(settings: settings)
        let base = MarkdownHighlighter.BaseStyle(
            font: font,
            textColor: .textColor,
            lineSpacing: CGFloat(settings.editorLineSpacing)
        )
        textView.configure(
            base: base,
            dark: textView.effectiveAppearance.isDark,
            writingWidth: CGFloat(settings.writingWidth),
            spellCheck: settings.spellCheckEnabled
        )
        context.coordinator.lastAppliedFontName = settings.editorFontName
        context.coordinator.lastAppliedFontSize = settings.editorFontSize
        context.coordinator.lastAppliedLineSpacing = settings.editorLineSpacing
    }

    static func editorFont(settings: SettingsStore) -> NSFont {
        let size = CGFloat(settings.editorFontSize)
        if settings.editorFontName == "System Design" {
            return .systemFont(ofSize: size)
        }
        if settings.editorFontName == "New York" {
            return NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: "New York"]), size: size)
                ?? .systemFont(ofSize: size)
        }
        return NSFont(name: settings.editorFontName, size: size) ?? .systemFont(ofSize: size)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var textView: EditorTextView?
        var environment: AppEnvironment?
        var session: NoteSession?
        var lastAppliedFontName: String = ""
        var lastAppliedFontSize: Double = 0
        var lastAppliedLineSpacing: Double = 0
        private var lastPublishedSelectionLength: Int = -1
        private var completionController: WikiLinkCompletionController?
        private var observers: [NSObjectProtocol] = []

        override init() {
            super.init()
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: .editorCompletionsChanged, object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                let items = note.userInfo?["items"] as? [String] ?? []
                if items.isEmpty {
                    self.hideCompletions()
                } else if let textView = self.textView {
                    self.showCompletions(for: textView, items: items)
                }
            })
            observers.append(center.addObserver(forName: .editorCompletionNavigate, object: nil, queue: .main) { [weak self] note in
                guard let self, let keyCode = note.userInfo?["keyCode"] as? Int else { return }
                self.completionController?.handleNavigation(keyCode: keyCode)
            })
            observers.append(center.addObserver(forName: .editorCompletionAccept, object: nil, queue: .main) { [weak self] _ in
                self?.completionController?.acceptSelected()
            })
            observers.append(center.addObserver(forName: .sakuraJumpToLine, object: nil, queue: .main) { [weak self] note in
                guard let self, let textView = self.textView, let line = note.userInfo?["line"] as? Int else { return }
                textView.jumpToLine(line)
            })
        }

        deinit {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, let session else { return }
            session.textDidChange(textView.string)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView, let session else { return }
            let range = textView.selectedRange()
            if range.length != lastPublishedSelectionLength {
                lastPublishedSelectionLength = range.length
                session.selectedRange = range
                session.selectedText = range.length > 0
                    ? ((textView.string as NSString).substring(with: range))
                    : ""
            }
            if textView.isShowingCompletions {
                textView.triggerWikiLinkSuggestions()
            }
        }

        // MARK: - Image insertion

        func handleImageInsert(image: NSImage, suggestedName: String?) {
            guard let environment, let textView else { return }
            guard let path = AttachmentManager.saveImage(
                image,
                suggestedName: suggestedName,
                environment: environment
            ) else {
                NSSound.beep()
                return
            }
            let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            let markdown = "![\(name)](\(path))"
            textView.insertText(markdown, replacementRange: textView.selectedRange())
            session?.textDidChange(textView.string)
        }

        // MARK: - Wiki links

        func activateWikiLink(_ target: String) {
            guard let environment else { return }
            let folder = session.map { ($0.path as NSString).deletingLastPathComponent } ?? ""
            let resolved = environment.linkIndex.resolve(target: target, fromFolder: folder)
            if let resolved {
                NotificationCenter.default.post(name: .sakuraOpenNote, object: nil, userInfo: ["path": resolved])
            } else {
                // Offer to create the note with this title.
                NotificationCenter.default.post(name: .sakuraCreateNoteWithTitle, object: nil, userInfo: ["title": target])
            }
        }

        func suggestions(for query: String) -> [String] {
            guard let environment else { return [] }
            let lowered = query.lowercased()
            var titles = Set<String>()
            var paths: [String] = []
            for (path, facts) in environment.factsCache {
                let title = facts.title ?? (path as NSString).lastPathComponent
                if lowered.isEmpty || title.lowercased().contains(lowered) || path.lowercased().contains(lowered) {
                    titles.insert(title)
                    paths.append(path)
                }
            }
            let sortedTitles = titles.sorted { $0.count < $1.count }
            let sortedPaths = paths.sorted { $0.count < $1.count }.prefix(8)
            var result = Array(sortedTitles.prefix(8))
            for path in sortedPaths where result.count < 12 && !result.contains((path as NSString).deletingPathExtension) {
                result.append(path)
            }
            return result
        }

        func showCompletions(for textView: EditorTextView, items: [String]) {
            if completionController == nil {
                completionController = WikiLinkCompletionController()
            }
            guard let controller = completionController else { return }
            let caretRect = textView.firstRectForCurrentInsertionPoint()
            controller.present(items: items, near: caretRect, textView: textView)
        }

        func hideCompletions() {
            completionController?.dismiss()
        }
    }
}

/// Saves pasted/dropped images into the vault's attachments folder.
enum AttachmentManager {

    @MainActor
    static func saveImage(_ image: NSImage, suggestedName: String?, environment: AppEnvironment) -> String? {
        guard let vault = environment.vault else { return nil }
        let folder = environment.settings.attachmentsFolder
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }

        let cleanBase = StringUtilities.sanitizedFileName(
            ((suggestedName ?? "image") as NSString).deletingPathExtension
        )
        let fileName = "\(Int(Date().timeIntervalSince1970))-\(cleanBase).png"
        let relativePath = "\(folder)/\(fileName)"
        do {
            try vault.ensureFolder(folder)
            try vault.writeData(png, toRelativePath: relativePath)
            return relativePath
        } catch {
            environment.presentError(error)
            return nil
        }
    }
}

extension EditorTextView {
    func firstRectForCurrentInsertionPoint() -> NSRect {
        guard let layoutManager, let textContainer else { return .zero }
        let range = selectedRange()
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let containerOrigin = textContainerOrigin
        let viewRect = NSRect(
            x: rect.origin.x + containerOrigin.x,
            y: rect.origin.y + containerOrigin.y,
            width: rect.width,
            height: rect.height
        )
        return window?.convertToScreen(convert(viewRect, to: nil)) ?? .zero
    }
}
