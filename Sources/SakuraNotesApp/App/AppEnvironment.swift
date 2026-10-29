import Foundation
import Combine
import AppKit
import SakuraCore
import SakuraStorage
import SakuraSearch
import SakuraAI

/// A pending conflict between local unsaved edits and an external change.
struct ConflictInfo: Identifiable, Equatable {
    let id: String
    let path: String
    let localText: String
    let externalText: String
}

/// Central dependency container and coordinator for one app run.
/// Owns the current vault, its derived indexes, and the note sessions
/// (one per open note buffer).
@MainActor
final class AppEnvironment: ObservableObject {

    static let shared = AppEnvironment()

    let settings: SettingsStore
    let workspaceStore: WorkspaceStore
    let snapshotStore: SnapshotStore
    let keychain: KeychainStore
    let client: OpenAIClient

    @Published private(set) var vault: VaultStore?
    @Published private(set) var searchCoordinator: SearchCoordinator?
    @Published private(set) var linkIndex = LinkIndex()
    /// Cached analysis per note, refreshed as notes change. Powers tags,
    /// tasks, and outline UIs without rescanning on every keystroke.
    @Published private(set) var factsCache: [String: NoteFacts] = [:]
    @Published var conflicts: [ConflictInfo] = []
    @Published var lastVaultError: String?
    /// Bumped whenever the link graph changed, so graph views re-render.
    @Published private(set) var graphVersion: Int = 0

    private let workQueue = DispatchQueue(label: "com.sakuranotes.facts", qos: .utility)
    private var pendingFactPaths = Set<String>()
    private var factsFlushItem: DispatchWorkItem?
    /// Sessions keep buffers alive even when their tab is temporarily gone.
    private(set) var sessions: [String: NoteSession] = [:]

    init(settings: SettingsStore = SettingsStore(),
         workspaceStore: WorkspaceStore = WorkspaceStore(),
         snapshotBase: URL? = nil) {
        self.settings = settings
        self.workspaceStore = workspaceStore
        self.snapshotStore = SnapshotStore(baseDirectory: snapshotBase ?? SnapshotStore.defaultBaseDirectory())
        self.keychain = .shared
        self.client = OpenAIClient()
        workspaceStore.pruneMissing()
    }

    // MARK: - Vault lifecycle

    var activeProviderConfig: AIProviderConfig? { settings.activeAIProvider }
    func apiKey() -> String? {
        guard let config = activeProviderConfig else { return nil }
        return keychain.get(forAccount: "ai.\(config.id)")
    }

    func openWorkspace(at url: URL) {
        do {
            let newVault = try VaultStore(rootURL: url)
            newVault.showsHiddenFiles = settings.showsHiddenFiles
            newVault.delegate = self
            vault = newVault
            lastVaultError = nil

            let dbURL = Self.indexDatabaseURL(forVault: url)
            let index = FTSIndex(databaseURL: dbURL)
            let coordinator = SearchCoordinator(index: index)
            searchCoordinator = coordinator
            linkIndex.removeAll()
            factsCache = [:]
            graphVersion += 1
            coordinator.attach(vault: newVault)
            // Seed facts + link graph from the full note list.
            enqueueFacts(newVault.notes.map(\.relativePath))

            workspaceStore.add(workspace: Workspace(
                name: url.lastPathComponent,
                path: url.path
            ))
        } catch {
            lastVaultError = error.localizedDescription
        }
    }

    func closeWorkspace() {
        flushAllSessions()
        vault?.delegate = nil
        searchCoordinator?.detach()
        vault = nil
        searchCoordinator = nil
        linkIndex.removeAll()
        factsCache = [:]
        sessions.removeAll()
        conflicts.removeAll()
        graphVersion += 1
    }

    static func indexDatabaseURL(forVault vaultURL: URL) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = support.appendingPathComponent("SakuraNotes/Indexes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(SnapshotStore.vaultFolderName(for: vaultURL) + ".sqlite")
    }

    /// Last opened workspace URL, if its directory still exists.
    var lastWorkspaceURL: URL? {
        workspaceStore.pruneMissing()
        return workspaceStore.mostRecentlyUsed().map { URL(fileURLWithPath: $0.path) }
    }

    // MARK: - Sessions

    func session(for path: String) -> NoteSession? {
        sessions[path]
    }

    @discardableResult
    func makeSession(for path: String) -> NoteSession? {
        guard let vault else { return nil }
        if let existing = sessions[path] { return existing }
        guard let session = try? NoteSession(path: path, vault: vault, environment: self) else { return nil }
        sessions[path] = session
        workspaceStore.recordRecentFile(workspacePath: vault.rootURL.path, relativePath: path)
        return session
    }

    func dropSession(for path: String) {
        sessions.removeValue(forKey: path)
    }

    /// Saves every dirty session (used at quit time).
    func flushAllSessions() {
        for session in sessions.values {
            if session.isDirty {
                session.saveNow(showErrors: false)
            }
        }
    }

