import SwiftUI
import AppKit
import SakuraCore
import SakuraStorage

// MARK: - Quick Switcher

/// ⌘O overlay: fuzzy-jump to any note.
struct QuickSwitcherView: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var environment: AppEnvironment
    @Binding var isPresented: Bool
    @VS private var query: String = ""
    @VS private var selectedIndex: Int = 0
    @FocusState private var fieldFocused: Bool

    private var candidates: [NoteEntry] {
        let notes = environment.vault?.notes ?? []
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.isEmpty {
            return recentFirst(notes: notes)
        }
        return scoredMatches(notes: notes, query: trimmed)
    }

    private func recentFirst(notes: [NoteEntry]) -> [NoteEntry] {
        let recents = environment.workspaceStore.recentFiles(forWorkspace: environment.vault?.rootURL.path ?? "")
        var entries: [NoteEntry] = []
        let byPath = Dictionary(uniqueKeysWithValues: notes.map { ($0.relativePath, $0) })
        for path in recents {
            if let entry = byPath[path] { entries.append(entry) }
        }
        for entry in notes where !entries.contains(entry) { entries.append(entry) }
        return Array(entries.prefix(12))
    }

    private func scoredMatches(notes: [NoteEntry], query: String) -> [NoteEntry] {
        var scored: [(NoteEntry, Int)] = []
        for entry in notes {
            let title = entry.displayName.lowercased()
            let path = entry.relativePath.lowercased()
            var score = 0
            if title.hasPrefix(query) { score += 100 }
            if title.contains(query) { score += 50 }
            if path.contains(query) { score += 25 }
            if title.contains(query.first ?? " ") { score += 5 }
            score += max(0, 20 - title.count / 4)
            if score > 0 { scored.append((entry, score)) }
        }
        scored.sort { lhs, rhs in
            if lhs.1 == rhs.1 { return lhs.0.displayName.count < rhs.0.displayName.count }
            return lhs.1 > rhs.1
        }
        return Array(scored.prefix(12).map(\.0))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.spaceS) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Jump to note…", text: $query)
                    .textFieldStyle(.plain)
                    .font(DS.title(16))
                    .focused($fieldFocused)
                    .onSubmit { open(selectedIndex) }
            }
            .padding(DS.spaceL)
            HairlineDivider()
            if candidates.isEmpty {
                Text("No matching notes")
                    .font(DS.secondary(12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(DS.spaceXL)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, entry in
                                Button {
                                    open(index)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.displayName)
                                                .font(DS.body(13.5))
                                                .fontWeight(index == selectedIndex ? .semibold : .regular)
                                            Text(entry.relativePath)
                                                .font(DS.caption())
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        Spacer()
                                        if index == selectedIndex {
                                            Text("⏎")
                                                .font(DS.caption())
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, DS.spaceL)
                                    .padding(.vertical, DS.spaceS)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .background(index == selectedIndex ? Color.primary.opacity(0.08) : Color.clear)
                                .onHover { hovering in
                                    if hovering { selectedIndex = index }
                                }
                                .id(index)
                            }
                        }
                        .padding(.vertical, DS.spaceS)
                    }
                    .frame(maxHeight: 380)
                    .onChange(of: selectedIndex) { index in
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 540)
        .background(RoundedRectangle(cornerRadius: DS.radiusL).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusL).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .onAppear { fieldFocused = true }
        .background(keyHandler)
    }

    private var keyHandler: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onExitCommand {
                isPresented = false
            }
            .overlay(
                // Up/Down navigation via keyboard events on the window.
                KeyEventCatcher(onUp: {
                    selectedIndex = max(0, selectedIndex - 1)
                }, onDown: {
                    selectedIndex = min(candidates.count - 1, selectedIndex + 1)
                })
                .frame(width: 0, height: 0)
            )
    }

    private func open(_ index: Int) {
        guard index < candidates.count else { return }
        let entry = candidates[index]
        model.openNote(path: entry.relativePath, forceNewTab: NSApp.currentEvent?.modifierFlags.contains(.shift) == true)
        isPresented = false
    }
}

