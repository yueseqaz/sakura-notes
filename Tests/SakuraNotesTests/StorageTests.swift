import Testing
import Foundation
@testable import SakuraCore
@testable import SakuraStorage

/// Creates an isolated temporary vault for each test.
@MainActor
func makeTemporaryVault() throws -> (VaultStore, URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("sakura-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let vault = try VaultStore(rootURL: root, monitor: false, scanSynchronously: true)
    return (vault, root)
}

@MainActor
@Suite("Vault Store")
struct VaultStoreTests {

    @Test func createsNotesWithAutoRename() throws {
        let (vault, _) = try makeTemporaryVault()
        let first = try vault.createNote(folder: "", title: "Ideas", content: "# Ideas")
        let second = try vault.createNote(folder: "", title: "Ideas", content: "# Ideas 2")
        #expect(first.name == "Ideas.md")
        #expect(second.name == "Ideas 2.md")
        #expect(vault.notes.count == 2)
        #expect(try vault.readNote(first.relativePath) == "# Ideas")
    }

    @Test func sanitizesHostileTitles() throws {
        let (vault, _) = try makeTemporaryVault()
        let entry = try vault.createNote(folder: "", title: "a/b:c", content: "x")
        #expect(entry.name == "a-b-c.md")
    }

    @Test func createsNestedFolders() throws {
        let (vault, _) = try makeTemporaryVault()
        _ = try vault.createFolder("Journal/2026/October")
        let entry = try vault.createNote(folder: "Journal/2026/October", title: "Day", content: "hi")
        #expect(entry.relativePath == "Journal/2026/October/Day.md")
        #expect(vault.notes.map(\.relativePath) == ["Journal/2026/October/Day.md"])
    }

    @Test func duplicateNameThrowsWhenAutoRenameDisabled() throws {
        let (vault, _) = try makeTemporaryVault()
        _ = try vault.createNote(folder: "", title: "Same", content: "")
        #expect(throws: VaultError.self) {
            try vault.createNote(folder: "", title: "Same", content: "", allowAutoRename: false)
        }
    }

    @Test func renameUpdatesModelAndDelegate() throws {
        let (vault, _) = try makeTemporaryVault()
        let entry = try vault.createNote(folder: "", title: "Before", content: "content")
        final class Recorder: VaultDelegate {
            var moves: [(String, String)] = []
            func vault(_ vault: VaultStore, movedFrom: String, to: String) { moves.append((movedFrom, to)) }
        }
        let recorder = Recorder()
        vault.delegate = recorder
        let newPath = try vault.rename(entry.relativePath, to: "After")
        #expect(newPath == "After.md")
        #expect(vault.noteEntry(at: "After.md") != nil)
        #expect(vault.noteEntry(at: "Before.md") == nil)
        #expect(recorder.moves.count == 1)
        #expect(try vault.readNote("After.md") == "content")
    }

    @Test func moveBetweenFoldersPreservesContent() throws {
        let (vault, _) = try makeTemporaryVault()
        _ = try vault.createFolder("Archive")
        let entry = try vault.createNote(folder: "", title: "Doc", content: "payload")
        let newPath = try vault.move(entry.relativePath, toFolder: "Archive")
        #expect(newPath == "Archive/Doc.md")
        #expect(try vault.readNote(newPath) == "payload")
        #expect(vault.notes.count == 1)
        #expect(vault.notes[0].relativePath == "Archive/Doc.md")
    }

    @Test func duplicateCreatesIncrementingNames() throws {
        let (vault, _) = try makeTemporaryVault()
        let entry = try vault.createNote(folder: "", title: "Base", content: "v1")
        let copy1 = try vault.duplicate(entry.relativePath)
        let copy2 = try vault.duplicate(entry.relativePath)
        #expect(copy1.name == "Base copy.md")
        #expect(copy2.name == "Base copy 2.md")
        #expect(try vault.readNote(copy2.relativePath) == "v1")
    }

    @Test func trashRemovesEntry() throws {
        let (vault, _) = try makeTemporaryVault()
        let entry = try vault.createNote(folder: "", title: "Doomed", content: "")
        try vault.trash(entry.relativePath)
        #expect(vault.notes.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: vault.absoluteURL(for: entry.relativePath).path))
    }

    @Test func writeNoteDetectsExternalChange() async throws {
        let (vault, root) = try makeTemporaryVault()
        let entry = try vault.createNote(folder: "", title: "Conflict", content: "original")
        let synced = vault.currentModificationDate(of: entry.relativePath)!
        // Simulate an external modification after our last sync.
        try await Task.sleep(nanoseconds: 50_000_000)
        try "external edit".write(to: root.appendingPathComponent("Conflict.md"), atomically: true, encoding: .utf8)
        #expect(throws: VaultError.self) {
            try vault.writeNote(entry.relativePath, content: "local edit", requireUnchangedSince: synced)
        }
        // And a clean save succeeds.
        try vault.writeNote(entry.relativePath, content: "local edit", requireUnchangedSince: vault.currentModificationDate(of: entry.relativePath))
        #expect(try vault.readNote(entry.relativePath) == "local edit")
    }

    @Test func pathTraversalIsRejected() throws {
        // Externally supplied paths must be validated before reaching
        // absoluteURL (which asserts the invariant for programmer errors).
        #expect(!VaultStore.isSafeRelativePath("../escape.md"))
        #expect(!VaultStore.isSafeRelativePath("/absolute.md"))
        #expect(!VaultStore.isSafeRelativePath("a/../b.md"))
        #expect(!VaultStore.isSafeRelativePath(""))
        #expect(VaultStore.isSafeRelativePath("folder/note.md"))
        #expect(VaultStore.isSafeRelativePath("日本語 ノート.md"))
        let (vault, _) = try makeTemporaryVault()
        let url = vault.absoluteURL(for: "folder/note.md")
        #expect(url.path.hasSuffix("folder/note.md"))
    }

    @Test func externalFileAdditionIsDetectedOnRescan() async throws {
        let (vault, root) = try makeTemporaryVault()
        #expect(vault.notes.isEmpty)
        try "# External".write(to: root.appendingPathComponent("External.md"), atomically: true, encoding: .utf8)
        vault.rescan()
        // Scan is synchronous when scanSynchronously is used; rescan is async.
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(vault.notes.count == 1)
        #expect(vault.notes[0].name == "External.md")
    }

    @Test func hiddenFilesRespected() async throws {
        let (vault, root) = try makeTemporaryVault()
        try "visible".write(to: root.appendingPathComponent("Visible.md"), atomically: true, encoding: .utf8)
        try "hidden".write(to: root.appendingPathComponent(".Hidden.md"), atomically: true, encoding: .utf8)
        vault.rescan()
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(vault.notes.count == 1)
        vault.showsHiddenFiles = true
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(vault.notes.count == 2)
    }

    @Test func metadataPersistsAcrossInstances() throws {
        let (vault, root) = try makeTemporaryVault()
        vault.updateMetadata { $0.dailyNotesFolder = "Journal" }
        let reopened = try VaultStore(rootURL: root, monitor: false, scanSynchronously: true)
        #expect(reopened.metadata.dailyNotesFolder == "Journal")
    }
}