    var dirtySessionCount: Int {
        sessions.values.filter(\.isDirty).count
    }

    // MARK: - Facts pipeline

    private func enqueueFacts(_ paths: [String]) {
        for path in paths { pendingFactPaths.insert(path) }
        factsFlushItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let paths = Array(self.pendingFactPaths)
            self.pendingFactPaths.removeAll()
            guard let vault = self.vault else { return }
            for path in paths {
                guard let content = try? vault.readNote(path) else { continue }
                let name = (path as NSString).lastPathComponent
                let facts = NoteAnalyzer.analyze(markdown: content, fileName: (name as NSString).deletingPathExtension)
                Task { @MainActor in
                    self.factsCache[path] = facts
                    self.linkIndex.update(path: path, facts: facts)
                    self.graphVersion += 1
                }
            }
        }
        factsFlushItem = item
        workQueue.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    /// Convenience: the workspace display name.
    var workspaceName: String { vault?.rootURL.lastPathComponent ?? "" }

    // MARK: - Note operations invoked from UI

    func createNote(inFolder folder: String, title: String, content: String = "") -> NoteEntry? {
        guard let vault else { return nil }
        do {
            return try vault.createNote(folder: folder, title: title, content: content.isEmpty ? "# \(title)\n\n" : content)
        } catch {
            presentError(error)
            return nil
        }
    }

    func presentError(_ error: Error) {
        lastVaultError = error.localizedDescription
        NSSound.beep()
    }

    // MARK: - Tag overview

    struct TagSummary: Identifiable {
        var id: String { name }
        let name: String
        let count: Int
    }