/// Catches arrow-key events for overlay lists (SwiftUI lacks native support
/// in plain overlays).
struct KeyEventCatcher: NSViewRepresentable {
    let onUp: () -> Void
    let onDown: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onUp = onUp
        view.onDown = onDown
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onUp = onUp
        nsView.onDown = onDown
    }

    final class CatcherView: NSView {
        var onUp: (() -> Void)?
        var onDown: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 126: onUp?()
            case 125: onDown?()
            default: super.keyDown(with: event)
            }
        }
    }
}

// MARK: - Command palette

/// ⌘K overlay: run any app command.
struct CommandPaletteView: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var environment: AppEnvironment
    @Binding var isPresented: Bool
    @VS private var query: String = ""
    @VS private var selectedIndex: Int = 0
    @FocusState private var fieldFocused: Bool

    struct Command: Identifiable {
        let id: String
        let title: String
        let shortcut: String
        let action: () -> Void
    }

    private var commands: [Command] {
        [
            Command(id: "newNote", title: "New Note", shortcut: "⌘N") {
                NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "newNote"])
            },
            Command(id: "newFolder", title: "New Folder…", shortcut: "⇧⌘N") {
                NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "newFolder"])
            },
            Command(id: "dailyNote", title: "Open Today's Note", shortcut: "⇧⌘D") {
                NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "dailyNote"])
            },
            Command(id: "togglePreview", title: "Toggle Editor / Preview", shortcut: "⌘R") {
                NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "togglePreview"])
            },
            Command(id: "toggleSidebar", title: "Toggle Sidebar", shortcut: "⌥⌘S") {
                NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "toggleSidebar"])
            },
            Command(id: "toggleAIPanel", title: "Toggle AI Assistant", shortcut: "⌥⌘A") {
                NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "toggleAIPanel"])
            },
            Command(id: "graph", title: "Show Knowledge Graph", shortcut: "⌥⌘G") {
                NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "graph"])
            },
            Command(id: "tasks", title: "Show All Tasks", shortcut: "⌥⌘T") {
                NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "tasks"])
            },
            Command(id: "history", title: "Version History…", shortcut: "⌥⌘H") {
                NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "history"])
            },
            Command(id: "renameNote", title: "Rename Note…", shortcut: "") {
                NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "renameNote"])
            },
            Command(id: "duplicateNote", title: "Duplicate Note", shortcut: "") {
                NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "duplicateNote"])
            },
            Command(id: "trashNote", title: "Move Note to Trash", shortcut: "⌫") {
                NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "trashNote"])
            },
            Command(id: "revealNote", title: "Reveal in Finder", shortcut: "⌥⌘R") {
                NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "revealNote"])
            },
            Command(id: "exportHTML", title: "Export as HTML…", shortcut: "") {
                NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "exportHTML"])
            },
            Command(id: "exportPDF", title: "Export as PDF…", shortcut: "") {
                NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "exportPDF"])
            },
            Command(id: "exportMarkdown", title: "Export as Markdown…", shortcut: "") {
                NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "exportMarkdown"])
            },
            Command(id: "importFolder", title: "Import Folder of Notes…", shortcut: "") {
                NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "importFolder"])
            },
            Command(id: "reindex", title: "Rebuild Search Index", shortcut: "") {
                NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "reindex"])
            },
            Command(id: "closeTab", title: "Close Tab", shortcut: "⌘W") {
                NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "closeTab"])
            },
        ]
    }

    private var filtered: [Command] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.isEmpty { return commands }
        return commands.filter { $0.title.lowercased().contains(trimmed) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.spaceS) {
                Image(systemName: "command")
                    .foregroundColor(.secondary)
                TextField("Type a command…", text: $query)
                    .textFieldStyle(.plain)
                    .font(DS.title(16))
                    .focused($fieldFocused)
                    .onSubmit { run(selectedIndex) }
            }
            .padding(DS.spaceL)
            HairlineDivider()
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, command in
                        Button {
                            run(index)
                        } label: {
                            HStack {
                                Text(command.title)
                                    .font(DS.body(13.5))
                                    .fontWeight(index == selectedIndex ? .semibold : .regular)
                                Spacer()
                                Text(command.shortcut)
                                    .font(DS.caption())
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, DS.spaceL)
                            .padding(.vertical, DS.spaceS)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(index == selectedIndex ? Color.primary.opacity(0.08) : Color.clear)
                        .onHover { hovering in
                            if hovering { selectedIndex = index }
                        }
                    }
                }
                .padding(.vertical, DS.spaceS)
            }
            .frame(maxHeight: 340)
        }
        .frame(width: 500)
        .background(RoundedRectangle(cornerRadius: DS.radiusL).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusL).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .onAppear { fieldFocused = true }
        .background(
            KeyEventCatcher(onUp: { selectedIndex = max(0, selectedIndex - 1) }, onDown: {
                selectedIndex = min(filtered.count - 1, selectedIndex + 1)
            })
            .frame(width: 0, height: 0)
        )
        .onExitCommand { isPresented = false }
    }

    private func run(_ index: Int) {
        guard index < filtered.count else { return }
        let command = filtered[index]
        isPresented = false
        command.action()
    }
}