@MainActor
@Suite("Snapshot Store")
struct SnapshotStoreTests {

    @Test func capturesListsAndRestores() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("snap-\(UUID())", isDirectory: true)
        let store = SnapshotStore(baseDirectory: base)
        let (vault, root) = try makeTemporaryVault()
        let entry = try vault.createNote(folder: "", title: "Doc", content: "v1")

        #expect(store.capture(vaultRoot: root, relativePath: entry.relativePath, content: "v1") != nil)
        // Identical content is not captured twice.
        #expect(store.capture(vaultRoot: root, relativePath: entry.relativePath, content: "v1") == nil)

        _ = try vault.writeNote(entry.relativePath, content: "v2")
        #expect(store.capture(vaultRoot: root, relativePath: entry.relativePath, content: "v2") != nil)

        let snapshots = store.list(vaultRoot: root, relativePath: entry.relativePath)
        #expect(snapshots.count == 2)
        #expect(snapshots.first!.timestamp >= snapshots.last!.timestamp)

        // Restore the oldest snapshot.
        try store.restore(vaultRoot: root, snapshot: snapshots.last!, to: vault)
        #expect(try vault.readNote(entry.relativePath) == "v1")

        store.deleteAllSnapshots(vaultRoot: root, relativePath: entry.relativePath)
        #expect(store.list(vaultRoot: root, relativePath: entry.relativePath).isEmpty)
    }

    @Test func retentionCapsPerNote() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("snap-\(UUID())", isDirectory: true)
        let store = SnapshotStore(baseDirectory: base)
        let (vault, root) = try makeTemporaryVault()
        let entry = try vault.createNote(folder: "", title: "Doc", content: "")
        for i in 0..<(SnapshotStore.maxSnapshotsPerNote + 10) {
            _ = store.capture(vaultRoot: root, relativePath: entry.relativePath, content: "version \(i)")
        }
        #expect(store.list(vaultRoot: root, relativePath: entry.relativePath).count == SnapshotStore.maxSnapshotsPerNote)
    }

    @Test func vaultFolderNameIsStableAndSafe() {
        let a = SnapshotStore.vaultFolderName(for: URL(fileURLWithPath: "/tmp/vault one"))
        let b = SnapshotStore.vaultFolderName(for: URL(fileURLWithPath: "/tmp/vault one"))
        let c = SnapshotStore.vaultFolderName(for: URL(fileURLWithPath: "/tmp/vault two"))
        #expect(a == b)
        #expect(a != c)
        #expect(!a.contains("/"))
    }
}

@MainActor
@Suite("Workspace Store")
struct WorkspaceStoreTests {

    @Test func persistsWorkspacesAndRecents() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ws-\(UUID())", isDirectory: true)
        let store = WorkspaceStore(baseDirectory: dir)
        let path = "/tmp/vault-\(UUID())"
        store.add(workspace: Workspace(name: "Vault", path: path))
        store.recordRecentFile(workspacePath: path, relativePath: "a.md")
        store.recordRecentFile(workspacePath: path, relativePath: "b.md")
        store.recordRecentFile(workspacePath: path, relativePath: "a.md")

        let reloaded = WorkspaceStore(baseDirectory: dir)
        #expect(reloaded.workspaces.count == 1)
        #expect(reloaded.workspaces[0].name == "Vault")
        #expect(reloaded.recentFiles(forWorkspace: path) == ["a.md", "b.md"])

        reloaded.remove(path: path)
        #expect(reloaded.workspaces.isEmpty)
        #expect(reloaded.recentFiles(forWorkspace: path).isEmpty)
    }

    @Test func mostRecentlyUsedIsFirst() {
        let store = WorkspaceStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("ws-\(UUID())"))
        store.add(workspace: Workspace(name: "A", path: "/tmp/a"))
        store.add(workspace: Workspace(name: "B", path: "/tmp/b"))
        store.touch(path: "/tmp/a")
        #expect(store.mostRecentlyUsed()?.name == "A")
    }
}
