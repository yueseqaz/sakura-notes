import SwiftUI
import AppKit
import SakuraCore
import SakuraStorage

/// Custom tab strip above the editor.
struct TabBarView: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(model.tabs) { tab in
                        TabItemView(
                            environment: environment,
                            model: model,
                            tab: tab,
                            isActive: model.activeTabID == tab.id
                        )
                        .id(tab.id)
                    }
                }
            }
            .onChange(of: model.activeTabID) { id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .frame(height: 34)
        .overlay(alignment: .bottom) {
            HairlineDivider()
        }
    }
}

struct TabItemView: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var model: WorkspaceModel
    let tab: NoteTab
    let isActive: Bool

    private var session: NoteSession? {
        environment.session(for: tab.path)
    }

    var body: some View {
        HStack(spacing: DS.spaceXS) {
            if tab.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
            Image(systemName: session?.fileKind == .markdown ? "doc.text" : (session?.fileKind == .image ? "photo" : "doc"))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(session?.displayTitle ?? ((tab.path as NSString).lastPathComponent as NSString).deletingPathExtension)
                .font(DS.body(12))
                .lineLimit(1)
                .frame(maxWidth: 160)
            if session?.isDirty == true {
                Circle()
                    .fill(DS.accentColor(environment.settings.accentColorName))
                    .frame(width: 6, height: 6)
            }
            Button {
                model.closeTab(id: tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.8))
                    .padding(3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isActive ? 1 : 0.55)
        }
        .padding(.leading, DS.spaceM)
        .padding(.trailing, DS.spaceS)
        .frame(height: 34)
        .background(isActive ? Color(nsColor: .textBackgroundColor) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            model.activeTabID = tab.id
        }
        .contextMenu {
            Button(tab.pinned ? "Unpin Tab" : "Pin Tab") { model.togglePin(id: tab.id) }
            Divider()
            Button("Close Tab") { model.closeTab(id: tab.id) }
            Button("Close Other Tabs") { model.closeOtherTabs(id: tab.id) }
            Divider()
            Button("Reveal in Finder") {
                if let vault = environment.vault {
                    NSWorkspace.shared.activateFileViewerSelecting([vault.absoluteURL(for: tab.path)])
                }
            }
        }
        .onHover { hovering in
            if hovering { DispatchQueue.main.async { NSCursor.arrow.push() } }
        }
    }
}