// MARK: - Conflict resolution

/// Sheet shown when local edits collide with an external modification.
struct ConflictResolutionSheet: View {
    @ObservedObject var environment: AppEnvironment
    let conflict: ConflictInfo
    let onDismiss: () -> Void
    @VS private var comparison: LineDiff.Result?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: DS.spaceXS) {
                Label("External changes detected", systemImage: "exclamationmark.triangle.fill")
                    .font(DS.title(15))
                    .foregroundColor(.orange)
                Text("“\((conflict.path as NSString).lastPathComponent)” was modified by another application while you had unsaved edits. Your version was never overwritten — a snapshot of the external file is in version history.")
                    .font(DS.secondary(12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.spaceL)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                diffColumn(title: "Your version", lines: changedLines(from: comparison, side: .local))
                HairlineDivider()
                diffColumn(title: "On disk", lines: changedLines(from: comparison, side: .external))
            }
            .frame(maxHeight: 280)

            HStack {
                Spacer()
                Button("Keep Mine") { resolve(.keepLocal) }
                Button("Take Theirs") { resolve(.takeExternal) }
                Button("Keep Both") { resolve(.keepBoth) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(DS.spaceL)
        }
        .frame(width: 640)
        .onAppear {
            comparison = LineDiff.diff(conflict.externalText, conflict.localText)
        }
    }

    enum DiffSide { case local, external }

    private func changedLines(from result: LineDiff.Result?, side: DiffSide) -> [String] {
        guard let result else { return [] }
        var lines: [String] = []
        for op in result.operations {
            switch (op, side) {
            case (.equal(let shared), _):
                lines.append(contentsOf: shared.prefix(3))
                if shared.count > 3 { lines.append("…") }
            case (.insert(let inserted, _), .local):
                lines.append(contentsOf: inserted.map { "+ \($0)" })
            case (.delete(let deleted, _), .external):
                lines.append(contentsOf: deleted.map { "− \($0)" })
            default:
                break
            }
        }
        return Array(lines.prefix(60))
    }

    private func diffColumn(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: DS.spaceXS) {
            Text(title)
                .font(DS.caption())
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            ScrollView {
                Text(lines.isEmpty ? "(no differences)" : lines.joined(separator: "\n"))
                    .font(DS.mono(10.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(DS.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resolve(_ choice: NoteSession.ConflictChoice) {
        guard let session = environment.session(for: conflict.path) else {
            onDismiss()
            return
        }
        session.resolveConflict(choice)
        onDismiss()
    }
}

// MARK: - Version history sheet

struct HistorySheet: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var model: WorkspaceModel
    @Binding var isPresented: Bool
    @VS private var snapshots: [NoteSnapshot] = []
    @VS private var selectedSnapshot: NoteSnapshot?
    @VS private var selectedContent: String = ""
    @VS private var isRestoring = false

    var body: some View {
        HStack(spacing: 0) {
            // Snapshot list
            VStack(alignment: .leading, spacing: 0) {
                Text("Version History")
                    .font(DS.title(14))
                    .padding(DS.spaceM)
                if snapshots.isEmpty {
                    Text("No snapshots for this note yet.\nSnapshots are created before overwrites, conflict resolution, and AI edits.")
                        .font(DS.caption())
                        .foregroundColor(.secondary)
                        .padding(.horizontal, DS.spaceM)
                }
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(snapshots) { snapshot in
                            Button {
                                select(snapshot)
                            } label: {
                                HStack {
                                    Text(Self.format(snapshot.timestamp))
                                        .font(DS.body(12))
                                    Spacer()
                                    Text("\(snapshot.byteSize) B")
                                        .font(DS.caption())
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, DS.spaceM)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(selectedSnapshot == snapshot ? Color.primary.opacity(0.08) : Color.clear)
                        }
                    }
                }
            }
            .frame(width: 210)
            .background(Color(nsColor: .windowBackgroundColor))

            // Diff view
            VStack(spacing: 0) {
                if let snapshot = selectedSnapshot {
                    ScrollView {
                        Text(diffText)
                            .font(DS.mono(11))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DS.spaceM)
                            .textSelection(.enabled)
                    }
                    HStack {
                        Text("Compared with the current buffer")
                            .font(DS.caption())
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Restore This Version") {
                            restore(snapshot)
                        }
                        .disabled(isRestoring)
                        Button("Close") { isPresented = false }
                            .keyboardShortcut(.cancelAction)
                    }
                    .padding(DS.spaceM)
                } else {
                    EmptyStateView(
                        symbol: "clock.arrow.circlepath",
                        title: "Select a snapshot",
                        message: "Choose a version on the left to compare it with the current text."
                    )
                }
            }
        }
        .frame(width: 720, height: 460)
        .onAppear(perform: load)
    }

    private var diffText: String {
        guard let session = model.activeSession else { return "" }
        let result = LineDiff.diff(session.text, selectedContent)
        var lines: [String] = []
        for op in result.operations {
            switch op {
            case .equal(let shared):
                lines.append(contentsOf: shared.map { "  \($0)" })
            case .insert(let inserted, _):
                lines.append(contentsOf: inserted.map { "+ \($0)" })
            case .delete(let deleted, _):
                lines.append(contentsOf: deleted.map { "− \($0)" })
            }
        }
        return lines.joined(separator: "\n")
    }

    private func load() {
        guard let vault = environment.vault, let path = model.activeTab?.path else { return }
        snapshots = environment.snapshotStore.list(vaultRoot: vault.rootURL, relativePath: path)
        selectedSnapshot = snapshots.first
        if let first = snapshots.first {
            selectedContent = environment.snapshotStore.content(vaultRoot: vault.rootURL, of: first) ?? ""
        }
    }

    private func select(_ snapshot: NoteSnapshot) {
        selectedSnapshot = snapshot
        guard let vault = environment.vault else { return }
        selectedContent = environment.snapshotStore.content(vaultRoot: vault.rootURL, of: snapshot) ?? ""
    }

    private func restore(_ snapshot: NoteSnapshot) {
        guard let vault = environment.vault else { return }
        isRestoring = true
        do {
            try environment.snapshotStore.restore(vaultRoot: vault.rootURL, snapshot: snapshot, to: vault)
            if let session = model.activeSession, session.path == snapshot.relativePath {
                session.reloadFromDisk()
            }
            load()
        } catch {
            environment.presentError(error)
        }
        isRestoring = false
    }

    static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
