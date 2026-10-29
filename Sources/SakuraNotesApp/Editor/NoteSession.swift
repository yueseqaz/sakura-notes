import Foundation
import Combine
import AppKit
import SakuraCore
import SakuraStorage

/// The state of one open note buffer: text, dirty flag, autosave, facts, and
/// conflict handling. One instance per open note, shared across tabs showing
/// the same file.
@MainActor
final class NoteSession: ObservableObject, Identifiable {

    enum SaveState: Equatable {
        case saved(Date)
        case dirty
        case saving
        case error(String)
        case deletedExternally
    }

    nonisolated let id = UUID()
    let path: String
    let fileKind: TextFileKind

    @Published var text: String
    @Published private(set) var isDirty: Bool = false
    @Published private(set) var saveState: SaveState
    @Published private(set) var facts: NoteFacts
    @Published var conflict: ConflictInfo?
    @Published private(set) var externallyDeleted: Bool = false
    /// Selection reported by the editor (for AI actions on selection).
    @Published var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @Published var selectedText: String = ""

    private weak var vault: VaultStore?
    private weak var environment: AppEnvironment?
    private var lastSyncedDate: Date
    private var autosaveItem: DispatchWorkItem?
    private var factsItem: DispatchWorkItem?
    private var isSaving = false
    private let serialSaveQueue = DispatchQueue(label: "com.sakuranotes.save", qos: .userInitiated)

    var displayName: String {
        (path as NSString).lastPathComponent
    }

    var displayTitle: String {
        (displayName as NSString).deletingPathExtension
    }

    var lastSynced: Date { lastSyncedDate }

    init(path: String, vault: VaultStore, environment: AppEnvironment) throws {
        self.path = path
        self.vault = vault
        self.environment = environment
        self.fileKind = TextFileKind.classify(fileExtension: (path as NSString).pathExtension)
        let content = try vault.readNote(path)
        self.text = content
        self.lastSyncedDate = vault.currentModificationDate(of: path) ?? Date()
        let name = (path as NSString).lastPathComponent
        self.facts = NoteAnalyzer.analyze(markdown: content, fileName: (name as NSString).deletingPathExtension)
        self.saveState = .saved(lastSyncedDate)
    }

    // MARK: - Editing

    /// Called by the editor on every change.
    func textDidChange(_ newText: String) {
        text = newText
        isDirty = true
        externallyDeleted = false
        saveState = .dirty
        conflict = nil
        scheduleAutosave()
        scheduleFactsRefresh()
    }

