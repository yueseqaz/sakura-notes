import Foundation
import SakuraCore
import Combine

/// Events emitted when the vault contents change (including external changes).
public protocol VaultDelegate: AnyObject {
    func vault(_ vault: VaultStore, notesAdded: [NoteEntry])
    func vault(_ vault: VaultStore, notesModified: [NoteEntry])
    func vault(_ vault: VaultStore, notesRemoved: [String])
    func vault(_ vault: VaultStore, movedFrom: String, to: String)
    func vaultDidReload(_ vault: VaultStore)
}

public extension VaultDelegate {
    func vault(_ vault: VaultStore, notesAdded: [NoteEntry]) {}
    func vault(_ vault: VaultStore, notesModified: [NoteEntry]) {}
    func vault(_ vault: VaultStore, notesRemoved: [String]) {}
    func vault(_ vault: VaultStore, movedFrom: String, to: String) {}
    func vaultDidReload(_ vault: VaultStore) {}
}

/// Per-vault configuration persisted inside the vault under `.sakuranotes/`.
/// Kept minimal and human-inspectable; never required to read notes.
public struct VaultMetadata: Codable, Equatable {
    public var id: UUID
    public var dailyNotesFolder: String?
    public var templatesFolder: String?

    public init(id: UUID = UUID(), dailyNotesFolder: String? = nil, templatesFolder: String? = nil) {
        self.id = id
        self.dailyNotesFolder = dailyNotesFolder
        self.templatesFolder = templatesFolder
    }
}

/// The source of truth for a workspace: an ordinary directory of Markdown
/// files. Owns the tree model, all file mutations (atomic), external-change
/// detection via FSEvents, and per-vault metadata.
///
/// All public API is main-thread confined; scanning and monitoring happen on
/// background queues and results are published on the main thread.
public final class VaultStore: ObservableObject {

    public static let metadataDirectoryName = ".sakuranotes"

    public let rootURL: URL
    @Published public private(set) var rootFolder: FolderNode
    @Published public private(set) var notes: [NoteEntry] = []
    @Published public private(set) var isScanning: Bool = false
    @Published public var showsHiddenFiles: Bool = false {
        didSet { if oldValue != showsHiddenFiles { rescan() } }
    }
    public private(set) var metadata: VaultMetadata
    public weak var delegate: VaultDelegate?

    private let workQueue = DispatchQueue(label: "com.sakuranotes.vault.scan", qos: .userInitiated)
    private let monitorQueue = DispatchQueue(label: "com.sakuranotes.vault.fsevents", qos: .utility)
    private var monitor: FSEventsMonitor?
    private var trackedMTimes: [String: Date] = [:]
    private var pendingEventPaths = Set<String>()
    private var flushWorkItem: DispatchWorkItem?
    private let fileManager = FileManager.default
    private let caseSensitiveFS: Bool

    public var metadataDirectory: URL { rootURL.appendingPathComponent(Self.metadataDirectoryName, isDirectory: true) }

    // MARK: - Init

