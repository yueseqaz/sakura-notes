import Foundation
import Combine
import SakuraCore
import SakuraStorage

/// Keeps the FTS index in sync with the vault and executes searches.
///
/// Indexing runs on a background queue, is cancellable, and is fully
/// incremental: only changed/added/removed notes are reprocessed.
public final class SearchCoordinator: NSObject, ObservableObject, VaultDelegate {

    private let index: FTSIndex
    private weak var vault: VaultStore?
    private let indexQueue = DispatchQueue(label: "com.sakuranotes.index", qos: .utility)
    private let searchQueue = DispatchQueue(label: "com.sakuranotes.search", qos: .userInitiated)

    @Published public private(set) var noteCount: Int = 0
    /// nil when idle; 0...1 during a full (re)build.
    @Published public private(set) var buildProgress: Double? = nil
    @Published public private(set) var lastError: String? = nil
    @Published public private(set) var searchResults: [SearchResult] = []
    @Published public private(set) var isSearching: Bool = false

    private var pendingPaths = Set<String>()
    private var pendingRemovals = Set<String>()
    private var flushItem: DispatchWorkItem?
    private var searchItem: DispatchWorkItem?
    private var buildGeneration = 0

    public init(index: FTSIndex) {
        self.index = index
        super.init()
        noteCount = index.noteCount()
    }

    public var isAvailable: Bool { index.isAvailable }

    // MARK: - Attaching to a vault

    /// Performs a full (re)build of the index for the given vault.
    public func attach(vault: VaultStore) {
        self.vault = vault
        rebuildAll(vault: vault)
    }

    public func detach() {
        vault = nil
    }

    public func rebuildAll(vault: VaultStore) {
        buildGeneration += 1
        let generation = buildGeneration
        let index = self.index
        let snapshot = vault.notes
        DispatchQueue.main.async { self.buildProgress = 0 }
        indexQueue.async { [weak self] in
            guard let self else { return }
            index.removeAll()
            let total = snapshot.count
            for (offset, entry) in snapshot.enumerated() {
                guard generation == self.buildGeneration else { return }
                guard let content = try? vault.readNote(entry.relativePath) else { continue }
                self.indexNoteContent(path: entry.relativePath, content: content, mtime: entry.modificationDate, index: index)
                if offset % 50 == 0 {
                    let progress = total > 0 ? Double(offset) / Double(total) : 1
                    DispatchQueue.main.async { [weak self] in
                        self?.buildProgress = progress
                    }
                }
            }
            let count = index.noteCount()
            DispatchQueue.main.async { [weak self] in
                self?.buildProgress = nil
                self?.noteCount = count
            }
        }
    }

    // MARK: - Search execution

    /// Debounced, cancellable search. Results appear on `searchResults`.
    public func search(_ rawQuery: String) {
        searchItem?.cancel()
        guard !rawQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            DispatchQueue.main.async { [weak self] in
                self?.searchResults = []
                self?.isSearching = false
            }
            return
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let query = SearchQuery.parse(rawQuery)
            let results = self.index.search(query)
            DispatchQueue.main.async {
                self.searchResults = results
                self.isSearching = false
            }
        }
        searchItem = item
        isSearching = true
        searchQueue.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    // MARK: - VaultDelegate

    public func vault(_ vault: VaultStore, notesAdded: [NoteEntry]) {
        enqueueIndex(notesAdded.map(\.relativePath), vault: vault)
    }

    public func vault(_ vault: VaultStore, notesModified: [NoteEntry]) {
        enqueueIndex(notesModified.map(\.relativePath), vault: vault)
    }

    public func vault(_ vault: VaultStore, notesRemoved: [String]) {
        for path in notesRemoved {
            pendingPaths.remove(path)
            pendingRemovals.insert(path)
        }
        scheduleFlush(vault: vault)
    }

    public func vault(_ vault: VaultStore, movedFrom: String, to: String) {
        indexQueue.async { [weak self] in
            guard let self else { return }
            self.index.removeNote(movedFrom)
            guard let content = try? vault.readNote(to) else { return }
            let mtime = vault.currentModificationDate(of: to) ?? Date()
            self.indexNoteContent(path: to, content: content, mtime: mtime, index: self.index)
            DispatchQueue.main.async { self.noteCount = self.index.noteCount() }
        }
    }

    public func vaultDidReload(_ vault: VaultStore) {}

    // MARK: - Internals

    private func enqueueIndex(_ paths: [String], vault: VaultStore) {
        for path in paths {
            pendingRemovals.remove(path)
            pendingPaths.insert(path)
        }
        scheduleFlush(vault: vault)
    }

    private func scheduleFlush(vault: VaultStore) {
        flushItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let toRemove = self.pendingRemovals
            let toIndex = self.pendingPaths
            self.pendingRemovals.removeAll()
            self.pendingPaths.removeAll()
            for path in toRemove {
                self.index.removeNote(path)
            }
            for path in toIndex {
                guard let content = try? vault.readNote(path) else { continue }
                let mtime = vault.currentModificationDate(of: path) ?? Date()
                self.indexNoteContent(path: path, content: content, mtime: mtime, index: self.index)
            }
            DispatchQueue.main.async { self.noteCount = self.index.noteCount() }
        }
        flushItem = item
        indexQueue.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    private func indexNoteContent(path: String, content: String, mtime: Date, index: FTSIndex) {
        let fileName = (path as NSString).lastPathComponent
        let facts = NoteAnalyzer.analyze(markdown: content, fileName: (fileName as NSString).deletingPathExtension)
        index.indexNote(FTSIndex.IndexedNote(
            path: path,
            title: facts.title ?? fileName,
            body: content,
            tags: facts.allTags,
            modificationDate: mtime
        ))
    }

    // MARK: - Diagnostics

    public func status() -> IndexStatus {
        IndexStatus(noteCount: noteCount, isReady: index.isAvailable && buildProgress == nil, lastError: lastError)
    }
}