/// The editor surface: tab strip, mode switcher, format toolbar, editor and
/// preview panes, outline/backlinks, and the status bar.
struct EditorArea: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: WorkspaceModel
    @Binding var showsQuickSwitcher: Bool

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(environment: environment, settings: settings, model: model)
            if let session = model.activeSession {
                editorContent(session: session)
            } else {
                noNoteState
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private func editorContent(session: NoteSession) -> some View {
        VStack(spacing: 0) {
            EditorToolbar(environment: environment, settings: settings, model: model, session: session)
            HairlineDivider()

            switch model.editorMode {
            case .edit:
                MarkdownEditorView(session: session, settings: settings, environment: environment)
                if settings.showsBacklinks {
                    BacklinksPanel(environment: environment, session: session)
                }
                StatusBar(session: session)
            case .preview:
                MarkdownPreviewView(session: session, settings: settings, environment: environment)
                StatusBar(session: session)
            case .split:
                VSplitView {
                    MarkdownEditorView(session: session, settings: settings, environment: environment)
                        .frame(minHeight: 120)
                    MarkdownPreviewView(session: session, settings: settings, environment: environment)
                        .frame(minHeight: 120)
                }
                if settings.showsBacklinks {
                    BacklinksPanel(environment: environment, session: session)
                }
                StatusBar(session: session)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if settings.showsOutline {
                OutlinePanel(session: session)
                    .padding(DS.spaceL)
            }
        }
        .overlay {
            // AI panel slides over the right edge; toggled from the toolbar.
            if settings.showsAIPanel {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    AIPanelView(environment: environment, settings: settings, session: session)
                        .frame(width: 320)
                }
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeOut(duration: 0.18), value: settings.showsAIPanel)
    }

    private var noNoteState: some View {
        EmptyStateView(
            symbol: "doc.text.magnifyingglass",
            title: "No note open",
            message: "Pick a note from the list, press ⌘O for the quick switcher, or create a new one.",
            actions: [
                ("Quick Switcher", { showsQuickSwitcher = true }),
            ]
        )
    }
}

/// Toolbar with formatting and view controls.
struct EditorToolbar: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var session: NoteSession

    var body: some View {
        HStack(spacing: DS.spaceS) {
            modePicker
            Divider().frame(height: 14)
            formatButtons
            Spacer()
            viewButtons
        }
        .padding(.horizontal, DS.spaceM)
        .padding(.vertical, DS.spaceXS)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var modePicker: some View {
        Picker("Mode", selection: $model.editorMode) {
            Image(systemName: "pencil.line").tag(EditorMode.edit)
            Image(systemName: "rectangle.split.2x1").tag(EditorMode.split)
            Image(systemName: "eye").tag(EditorMode.preview)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 150)
    }

    private var formatButtons: some View {
        HStack(spacing: 2) {
            toolButton("bold", "Bold (⌘B)") { NSApp.sendAction(#selector(EditorTextView.toggleBold(_:)), to: nil, from: nil) }
            toolButton("italic", "Italic (⌘I)") { NSApp.sendAction(#selector(EditorTextView.toggleItalic(_:)), to: nil, from: nil) }
            toolButton("strikethrough", "Strikethrough") { NSApp.sendAction(#selector(EditorTextView.toggleStrikethrough(_:)), to: nil, from: nil) }
            toolButton("link", "Link (⌘K)") { NSApp.sendAction(#selector(EditorTextView.makeLink(_:)), to: nil, from: nil) }
            toolButton("text.alignleft", "Heading (⌥⌘1–6)") {
                NSApp.sendAction(#selector(EditorTextView.toggleHeading(_:)), to: nil, from: headingMenuItem(2))
            }
            toolButton("checklist", "Task item") { NSApp.sendAction(#selector(EditorTextView.toggleTaskItem(_:)), to: nil, from: nil) }
            toolButton("tablecells", "Insert table") {
                NSApp.sendAction(#selector(EditorTextView.insertTable(_:)), to: nil, from: tableMenuItem("3x3"))
            }
            toolButton("curlybraces.square", "Code block") { NSApp.sendAction(#selector(EditorTextView.insertCodeBlock(_:)), to: nil, from: nil) }
        }
    }

    private var viewButtons: some View {
        HStack(spacing: 2) {
            toolButton("list.bullet.indent", settings.showsOutline ? "Hide outline" : "Show outline") {
                settings.showsOutline.toggle()
            }
            .opacity(settings.showsOutline ? 1 : 0.55)
            toolButton("link.badge.plus", settings.showsBacklinks ? "Hide backlinks" : "Show backlinks") {
                settings.showsBacklinks.toggle()
            }
            .opacity(settings.showsBacklinks ? 1 : 0.55)
            toolButton("clock.arrow.circlepath", "Version history") {
                NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "history"])
            }
            toolButton("sparkles", settings.showsAIPanel ? "Hide AI panel" : "Show AI panel") {
                settings.showsAIPanel.toggle()
            }
            .opacity(settings.showsAIPanel ? 1 : 0.55)
        }
    }

    private func toolButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func headingMenuItem(_ level: Int) -> NSMenuItem {
        let item = NSMenuItem()
        item.tag = level
        return item
    }

    private func tableMenuItem(_ dims: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.representedObject = dims
        return item
    }
}

/// Bottom status bar: counts, save state, external-file indicator.
struct StatusBar: View {
    @ObservedObject var session: NoteSession

    var body: some View {
        HStack(spacing: DS.spaceL) {
            Label("\(session.facts.wordCount) words", systemImage: "text.word.spacing")
            Text("\(session.facts.characterCount) chars")
            Label("\(session.facts.readingMinutes) min read", systemImage: "clock")
            if session.facts.openTaskCount > 0 {
                Label("\(session.facts.openTaskCount) open", systemImage: "checklist")
            }
            Spacer()
            saveStateView
        }
        .font(DS.caption())
        .foregroundColor(.secondary)
        .padding(.horizontal, DS.spaceL)
        .padding(.vertical, 5)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { HairlineDivider() }
    }

    @ViewBuilder
    private var saveStateView: some View {
        switch session.saveState {
        case .saved(let date):
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle")
                Text("Saved \(Self.timeString(date))")
            }
        case .dirty:
            HStack(spacing: 3) {
                Circle().fill(Color.orange).frame(width: 6, height: 6)
                Text("Unsaved")
            }
        case .saving:
            HStack(spacing: 3) {
                ProgressView().controlSize(.mini)
                Text("Saving…")
            }
        case .error(let message):
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text(message).lineLimit(1)
            }
        case .deletedExternally:
            HStack(spacing: 3) {
                Image(systemName: "trash").foregroundColor(.orange)
                Text("Deleted on disk — editing will recreate it")
            }
        }
    }

    static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// Collapsible outline (headings) panel.
struct OutlinePanel: View {
    @ObservedObject var session: NoteSession
    @VS private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: DS.spaceXS) {
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 10))
                    Text("Outline (\(session.facts.outline.count))")
                        .font(DS.caption())
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            if isExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(session.facts.outline) { entry in
                            Button {
                                NotificationCenter.default.post(
                                    name: .sakuraJumpToLine,
                                    object: nil,
                                    userInfo: ["line": entry.lineIndex]
                                )
                            } label: {
                                Text(String(repeating: "   ", count: entry.level - 1) + entry.title)
                                    .font(DS.secondary(11.5))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        if session.facts.outline.isEmpty {
                            Text("No headings yet")
                                .font(DS.caption())
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(DS.spaceS)
        .background(RoundedRectangle(cornerRadius: DS.radiusM).fill(.thinMaterial))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusM).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        .frame(width: 240)
    }
}

/// Backlinks panel under the editor.
struct BacklinksPanel: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var session: NoteSession
    @VS private var showsMentions = false

    var body: some View {
        let broken = environment.linkIndex.brokenLinks(from: session.path)
        VStack(alignment: .leading, spacing: DS.spaceXS) {
            let backlinks = environment.linkIndex.backlinks(to: session.path)
            let mentions = showsMentions ? environment.unlinkedMentions(of: session.displayTitle, excludingPath: session.path) : []
            HStack(spacing: DS.spaceS) {
                Text("Backlinks (\(backlinks.count))")
                    .font(DS.caption())
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                if !broken.isEmpty {
                    Text("· \(broken.count) broken link\(broken.count == 1 ? "" : "s")")
                        .font(DS.caption())
                        .foregroundColor(.orange)
                        .help("Wiki links in this note that don't resolve to any note")
                }
                Spacer()
                Button(showsMentions ? "Hide mentions" : "Unlinked mentions") {
                    showsMentions.toggle()
                }
                .font(DS.caption())
                .buttonStyle(.plain)
                .foregroundColor(DS.accentColor(environment.settings.accentColorName))
            }
            .padding(.horizontal, DS.spaceL)
            .padding(.top, DS.spaceS)

            if !broken.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(broken, id: \.self) { target in
                            Button {
                                if let entry = environment.createNote(inFolder: "", title: target) {
                                    NotificationCenter.default.post(name: .sakuraOpenNote, object: nil, userInfo: ["path": entry.relativePath])
                                }
                            } label: {
                                HStack(spacing: DS.spaceXS) {
                                    Image(systemName: "link.badge.plus")
                                        .font(.system(size: 9))
                                        .foregroundColor(.orange)
                                    Text("\(target) — click to create")
                                        .font(DS.secondary(12))
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, DS.spaceL)
                }
                .frame(maxHeight: 60)
            }

            if backlinks.isEmpty && mentions.isEmpty && broken.isEmpty {
                Text("No notes link here yet.")
                    .font(DS.caption())
                    .foregroundColor(.secondary.opacity(0.8))
                    .padding(.horizontal, DS.spaceL)
                    .padding(.bottom, DS.spaceS)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(backlinks, id: \.self) { path in
                            linkRow(path, label: ((path as NSString).lastPathComponent as NSString).deletingPathExtension, folder: (path as NSString).deletingLastPathComponent)
                        }
                        if showsMentions {
                            ForEach(mentions, id: \.self) { path in
                                linkRow(path, label: "mentions — " + ((path as NSString).lastPathComponent as NSString).deletingPathExtension, folder: (path as NSString).deletingLastPathComponent)
                            }
                        }
                    }
                    .padding(.horizontal, DS.spaceL)
                    .padding(.bottom, DS.spaceS)
                }
                .frame(maxHeight: 110)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { HairlineDivider() }
    }

    private func linkRow(_ path: String, label: String, folder: String) -> some View {
        Button {
            NotificationCenter.default.post(name: .sakuraOpenNote, object: nil, userInfo: ["path": path])
        } label: {
            HStack(spacing: DS.spaceXS) {
                Image(systemName: "arrow.turn.up.left")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Text(label)
                    .font(DS.secondary(12))
                if !folder.isEmpty {
                    Text(folder)
                        .font(DS.caption())
                        .foregroundColor(.secondary.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
