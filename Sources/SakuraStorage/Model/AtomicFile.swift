import Foundation

/// Errors surfaced by vault operations. All are user-presentable.
public enum VaultError: LocalizedError, Equatable {
    case noteNotFound(String)
    case duplicateName(String)
    case externalChangeDetected(path: String)
    case writeFailed(path: String, underlying: String)
    case readFailed(path: String, underlying: String)
    case notADirectory
    case trashFailed(path: String, underlying: String)
    case invalidPath(String)

    public var errorDescription: String? {
        switch self {
        case .noteNotFound(let p): return "The note “\(p)” could not be found on disk."
        case .duplicateName(let n): return "An item named “\(n)” already exists in this folder."
        case .externalChangeDetected(let p): return "“\(p)” was changed by another application while you had unsaved edits."
        case .writeFailed(let p, let u): return "Could not save “\(p)”: \(u)"
        case .readFailed(let p, let u): return "Could not read “\(p)”: \(u)"
        case .notADirectory: return "The selected workspace path is not a folder."
        case .trashFailed(let p, let u): return "Could not move “\(p)” to Trash: \(u)"
        case .invalidPath(let p): return "The path “\(p)” is not valid."
        }
    }
}

/// Writes file content atomically: content goes to a temporary file in the
/// destination directory, is flushed, and is then renamed over the target so
/// an interrupted write can never truncate or corrupt the original.
public enum AtomicFile {

    /// Writes `data` to `url` atomically. Creates parent directories when asked.
    public static func write(_ data: Data, to url: URL, createDirectories: Bool = true) throws {
        let directory = url.deletingLastPathComponent()
        if createDirectories && !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let tempName = ".\(ProcessInfo.processInfo.globallyUniqueString).tmp"
        let tempURL = directory.appendingPathComponent(tempName)
        guard FileManager.default.createFile(atPath: tempURL.path, contents: data, attributes: nil) else {
            throw VaultError.writeFailed(path: url.lastPathComponent, underlying: "Could not create temporary file.")
        }
        // Explicitly sync before rename so the data is on disk before the
        // original file is replaced.
        let handle: FileHandle
        do {
            handle = try FileHandle(forWritingTo: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw VaultError.writeFailed(path: url.lastPathComponent, underlying: error.localizedDescription)
        }
        do {
            try handle.synchronizeFile()
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: tempURL)
            throw VaultError.writeFailed(path: url.lastPathComponent, underlying: error.localizedDescription)
        }
        do {
            // rename(2) is atomic within a volume; use it rather than the
            // FileManager replacement which can leave backups behind.
            if rename(tempURL.path, url.path) != 0 {
                let errnoCopy = errno
                throw VaultError.writeFailed(path: url.lastPathComponent, underlying: String(cString: strerror(errnoCopy)))
            }
        } catch let error as VaultError {
            throw error
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw VaultError.writeFailed(path: url.lastPathComponent, underlying: error.localizedDescription)
        }
    }

    public static func write(text: String, to url: URL, createDirectories: Bool = true) throws {
        try write(Data(text.utf8), to: url, createDirectories: createDirectories)
    }
}
