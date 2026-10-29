import Foundation

/// A registered workspace (vault).
public struct Workspace: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var path: String
    public var lastOpened: Date

    public init(id: UUID = UUID(), name: String, path: String, lastOpened: Date = Date()) {
        self.id = id
        self.name = name
        self.path = path
        self.lastOpened = lastOpened
    }
}

/// Persists the list of workspaces and recently opened files as JSON in the
/// app's Application Support directory. The directory is injectable for tests.
public final class WorkspaceStore {

    private let fileURL: URL
    private let fileManager = FileManager.default

    public private(set) var workspaces: [Workspace] = []
    public private(set) var recentFiles: [String: [String]] = [:]   // workspace path → relative paths

    public init(baseDirectory: URL? = nil) {
        let support = baseDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = support.appendingPathComponent("SakuraNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("workspaces.json")
        load()
    }

    // MARK: - Workspaces

    public func add(workspace: Workspace) {
        workspaces.removeAll { $0.path == workspace.path }
        workspaces.insert(workspace, at: 0)
        workspaces.sort { $0.lastOpened > $1.lastOpened }
        save()
    }

    public func remove(path: String) {
        workspaces.removeAll { $0.path == path }
        recentFiles.removeValue(forKey: path)
        save()
    }

    public func rename(path: String, newName: String) {
        if let index = workspaces.firstIndex(where: { $0.path == path }) {
            workspaces[index].name = newName
            save()
        }
    }

    public func workspace(atPath path: String) -> Workspace? {
        workspaces.first { $0.path == path }
    }

    /// Marks a workspace as most recently used.
    public func touch(path: String) {
        guard let index = workspaces.firstIndex(where: { $0.path == path }) else { return }
        workspaces[index].lastOpened = Date()
        workspaces.sort { $0.lastOpened > $1.lastOpened }
        save()
    }

    public func mostRecentlyUsed() -> Workspace? {
        workspaces.first
    }

    /// Prunes workspaces whose directories no longer exist.
    public func pruneMissing() {
        let before = workspaces.count
        workspaces.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
        if workspaces.count != before { save() }
    }

    // MARK: - Recent files

    public func recordRecentFile(workspacePath: String, relativePath: String) {
        var recents = recentFiles[workspacePath] ?? []
        recents.removeAll { $0 == relativePath }
        recents.insert(relativePath, at: 0)
        if recents.count > 30 { recents = Array(recents.prefix(30)) }
        recentFiles[workspacePath] = recents
        save()
    }

    public func recentFiles(forWorkspace workspacePath: String) -> [String] {
        recentFiles[workspacePath] ?? []
    }

    // MARK: - Persistence

    private struct Payload: Codable {
        var workspaces: [Workspace]
        var recentFiles: [String: [String]]
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        workspaces = payload.workspaces
        recentFiles = payload.recentFiles ?? [:]
    }

    private func save() {
        let payload = Payload(workspaces: workspaces, recentFiles: recentFiles)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        try? AtomicFile.write(data, to: fileURL, createDirectories: false)
    }
}
