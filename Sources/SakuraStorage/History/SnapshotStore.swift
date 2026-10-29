import Foundation

/// A single version snapshot of a note.
public struct NoteSnapshot: Identifiable, Equatable {
    public var id: String { "\(relativePath)#\(timestamp.timeIntervalSince1970)" }
    public let relativePath: String
    public let timestamp: Date
    public let byteSize: Int

    public init(relativePath: String, timestamp: Date, byteSize: Int) {
        self.relativePath = relativePath
        self.timestamp = timestamp
        self.byteSize = byteSize
    }
}

/// Stores version history for notes under the app's Application Support
/// directory (never inside the vault, which belongs to the user's files).
///
/// Snapshots are captured:
/// - when an externally modified file is about to be overwritten,
/// - before AI edits are applied,
/// - and whenever the app detects a meaningful external change.
///
/// All content stays on disk as plain `.md` files and can be inspected in
/// Finder; the index is rebuildable from the file names themselves.
public final class SnapshotStore {

    public static let maxSnapshotsPerNote = 50

    private let baseDirectory: URL
    private let fileManager = FileManager.default
    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    /// Default location: ~/Library/Application Support/SakuraNotes/History
    public static func defaultBaseDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("SakuraNotes/History", isDirectory: true)
    }

    /// Stable per-vault directory name derived from the vault root path.
    /// Hashed rather than used raw so paths with slashes are safe.
    public static func vaultFolderName(for vaultRoot: URL) -> String {
        let raw = vaultRoot.standardizedFileURL.path
        // FNV-1a 64-bit for a short, stable, filesystem-safe identifier.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in raw.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    /// File-name-safe encoding of a relative path so `/` becomes a literal
    /// separator-free token.
    static func encodedRelativePath(_ relativePath: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.")
        return relativePath.addingPercentEncoding(withAllowedCharacters: allowed) ?? relativePath
    }

    static func decodedRelativePath(_ encoded: String) -> String {
        encoded.removingPercentEncoding ?? encoded
    }

    private func noteDirectory(vaultRoot: URL, relativePath: String) -> URL {
        baseDirectory
            .appendingPathComponent(Self.vaultFolderName(for: vaultRoot), isDirectory: true)
            .appendingPathComponent(Self.encodedRelativePath(relativePath), isDirectory: true)
    }

    /// Captures a snapshot. Returns the created snapshot, or nil if the
    /// content is byte-identical to the newest existing snapshot.
    @discardableResult
    public func capture(vaultRoot: URL, relativePath: String, content: String) -> NoteSnapshot? {
        let dir = noteDirectory(vaultRoot: vaultRoot, relativePath: relativePath)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let snapshots = list(vaultRoot: vaultRoot, relativePath: relativePath)
        if let newest = snapshots.first {
            let newestURL = dir.appendingPathComponent(Self.fileName(for: newest.timestamp))
            if let existing = try? String(contentsOf: newestURL, encoding: .utf8), existing == content {
                return nil
            }
        }
        let now = Date()
        let url = dir.appendingPathComponent(Self.fileName(for: now))
        do {
            try AtomicFile.write(text: content, to: url, createDirectories: false)
        } catch {
            return nil
        }
        enforceRetention(vaultRoot: vaultRoot, relativePath: relativePath)
        return NoteSnapshot(relativePath: relativePath, timestamp: now, byteSize: content.utf8.count)
    }

    public func list(vaultRoot: URL, relativePath: String) -> [NoteSnapshot] {
        let dir = noteDirectory(vaultRoot: vaultRoot, relativePath: relativePath)
        guard let names = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return [] }
        var snapshots: [NoteSnapshot] = []
        for name in names where name.hasSuffix(".md") {
            let iso = String(name.dropLast(3))
            guard let date = timestampFormatter.date(from: iso) else { continue }
            let url = dir.appendingPathComponent(name)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            snapshots.append(NoteSnapshot(relativePath: relativePath, timestamp: date, byteSize: size))
        }
        return snapshots.sorted { $0.timestamp > $1.timestamp }
    }

    public func content(vaultRoot: URL, of snapshot: NoteSnapshot) -> String? {
        let dir = noteDirectory(vaultRoot: vaultRoot, relativePath: snapshot.relativePath)
        let url = dir.appendingPathComponent(Self.fileName(for: snapshot.timestamp))
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Restores a snapshot by writing its content into the note file.
    public func restore(vaultRoot: URL, snapshot: NoteSnapshot, to vault: VaultStore) throws {
        guard let content = content(vaultRoot: vaultRoot, of: snapshot) else {
            throw VaultError.noteNotFound(snapshot.relativePath)
        }
        // Capture the current state before overwriting so a restore is itself reversible.
        if let current = try? vault.readNote(snapshot.relativePath) {
            capture(vaultRoot: vaultRoot, relativePath: snapshot.relativePath, content: current)
        }
        try vault.writeNote(snapshot.relativePath, content: content)
    }

    public func deleteAllSnapshots(vaultRoot: URL, relativePath: String) {
        let dir = noteDirectory(vaultRoot: vaultRoot, relativePath: relativePath)
        try? fileManager.removeItem(at: dir)
    }

    /// Total snapshots stored (used by the settings "history size" indicator).
    public func totalCount() -> Int {
        guard let vaultDirs = try? fileManager.contentsOfDirectory(atPath: baseDirectory.path) else { return 0 }
        var total = 0
        for vaultDir in vaultDirs {
            let vaultURL = baseDirectory.appendingPathComponent(vaultDir)
            guard let noteDirs = try? fileManager.contentsOfDirectory(atPath: vaultURL.path) else { continue }
            for noteDir in noteDirs {
                let files = try? fileManager.contentsOfDirectory(atPath: vaultURL.appendingPathComponent(noteDir).path)
                total += files?.count ?? 0
            }
        }
        return total
    }

    private func enforceRetention(vaultRoot: URL, relativePath: String) {
        let snapshots = list(vaultRoot: vaultRoot, relativePath: relativePath)
        guard snapshots.count > Self.maxSnapshotsPerNote else { return }
        let dir = noteDirectory(vaultRoot: vaultRoot, relativePath: relativePath)
        for stale in snapshots.suffix(from: Self.maxSnapshotsPerNote) {
            try? fileManager.removeItem(at: dir.appendingPathComponent(Self.fileName(for: stale.timestamp)))
        }
    }

    private static func fileName(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date) + ".md"
    }
}