    func tagSummaries() -> [TagSummary] {
        var counts: [String: Int] = [:]
        for facts in factsCache.values {
            for tag in facts.allTags {
                counts[tag, default: 0] += 1
            }
        }
        return counts
            .map { TagSummary(name: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    /// Notes carrying a given tag (exact, or a descendant of a hierarchical tag).
    func notes(withTag tag: String) -> [String] {
        let lowerTag = tag.lowercased()
        return factsCache
            .filter { path, facts in
                facts.allTags.contains { $0.lowercased() == lowerTag || $0.lowercased().hasPrefix(lowerTag + "/") }
            }
            .map(\.key)
            .sorted()
    }

    // MARK: - Daily notes & templates

    /// Creates (or opens) today's daily note; returns its path.
    func openTodayNote() -> String? {
        guard let vault else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let title = formatter.string(from: Date())
        let folder = settings.dailyNotesFolder
        let relativePath = "\(folder)/\(title).md"
        if vault.noteEntry(at: relativePath) != nil {
            return relativePath
        }
        do {
            _ = try vault.createNote(folder: folder, title: title, content: dailyNoteContent(for: Date()))
            return relativePath
        } catch {
            presentError(error)
            return nil
        }
    }

    func dailyNoteContent(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let weekday = DateFormatter()
        weekday.dateFormat = "EEEE"
        return "# \(formatter.string(from: date))\n\n> \(weekday.string(from: date))\n\n## Notes\n\n## Tasks\n- [ ] \n"
    }

    /// Template files in the vault's templates folder.
    func templateFiles() -> [NoteEntry] {
        guard let vault else { return [] }
        let folder = settings.templatesFolder
        return vault.notes.filter { $0.folderPath == folder && vault.isMarkdown($0.relativePath) }
    }

    func newNoteFromTemplate(_ template: NoteEntry, title: String, inFolder folder: String) -> NoteEntry? {
        guard let vault, let raw = try? vault.readNote(template.relativePath) else { return nil }
        let engine = TemplateEngine(title: title)
        let expanded = engine.expand(raw)
        return createNote(inFolder: folder, title: title, content: expanded)
    }

    /// Toggles a task checkbox in the given note without requiring it to be open.
    func toggleTask(path: String, lineIndex: Int) {
        if let session = session(for: path) {
            session.toggleTask(atLine: lineIndex)
            return
        }
        guard let vault else { return }
        guard var content = try? vault.readNote(path) else { return }
        var lines = content.components(separatedBy: "\n")
        guard lineIndex < lines.count else { return }
        let line = lines[lineIndex]
        if let range = line.range(of: "[ ]") {
            lines[lineIndex] = line.replacingCharacters(in: range, with: "[x]")
        } else if let range = line.range(of: "[x]", options: .caseInsensitive) {
            lines[lineIndex] = line.replacingCharacters(in: range, with: "[ ]")
        } else {
            return
        }
        content = lines.joined(separator: "\n")
        do {
            try vault.writeNote(path, content: content)
        } catch {
            presentError(error)
        }
    }

    /// Creates a note for a wiki link target that doesn't resolve yet.
    func createNoteForWikiLink(_ title: String) {
        guard let vault else { return }
        let folder = vault.folderNode(at: selectedDefaultFolder()) != nil ? selectedDefaultFolder() : ""
        _ = createNote(inFolder: folder, title: title, content: "# \(title)\n\n")
    }

    /// Creates a note from a template with a generated title and opens it.
    @discardableResult
    func newNoteFromTemplateAndOpen(_ template: NoteEntry) -> NoteEntry? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let title = template.displayName + " " + formatter.string(from: Date())
        guard let entry = newNoteFromTemplate(template, title: title, inFolder: "") else { return nil }
        NotificationCenter.default.post(name: .sakuraOpenNote, object: nil, userInfo: ["path": entry.relativePath])
        return entry
    }

    private func selectedDefaultFolder() -> String { "" }

    /// Notes mentioning `title` in their body without linking to `path`.
    func unlinkedMentions(of title: String, excludingPath path: String) -> [String] {
        guard let coordinator = searchCoordinator, !title.isEmpty else { return [] }
        let containing = coordinator.notesContaining(text: title, excludingPath: path)
        let linked = Set(linkIndex.backlinks(to: path))
        return containing.filter { !linked.contains($0) }
    }
}

// MARK: - VaultDelegate

extension AppEnvironment: @preconcurrency VaultDelegate {

    func vault(_ vault: VaultStore, notesAdded: [NoteEntry]) {
        searchCoordinator?.vault(vault, notesAdded: notesAdded)
        enqueueFacts(notesAdded.map(\.relativePath))
    }

    func vault(_ vault: VaultStore, notesModified: [NoteEntry]) {
        searchCoordinator?.vault(vault, notesModified: notesModified)
        enqueueFacts(notesModified.map(\.relativePath))
        for note in notesModified {
            Task { @MainActor in
                self.sessions[note.relativePath]?.externalFileChanged(onDiskDate: note.modificationDate)
            }
        }
    }

    func vault(_ vault: VaultStore, notesRemoved: [String]) {
        searchCoordinator?.vault(vault, notesRemoved: notesRemoved)
        for path in notesRemoved {
            if let facts = factsCache.removeValue(forKey: path) {
                _ = facts
            }
            linkIndex.remove(path: path)
            Task { @MainActor in
                self.sessions[path]?.noteDeletedExternally()
            }
        }
        graphVersion += 1
    }

    func vault(_ vault: VaultStore, movedFrom: String, to: String) {
        searchCoordinator?.vault(vault, movedFrom: movedFrom, to: to)
        if let facts = factsCache.removeValue(forKey: movedFrom) {
            factsCache[to] = facts
        }
        linkIndex.rename(from: movedFrom, to: to)
        graphVersion += 1
        NotificationCenter.default.post(
            name: .sakuraNoteMoved,
            object: nil,
            userInfo: ["from": movedFrom, "to": to, "vault": vault.rootURL]
        )
        // Keep internal links pointing at the moved item.
        let report = LinkUpdater.updateLinksAfterMove(
            vault: vault,
            search: searchCoordinator,
            snapshots: snapshotStore,
            from: movedFrom,
            to: to
        )
        if report.notesUpdated > 0 {
            lastVaultError = "Updated \(report.linksRewritten) link(s) in \(report.notesUpdated) note(s) to follow the move."
        }
    }

    func vaultDidReload(_ vault: VaultStore) {
        // Link rename cascades (e.g. folder renamed in Finder) are handled by
        // the moved events above; nothing else to do here.
    }
}

extension Notification.Name {
    /// A note (or folder) moved within the vault. userInfo: from, to, vault.
    static let sakuraNoteMoved = Notification.Name("com.sakuranotes.noteMoved")
    /// A note was opened and should be selected. userInfo: path.
    static let sakuraOpenNote = Notification.Name("com.sakuranotes.openNote")
    /// Quick capture should toggle.
    static let sakuraToggleQuickCapture = Notification.Name("com.sakuranotes.toggleQuickCapture")
    /// Commands from the menu system. userInfo: command id.
    static let sakuraCommand = Notification.Name("com.sakuranotes.command")
    /// A wiki link pointed at a note that doesn't exist. userInfo: title.
    static let sakuraCreateNoteWithTitle = Notification.Name("com.sakuranotes.createNoteWithTitle")
    /// Global search should open with a query. userInfo: query.
    static let sakuraOpenSearch = Notification.Name("com.sakuranotes.openSearch")
    /// An AI action should run on the current note. userInfo: AIAction raw value.
    static let sakuraRunAIAction = Notification.Name("com.sakuranotes.runAIAction")
    /// Export commands. userInfo: kind ("html" | "pdf" | "markdown").
    static let sakuraExport = Notification.Name("com.sakuranotes.export")
    /// Rename a folder. userInfo: path.
    static let sakuraRenameFolder = Notification.Name("com.sakuranotes.renameFolder")
    /// Jump the editor caret to a 0-based line. userInfo: line (Int).
    static let sakuraJumpToLine = Notification.Name("com.sakuranotes.jumpToLine")
}
