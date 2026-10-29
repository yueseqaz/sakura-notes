import Foundation

/// A note (or attachment) tracked by the vault, identified by its path
/// relative to the vault root using POSIX separators.
public struct NoteEntry: Identifiable, Hashable {
    public var id: String { relativePath }
    public let relativePath: String
    public let name: String
    public let modificationDate: Date
    public let size: Int

    public init(relativePath: String, name: String, modificationDate: Date, size: Int) {
        self.relativePath = relativePath
        self.name = name
        self.modificationDate = modificationDate
        self.size = size
    }

    public var fileName: String { (relativePath as NSString).lastPathComponent }
    public var fileExtension: String { (relativePath as NSString).pathExtension.lowercased() }
    public var displayName: String { (name as NSString).deletingPathExtension }
    public var folderPath: String {
        let dir = (relativePath as NSString).deletingLastPathComponent
        return dir == relativePath ? "" : dir
    }
}

/// A folder in the vault tree.
public final class FolderNode: Hashable {
    public let name: String
    public let relativePath: String
    public var children: [VaultNode]

    public init(name: String, relativePath: String, children: [VaultNode] = []) {
        self.name = name
        self.relativePath = relativePath
        self.children = children
    }

    public static func == (lhs: FolderNode, rhs: FolderNode) -> Bool { lhs.relativePath == rhs.relativePath }
    public func hash(into hasher: inout Hasher) { hasher.combine(relativePath) }

    func setChildren(_ newChildren: [VaultNode]) { children = newChildren }
}

/// A node in the vault tree.
public enum VaultNode: Hashable {
    case folder(FolderNode)
    case note(NoteEntry)

    public var name: String {
        switch self {
        case .folder(let f): return f.name
        case .note(let n): return n.name
        }
    }

    public var relativePath: String {
        switch self {
        case .folder(let f): return f.relativePath
        case .note(let n): return n.relativePath
        }
    }
}

/// File kinds the app recognizes.
public enum TextFileKind: Equatable {
    case markdown
    case plainText
    case image
    case pdf
    case other

    public static func classify(fileExtension ext: String) -> TextFileKind {
        switch ext.lowercased() {
        case "md", "markdown", "mdown", "mkd":
            return .markdown
        case "txt", "text":
            return .plainText
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "tiff", "heic":
            return .image
        case "pdf":
            return .pdf
        default:
            return .other
        }
    }
}