    private func scheduleAutosave() {
        autosaveItem?.cancel()
        let delay = environment?.settings.autosaveDelay ?? 0.8
        let item = DispatchWorkItem { [weak self] in
            self?.saveNow(showErrors: true)
        }
        autosaveItem = item
        serialSaveQueue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func scheduleFactsRefresh() {
        factsItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let content = self.text
            let name = (self.path as NSString).lastPathComponent
            let facts = NoteAnalyzer.analyze(markdown: content, fileName: (name as NSString).deletingPathExtension)
            self.facts = facts
        }
        factsItem = item
        serialSaveQueue.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    // MARK: - Saving

    /// Saves immediately, cancelling pending autosave.
    func saveNow(showErrors: Bool) {
        guard isDirty, !isSaving else { return }
        guard let vault else { return }
        isSaving = true
        autosaveItem?.cancel()
        saveState = .saving
        let content = text
        let synced = lastSyncedDate
        do {
            try vault.writeNote(path, content: content, requireUnchangedSince: synced)
            isSaving = false
            isDirty = false
            let newDate = vault.currentModificationDate(of: path) ?? Date()
            lastSyncedDate = newDate
            saveState = .saved(newDate)
            externallyDeleted = false
        } catch VaultError.externalChangeDetected {
            isSaving = false
            handleSaveConflict()
        } catch {
            isSaving = false
            saveState = .error(error.localizedDescription)
            if showErrors {
                environment?.presentError(error)
            }
        }
    }

    private func handleSaveConflict() {
        guard let vault else { return }
        // Snapshot the external version before it can be overwritten.
        if let external = try? vault.readNote(path) {
            _ = environment?.snapshotStore.capture(vaultRoot: vault.rootURL, relativePath: path, content: external)
            conflict = ConflictInfo(id: path, path: path, localText: text, externalText: external)
        } else {
            conflict = ConflictInfo(id: path, path: path, localText: text, externalText: "")
        }
    }

    /// An external process modified the file on disk.
    func externalFileChanged(onDiskDate: Date) {
        guard let vault else { return }
        if isDirty {
            // Capture and surface the conflict; never silently overwrite.
            if let external = try? vault.readNote(path) {
                _ = environment?.snapshotStore.capture(vaultRoot: vault.rootURL, relativePath: path, content: external)
                conflict = ConflictInfo(id: path, path: path, localText: text, externalText: external)
            }
        } else if onDiskDate > lastSyncedDate.addingTimeInterval(0.001), conflict == nil {
            // Auto-reload clean buffers.
            if let fresh = try? vault.readNote(path) {
                text = fresh
                lastSyncedDate = onDiskDate
                facts = NoteAnalyzer.analyze(markdown: fresh, fileName: (path as NSString).lastPathComponent)
                saveState = .saved(onDiskDate)
            }
        }
    }

    func noteDeletedExternally() {
        if !isDirty {
            externallyDeleted = true
            saveState = .deletedExternally
        }
    }

    /// Reloads the buffer from disk (after conflict resolution or restore).
    func reloadFromDisk() {
        guard let vault, let fresh = try? vault.readNote(path) else { return }
        text = fresh
        lastSyncedDate = vault.currentModificationDate(of: path) ?? Date()
        facts = NoteAnalyzer.analyze(markdown: fresh, fileName: (path as NSString).lastPathComponent)
        isDirty = false
        externallyDeleted = false
        saveState = .saved(lastSyncedDate)
    }

    // MARK: - Conflict resolution

    enum ConflictChoice {
        case keepLocal
        case takeExternal
        case keepBoth
    }

    func resolveConflict(_ choice: ConflictChoice) {
        guard let vault, let conflict else { return }
        switch choice {
        case .keepLocal:
            // Snapshot is already stored; overwrite with local text.
            do {
                try vault.writeNote(path, content: text)
                isDirty = false
                lastSyncedDate = vault.currentModificationDate(of: path) ?? Date()
                saveState = .saved(lastSyncedDate)
                self.conflict = nil
            } catch {
                environment?.presentError(error)
            }
        case .takeExternal:
            text = conflict.externalText
            lastSyncedDate = vault.currentModificationDate(of: path) ?? Date()
            facts = NoteAnalyzer.analyze(markdown: text, fileName: (path as NSString).lastPathComponent)
            isDirty = false
            saveState = .saved(lastSyncedDate)
            self.conflict = nil
        case .keepBoth:
            let stamp = Self.conflictStamp()
            let base = (path as NSString).deletingPathExtension
            let ext = (path as NSString).pathExtension
            let copyName = "\(base) (conflict \(stamp)).\(ext)"
            let folder = (path as NSString).deletingLastPathComponent
            if let entry = try? vault.createNote(folder: folder, title: copyName, content: conflict.externalText, allowAutoRename: true) {
                _ = entry
            }
            // Keep the local text in the main buffer.
            do {
                try vault.writeNote(path, content: text)
                isDirty = false
                lastSyncedDate = vault.currentModificationDate(of: path) ?? Date()
                saveState = .saved(lastSyncedDate)
                self.conflict = nil
            } catch {
                environment?.presentError(error)
            }
        }
    }

    static func conflictStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    // MARK: - Task toggling

    /// Flips the checkbox state of the task at `lineIndex` (0-based) and saves.
    func toggleTask(atLine lineIndex: Int) {
        var lines = text.components(separatedBy: "\n")
        guard lineIndex < lines.count else { return }
        let line = lines[lineIndex]
        if let range = line.range(of: "[ ]") {
            lines[lineIndex] = line.replacingCharacters(in: range, with: "[x]")
        } else if let range = line.range(of: "[x]", options: .caseInsensitive) {
            lines[lineIndex] = line.replacingCharacters(in: range, with: "[ ]")
        } else {
            return
        }
        textDidChange(lines.joined(separator: "\n"))
        saveNow(showErrors: true)
    }

    // MARK: - Editor integration points

    /// The current writing width from settings, for the editor surface.
    var writingWidth: CGFloat { CGFloat(environment?.settings.writingWidth ?? 680) }
}