    /// - Parameter scanSynchronously: used by tests; production starts async.
    public init(rootURL: URL, monitor: Bool = true, scanSynchronously: Bool = false) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw VaultError.notADirectory
        }
        self.rootURL = rootURL
        self.rootFolder = FolderNode(name: rootURL.lastPathComponent, relativePath: "")
        self.metadata = Self.loadMetadata(at: rootURL) ?? VaultMetadata()
        self.caseSensitiveFS = (rootURL.withUnsafeFileSystemRepresentation { ptr in
            ptr.map { pathconf($0, _PC_CASE_SENSITIVE) } ?? 1
        }) != 0
        if scanSynchronously {
            performScanAndPublish()
        } else {
            isScanning = true
            workQueue.async { [weak self] in self?.performScanAndPublish() }
        }
        if monitor {
            let fsMonitor = FSEventsMonitor(root: rootURL, queue: monitorQueue) { [weak self] paths in
                self?.handleEvents(paths)
            }
            self.monitor = fsMonitor
            fsMonitor.start()
        }
        saveMetadata()
    }

    deinit {
        monitor?.stop()
    }

    // MARK: - Path handling

    /// True when a relative path is safe to pass to `absoluteURL(for:)`:
    /// non-empty, no leading slash, and no `.`/`..` components.
    public static func isSafeRelativePath(_ relativePath: String) -> Bool {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { return false }
        let components = relativePath.split(separator: "/").map(String.init)
        return !components.isEmpty && !components.contains("..") && !components.contains(".")
    }

    /// Converts a relative POSIX path into an absolute URL, refusing traversal.
    public func absoluteURL(for relativePath: String) -> URL {
        let components = relativePath.split(separator: "/").map(String.init)
        precondition(!components.isEmpty, "absoluteURL requires a non-empty relative path")
        precondition(!components.contains("..") && !components.contains(".") && !relativePath.hasPrefix("/"),
                     "Path traversal is not allowed: \(relativePath)")
        var url = rootURL
        for component in components {
            url.appendPathComponent(component)
        }
        return url
    }

    /// Returns the vault-relative path of an absolute URL inside the vault.
    public func relativePath(for url: URL) -> String? {
        let standardized = url.standardizedFileURL.path
        let rootPath = rootURL.standardizedFileURL.path
        guard standardized.hasPrefix(rootPath), standardized != rootPath else { return nil }
        let rest = standardized.dropFirst(rootPath.count)
        return String(rest.drop(while: { $0 == "/" }))
    }

    /// True when the filesystem treats names that differ only in case as equal.
    public var isCaseSensitive: Bool { caseSensitiveFS }

    private func namesCollide(_ a: String, _ b: String) -> Bool {
        if caseSensitiveFS { return a == b }
        return a.lowercased() == b.lowercased()
    }

    // MARK: - Scanning

    public func rescan() {
        workQueue.async { [weak self] in self?.performScanAndPublish() }
    }

    private func performScanAndPublish() {
        let (tree, notes) = Self.scanTree(rootURL: rootURL, showsHiddenFiles: showsHiddenFiles)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.publish(scanResult: (tree, notes))
        }
    }

    private func publish(scanResult: (FolderNode, [NoteEntry])) {
        let (tree, newNotes) = scanResult
        let oldNotes = notes
        self.rootFolder = tree
        self.notes = newNotes
        self.isScanning = false

        var oldByPath: [String: NoteEntry] = [:]
        for note in oldNotes { oldByPath[note.relativePath] = note }
        var newByPath: [String: NoteEntry] = [:]
        for note in newNotes { newByPath[note.relativePath] = note }

        var added: [NoteEntry] = []
        var modified: [NoteEntry] = []
        for note in newNotes {
            if let old = oldByPath[note.relativePath] {
                if old.modificationDate != note.modificationDate {
                    modified.append(note)
                }
            } else {
                // Our own writes update trackedMTimes before events arrive, so
                // anything new here came from outside the app.
                added.append(note)
            }
        }
        let removed = oldNotes.map(\.relativePath).filter { newByPath[$0] == nil }

        for note in newNotes { trackedMTimes[note.relativePath] = note.modificationDate }
        for path in removed { trackedMTimes.removeValue(forKey: path) }

        if !added.isEmpty { delegate?.vault(self, notesAdded: added) }
        if !modified.isEmpty { delegate?.vault(self, notesModified: modified) }
        if !removed.isEmpty { delegate?.vault(self, notesRemoved: removed) }
        delegate?.vaultDidReload(self)
    }

    private static func scanTree(rootURL: URL, showsHiddenFiles: Bool) -> (FolderNode, [NoteEntry]) {
        let rootName = rootURL.lastPathComponent
        let root = FolderNode(name: rootName, relativePath: "")
        var allNotes: [NoteEntry] = []
        let fileManager = FileManager.default

        func statEntry(_ url: URL) -> (Date, Int)? {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            guard let date = values?.contentModificationDate ?? values?.creationDate else {
                let attrs = try? fileManager.attributesOfItem(atPath: url.path)
                guard let modified = attrs?[.modificationDate] as? Date else { return nil }
                let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
                return (modified, size)
            }
            return (date, values?.fileSize ?? 0)
        }

        func walk(directory: URL, into node: FolderNode) {
            let contents: [URL]
            do {
                contents = try fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey, .isSymbolicLinkKey],
                    options: []
                )
            } catch {
                return
            }
            var children: [VaultNode] = []
            for item in contents {
                let name = item.lastPathComponent
                if name == VaultStore.metadataDirectoryName { continue }
                if !showsHiddenFiles && name.hasPrefix(".") { continue }
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isSymbolicLink == true { continue }
                if values?.isDirectory == true {
                    let child = FolderNode(name: name, relativePath: relativeChildPath(directory, item, rootURL))
                    walk(directory: item, into: child)
                    children.append(.folder(child))
                } else {
                    guard let (mtime, size) = statEntry(item) else { continue }
                    let entry = NoteEntry(
                        relativePath: relativeChildPath(directory, item, rootURL),
                        name: name,
                        modificationDate: mtime,
                        size: size
                    )
                    allNotes.append(entry)
                    children.append(.note(entry))
                }
            }
            children.sort { lhs, rhs in
                if case .folder(let lf) = lhs, case .folder(let rf) = rhs { return lf.name.localizedStandardCompare(rf.name) == .orderedAscending }
                if case .folder = lhs { return true }
                if case .folder = rhs { return false }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            node.setChildren(children)
        }

        func relativeChildPath(_ parent: URL, _ child: URL, _ root: URL) -> String {
            let parentPath = parent.standardizedFileURL.path
            let rootPath = root.standardizedFileURL.path
            let parentRelative: String
            if parentPath == rootPath { parentRelative = "" } else {
                parentRelative = parentPath.dropFirst(rootPath.count + 1).description
            }
            return parentRelative.isEmpty ? child.lastPathComponent : "\(parentRelative)/\(child.lastPathComponent)"
        }

        walk(directory: rootURL, into: root)
        allNotes.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        return (root, allNotes)
    }

    // MARK: - Reading & writing

    public func readNote(_ relativePath: String) throws -> String {
        let url = absoluteURL(for: relativePath)
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch CocoaError.fileReadNoSuchFile {
            throw VaultError.noteNotFound(relativePath)
        } catch {
            throw VaultError.readFailed(path: relativePath, underlying: error.localizedDescription)
        }
    }

    public func readData(_ relativePath: String) throws -> Data {
        let url = absoluteURL(for: relativePath)
        do {
            return try Data(contentsOf: url)
        } catch {
            throw VaultError.readFailed(path: relativePath, underlying: error.localizedDescription)
        }
    }

    /// Writes arbitrary data (e.g. an image attachment) into the vault and
    /// refreshes the model so the new file shows up immediately.
    public func writeData(_ data: Data, toRelativePath relativePath: String) throws {
        try AtomicFile.write(data, to: absoluteURL(for: relativePath))
        if let date = currentModificationDate(of: relativePath) {
            trackedMTimes[relativePath] = date
        }
        if noteEntry(at: relativePath) == nil {
            // New file: refresh the tree so it appears right away.
            rescan()
        } else {
            updateEntryAfterWrite(relativePath)
        }
    }

    /// Returns the on-disk modification date for a note right now, or nil if missing.
    public func currentModificationDate(of relativePath: String) -> Date? {
        let url = absoluteURL(for: relativePath)
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    /// Saves a note. When `requireUnchangedSince` is provided and the file on
    /// disk changed after that moment, throws `externalChangeDetected` instead
    /// of overwriting — the caller is responsible for resolving the conflict.
    /// A pre-overwrite snapshot is captured whenever an externally-modified
    /// file is about to be replaced by explicit `captureSnapshot` users; see
    /// `SnapshotStore`.
    public func writeNote(_ relativePath: String, content: String, requireUnchangedSince: Date? = nil) throws {
        let url = absoluteURL(for: relativePath)
        if let requireUnchangedSince, let diskDate = currentModificationDate(of: relativePath) {
            // Allow tiny clock/rounding jitter by comparing with 0 tolerance on
            // exact equality; macOS mtimes have nanosecond resolution.
            if diskDate > requireUnchangedSince.addingTimeInterval(0.001) {
                throw VaultError.externalChangeDetected(path: relativePath)
            }
        }
        do {
            try AtomicFile.write(text: content, to: url)
        } catch {
            throw error
        }
        if let date = currentModificationDate(of: relativePath) {
            trackedMTimes[relativePath] = date
        }
        objectWillChange.send()
        // Refresh the model entry so lists show the new modification date.
        updateEntryAfterWrite(relativePath)
    }

    private func updateEntryAfterWrite(_ relativePath: String) {
        guard let date = trackedMTimes[relativePath], let size = fileSize(of: relativePath) else { return }
        let updated = NoteEntry(relativePath: relativePath, name: (relativePath as NSString).lastPathComponent, modificationDate: date, size: size)
        if let index = notes.firstIndex(where: { $0.relativePath == relativePath }) {
            notes[index] = updated
        }
        updateInTree(relativePath) { $0 == relativePath ? .note(updated) : nil }
    }

    private func fileSize(of relativePath: String) -> Int? {
        let values = try? absoluteURL(for: relativePath).resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize
    }

    private func updateInTree(_ relativePath: String, replacement: (String) -> VaultNode?) {
        func walk(_ node: FolderNode, prefix: String) {
            var children: [VaultNode] = []
            for child in node.children {
                if child.relativePath == relativePath {
                    if let replaced = replacement(relativePath) { children.append(replaced); continue }
                    // Note moved out of this folder: drop it.
                    continue
                }
                if case .folder(let sub) = child {
                    walk(sub, prefix: prefix)
                    children.append(.folder(sub))
                } else {
                    children.append(child)
                }
            }
            node.setChildren(children)
        }
        walk(rootFolder, prefix: "")
    }

    // MARK: - Creating

    /// Creates a note, choosing a non-colliding name when needed.
    @discardableResult
    public func createNote(folder: String, title: String, content: String, allowAutoRename: Bool = true) throws -> NoteEntry {
        let cleanFolder = folder == "/" ? "" : folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !cleanFolder.isEmpty {
            let folderURL = absoluteURL(for: cleanFolder)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue else {
                throw VaultError.invalidPath(cleanFolder)
            }
        }
        let baseName = StringUtilities.sanitizedFileName((title as NSString).deletingPathExtension)
        var ext = (title as NSString).pathExtension
        if ext.isEmpty { ext = "md" }
        let existing = siblingNames(in: cleanFolder)
        var name = "\(baseName).\(ext)"
        if existing.contains(where: { namesCollide($0, name) }) {
            guard allowAutoRename else { throw VaultError.duplicateName(name) }
            var counter = 2
            while true {
                name = "\(baseName) \(counter).\(ext)"
                if !existing.contains(where: { namesCollide($0, name) }) { break }
                counter += 1
            }
        }
        let relativePath = cleanFolder.isEmpty ? name : "\(cleanFolder)/\(name)"
        let url = absoluteURL(for: relativePath)
        try AtomicFile.write(text: content, to: url)
        let date = currentModificationDate(of: relativePath) ?? Date()
        let entry = NoteEntry(relativePath: relativePath, name: name, modificationDate: date, size: content.utf8.count)
        trackedMTimes[relativePath] = date
        insertEntry(entry, intoFolder: cleanFolder)
        objectWillChange.send()
        return entry
    }

    @discardableResult
    public func createFolder(_ relativePath: String) throws -> FolderNode {
        let clean = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !clean.isEmpty else { throw VaultError.invalidPath(relativePath) }
        let components = clean.split(separator: "/").map(String.init)
        var path = ""
        for component in components {
            path = path.isEmpty ? component : "\(path)/\(component)"
            let url = absoluteURL(for: path)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
                guard isDir.boolValue else { throw VaultError.duplicateName(component) }
            } else {
                do {
                    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
                } catch {
                    throw VaultError.writeFailed(path: path, underlying: error.localizedDescription)
                }
            }
        }
        let node = FolderNode(name: components.last!, relativePath: clean)
        insertFolder(node, intoFolder: components.dropLast().joined(separator: "/"))
        objectWillChange.send()
        return node
    }

    /// Ensures a folder path exists (creating missing parts), without model-side
    /// renaming. Used for attachments and daily-note directories.
    public func ensureFolder(_ relativePath: String) throws {
        _ = try createFolder(relativePath)
    }

    // MARK: - Renaming / moving

    /// Renames a note or folder within its parent directory.
    /// - Returns: the new relative path.
    @discardableResult
    public func rename(_ relativePath: String, to newName: String) throws -> String {
        let cleanName = StringUtilities.sanitizedFileName(newName)
        let parent = (relativePath as NSString).deletingLastPathComponent
        let ext = (relativePath as NSString).pathExtension
        var targetName = cleanName
        if !ext.isEmpty && !(relativePathIsFolder(relativePath)) {
            let targetExt = ((cleanName as NSString).pathExtension)
            if targetExt.isEmpty { targetName = "\(cleanName).\(ext)" }
        }
        let siblingNames = self.siblingNames(in: parent).filter { $0 != (relativePath as NSString).lastPathComponent }
        if siblingNames.contains(where: { namesCollide($0, targetName) }) {
            throw VaultError.duplicateName(targetName)
        }
        let newRelativePath = parent.isEmpty ? targetName : "\(parent)/\(targetName)"
        try fileManager.moveItem(at: absoluteURL(for: relativePath), to: absoluteURL(for: newRelativePath))

        // Update model in place (fast path) instead of a full rescan.
        let oldPrefix = relativePath + "/"
        var movedPaths: [(String, String)] = []
        if relativePathIsFolder(relativePath) {
            for note in notes where note.relativePath == relativePath || note.relativePath.hasPrefix(oldPrefix) {
                let newPath = newRelativePath + note.relativePath.dropFirst(relativePath.count)
                movedPaths.append((note.relativePath, newPath))
            }
        } else {
            movedPaths.append((relativePath, newRelativePath))
        }
        applyMoves(movedPaths, subtreePath: relativePath, newSubtreePath: newRelativePath)
        delegate?.vault(self, movedFrom: relativePath, to: newRelativePath)
        objectWillChange.send()
        return newRelativePath
    }

    /// Moves a note (or folder) into a (possibly different) folder.
    @discardableResult
    public func move(_ relativePath: String, toFolder destinationFolder: String) throws -> String {
        let cleanFolder = destinationFolder == "/" ? "" : destinationFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relativePath.hasPrefix(cleanFolder + "/") && relativePath != cleanFolder else {
            throw VaultError.invalidPath("Cannot move a folder into itself.")
        }
        let name = (relativePath as NSString).lastPathComponent
        let existing = siblingNames(in: cleanFolder)
        if existing.contains(where: { namesCollide($0, name) }) {
            throw VaultError.duplicateName(name)
        }
        let newRelativePath = cleanFolder.isEmpty ? name : "\(cleanFolder)/\(name)"
        try fileManager.moveItem(at: absoluteURL(for: relativePath), to: absoluteURL(for: newRelativePath))

        var movedPaths: [(String, String)] = []
        if relativePathIsFolder(relativePath) {
            let oldPrefix = relativePath + "/"
            for note in notes where note.relativePath.hasPrefix(oldPrefix) {
                movedPaths.append((note.relativePath, newRelativePath + note.relativePath.dropFirst(relativePath.count)))
            }
        } else {
            movedPaths.append((relativePath, newRelativePath))
        }
        applyMoves(movedPaths, subtreePath: relativePath, newSubtreePath: newRelativePath)
        delegate?.vault(self, movedFrom: relativePath, to: newRelativePath)
        objectWillChange.send()
        return newRelativePath
    }

    /// True when the given vault-relative path is a directory on disk.
    public func isFolder(_ relativePath: String) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: absoluteURL(for: relativePath).path, isDirectory: &isDir) && isDir.boolValue
    }

    private func relativePathIsFolder(_ relativePath: String) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: absoluteURL(for: relativePath).path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Updates tracked mtimes, flat notes array, and the folder tree after a
    /// set of moves performed on disk.
    private func applyMoves(_ moves: [(String, String)], subtreePath: String, newSubtreePath: String) {
        for (from, to) in moves {
            if let date = trackedMTimes[from] { trackedMTimes.removeValue(forKey: from); trackedMTimes[to] = date }
        }
        // Rebuild flat notes list.
        var movedNoteEntries: [NoteEntry] = []
        var kept: [NoteEntry] = []
        let fromSet = Set(moves.map(\.0))
        for note in notes {
            if fromSet.contains(note.relativePath), let to = moves.first(where: { $0.0 == note.relativePath })?.1 {
                let moved = NoteEntry(relativePath: to, name: (to as NSString).lastPathComponent, modificationDate: note.modificationDate, size: note.size)
                movedNoteEntries.append(moved)
            } else {
                kept.append(note)
            }
        }
        kept.append(contentsOf: movedNoteEntries)
        kept.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        notes = kept

        // Rebuild the tree by removing the subtree and re-adding it at the new location.
        rebuildTreeAfterMove(from: subtreePath, to: newSubtreePath)
    }

    private func rebuildTreeAfterMove(from: String, to: String) {
        // Copy the subtree with updated paths, remove the old copy, re-insert.
        guard let subtree = extractSubtree(from) else { return }
        let copied = extractSubtreeCopy(subtree, newPath: to)
        removeNode(from)
        insertNode(copied, atRelativePath: to)
    }

    private func extractSubtree(_ relativePath: String) -> VaultNode? {
        func walk(_ node: FolderNode) -> VaultNode? {
            for child in node.children {
                if child.relativePath == relativePath { return child }
                if case .folder(let sub) = child, let found = walk(sub) { return found }
            }
            return nil
        }
        return walk(rootFolder)
    }

    private func extractSubtreeCopy(_ node: VaultNode, newPath: String) -> VaultNode {
        switch node {
        case .note(let note):
            return .note(NoteEntry(relativePath: newPath, name: (newPath as NSString).lastPathComponent, modificationDate: note.modificationDate, size: note.size))
        case .folder(let folder):
            let copy = FolderNode(name: (newPath as NSString).lastPathComponent, relativePath: newPath, children: [])
            for child in folder.children {
                copy.children.append(extractSubtreeCopy(child, newPath: newPath + "/" + child.name))
            }
            return .folder(copy)
        }
    }

    private func insertNode(_ node: VaultNode, atRelativePath path: String) {
        let parentPath = (path as NSString).deletingLastPathComponent
        let folder = folderNode(at: parentPath) ?? rootFolder
        var children = folder.children.filter { $0.relativePath != path }
        children.append(node)
        children.sort { lhs, rhs in
            if case .folder(let lf) = lhs, case .folder(let rf) = rhs { return lf.name.localizedStandardCompare(rf.name) == .orderedAscending }
            if case .folder = lhs { return true }
            if case .folder = rhs { return false }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        folder.setChildren(children)
    }

    /// Locates a live FolderNode by relative path ("" returns the root).
    public func folderNode(at relativePath: String) -> FolderNode? {
        if relativePath.isEmpty { return rootFolder }
        func walk(_ node: FolderNode) -> FolderNode? {
            for child in node.children {
                if case .folder(let sub) = child {
                    if sub.relativePath == relativePath { return sub }
                    if let found = walk(sub) { return found }
                }
            }
            return nil
        }
        return walk(rootFolder)
    }

    // MARK: - Duplicating / deleting

    @discardableResult
    public func duplicate(_ relativePath: String) throws -> NoteEntry {
        let name = (relativePath as NSString).lastPathComponent
        let ext = (relativePath as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        let folder = (relativePath as NSString).deletingLastPathComponent
        let content = try readNote(relativePath)
        var copyName = "\(base) copy.\(ext)"
        var counter = 2
        let existing = siblingNames(in: folder)
        while existing.contains(where: { namesCollide($0, copyName) }) {
            copyName = "\(base) copy \(counter).\(ext)"
            counter += 1
        }
        let newRelativePath = folder.isEmpty ? copyName : "\(folder)/\(copyName)"
        try AtomicFile.write(text: content, to: absoluteURL(for: newRelativePath))
        let date = currentModificationDate(of: newRelativePath) ?? Date()
        let entry = NoteEntry(relativePath: newRelativePath, name: copyName, modificationDate: date, size: content.utf8.count)
        trackedMTimes[newRelativePath] = date
        insertEntry(entry, intoFolder: folder)
        objectWillChange.send()
        return entry
    }

    /// Moves an item to the macOS Trash. This is the only delete path; notes
    /// are never permanently destroyed by the app.
    public func trash(_ relativePath: String) throws {
        let url = absoluteURL(for: relativePath)
        do {
            try fileManager.trashItem(at: url, resultingItemURL: nil)
        } catch {
            throw VaultError.trashFailed(path: relativePath, underlying: error.localizedDescription)
        }
        removeFromModel(relativePath)
        objectWillChange.send()
    }

    private func removeFromModel(_ relativePath: String) {
        trackedMTimes.removeValue(forKey: relativePath)
        notes.removeAll { $0.relativePath == relativePath }
        removeNode(relativePath)
    }

    private func removeNode(_ relativePath: String) {
        func walk(_ node: FolderNode) {
            var children = node.children.filter { $0.relativePath != relativePath }
            for child in node.children {
                if case .folder(let sub) = child {
                    walk(sub)
                }
            }
            // Remove folders whose subtree contained the path.
            children = children.filter { child in
                if case .folder(let f) = child {
                    return f.relativePath != relativePath
                }
                return true
            }
            node.setChildren(children)
        }
        walk(rootFolder)
    }

    // MARK: - Helpers

    private func siblingNames(in folder: String) -> [String] {
        folderNode(at: folder)?.children.map(\.name) ?? []
    }

    private func insertEntry(_ entry: NoteEntry, intoFolder folder: String) {
        notes.append(entry)
        notes.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        let node = folderNode(at: folder) ?? rootFolder
        var children = node.children
        children.append(.note(entry))
        children.sort { lhs, rhs in
            if case .folder(let lf) = lhs, case .folder(let rf) = rhs { return lf.name.localizedStandardCompare(rf.name) == .orderedAscending }
            if case .folder = lhs { return true }
            if case .folder = rhs { return false }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        node.setChildren(children)
    }

    private func insertFolder(_ node: FolderNode, intoFolder parent: String) {
        let container = folderNode(at: parent) ?? rootFolder
        var children = container.children
        children.append(.folder(node))
        children.sort { lhs, rhs in
            if case .folder(let lf) = lhs, case .folder(let rf) = rhs { return lf.name.localizedStandardCompare(rf.name) == .orderedAscending }
            if case .folder = lhs { return true }
            if case .folder = rhs { return false }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        container.setChildren(children)
    }

    public func noteEntry(at relativePath: String) -> NoteEntry? {
        notes.first { $0.relativePath == relativePath }
    }

    public func isMarkdown(_ relativePath: String) -> Bool {
        TextFileKind.classify(fileExtension: (relativePath as NSString).pathExtension) == .markdown
            || TextFileKind.classify(fileExtension: (relativePath as NSString).pathExtension) == .plainText
    }

    // MARK: - Metadata persistence

    private static func loadMetadata(at root: URL) -> VaultMetadata? {
        let url = root.appendingPathComponent(VaultStore.metadataDirectoryName, isDirectory: true)
            .appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(VaultMetadata.self, from: data)
    }

    private func saveMetadata() {
        let dir = metadataDirectory
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("meta.json")
        if let data = try? JSONEncoder().encode(metadata) {
            try? AtomicFile.write(data, to: url, createDirectories: false)
        }
    }

    public func updateMetadata(_ mutate: (inout VaultMetadata) -> Void) {
        mutate(&metadata)
        saveMetadata()
    }

    // MARK: - External change handling

    private func handleEvents(_ paths: [String]) {
        for path in paths {
            let relative = relativePath(for: URL(fileURLWithPath: path))
            if let relative { pendingEventPaths.insert(relative) }
        }
        guard !pendingEventPaths.isEmpty else { return }
        flushWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.flushEvents() }
        flushWorkItem = item
        workQueue.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    private func flushEvents() {
        pendingEventPaths.removeAll()
        // A full scan + diff is cheap relative to user-perceived latency and
        // keeps correctness trivial for moves, deletes, and permission errors.
        performScanAndPublish()
    }
}
