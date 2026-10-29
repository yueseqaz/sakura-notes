import Foundation
import SakuraCore
import SakuraStorage

/// One outgoing wiki link or explicit internal link from a note.
public struct OutgoingLink: Equatable, Identifiable {
    public var id: String { "\(source)#\(target)#\(lineIndex)" }
    public let source: String
    public let target: String
    public let lineIndex: Int
    public let resolvedPath: String?
}

/// Derived link graph over the vault: outgoing links, backlinks, orphans, and
/// graph edges. Fully rebuildable from note contents.
///
/// Wiki link resolution rules (deterministic):
/// 1. Exact vault-relative path match (`[[folder/note]]`) wins.
/// 2. Otherwise, case-insensitive match on the resolved note title
///    (front matter title → first heading → file name).
/// 3. Ties prefer a note in the same folder, then the alphabetically first.
public final class LinkIndex {

    struct NoteLinks {
        var title: String
        var folder: String
        var outgoing: [String]
    }

    private let lock = NSLock()
    private var linksByPath: [String: NoteLinks] = [:]
    /// title (lowercased) → note paths
    private var pathsByTitle: [String: Set<String>] = [:]
    /// file name without extension (lowercased) → note paths
    private var pathsByFileName: [String: Set<String>] = [:]

    public init() {}

    // MARK: - Mutation

    public func update(path: String, facts: NoteFacts) {
        lock.lock()
        defer { lock.unlock() }
        if let existing = linksByPath[path] {
            let oldTitleKey = existing.title.lowercased()
            pathsByTitle[oldTitleKey]?.remove(path)
            if pathsByTitle[oldTitleKey]?.isEmpty == true { pathsByTitle.removeValue(forKey: oldTitleKey) }
        }
        let title = facts.title ?? (path as NSString).deletingPathExtension
        let targets = facts.links.compactMap { link -> String? in
            if case .wikiLink(let target, _) = link.kind { return target }
            return nil
        }
        if let existing = linksByPath[path] {
            let oldFileKey = (((existing.folder as NSString).lastPathComponent) as NSString).deletingPathExtension.lowercased()
            pathsByFileName[oldFileKey]?.remove(path)
        }
        linksByPath[path] = NoteLinks(title: title, folder: (path as NSString).deletingLastPathComponent, outgoing: targets)
        pathsByTitle[title.lowercased(), default: []].insert(path)
        let fileNameKey = (((path as NSString).lastPathComponent) as NSString).deletingPathExtension.lowercased()
        pathsByFileName[fileNameKey, default: []].insert(path)
    }

    public func remove(path: String) {
        lock.lock()
        defer { lock.unlock() }
        if let existing = linksByPath.removeValue(forKey: path) {
            let key = existing.title.lowercased()
            pathsByTitle[key]?.remove(path)
            if pathsByTitle[key]?.isEmpty == true { pathsByTitle.removeValue(forKey: key) }
            let fileKey = (((path as NSString).lastPathComponent) as NSString).deletingPathExtension.lowercased()
            pathsByFileName[fileKey]?.remove(path)
            if pathsByFileName[fileKey]?.isEmpty == true { pathsByFileName.removeValue(forKey: fileKey) }
        }
    }

    public func rename(from: String, to: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let existing = linksByPath.removeValue(forKey: from) else { return }
        linksByPath[to] = existing
        let key = existing.title.lowercased()
        pathsByTitle[key]?.remove(from)
        pathsByTitle[key, default: []].insert(to)
    }

    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        linksByPath.removeAll()
        pathsByTitle.removeAll()
        pathsByFileName.removeAll()
    }

    // MARK: - Queries

    /// Resolves a wiki link target to a note path under the current title map.
    public func resolve(target: String, fromFolder: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return resolveUnlocked(target: target, fromFolder: fromFolder)
    }

    /// Notes that link to the given note (directly or via its title).
    public func backlinks(to path: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard let self_ = linksByPath[path] else { return [] }
        let titleKey = self_.title.lowercased()
        var result: Set<String> = []
        for (source, links) in linksByPath where source != path {
            for target in links.outgoing {
                if target == path
                    || target.lowercased() == titleKey
                    || pathsByTitle[target.lowercased()]?.contains(path) == true {
                    result.insert(source)
                    break
                }
            }
        }
        return result.sorted()
    }

    /// Outgoing links of a note, with resolution applied.
    public func outgoingLinks(from path: String) -> [OutgoingLink] {
        lock.lock()
        defer { lock.unlock() }
        guard let noteLinks = linksByPath[path] else { return [] }
        return noteLinks.outgoing.enumerated().map { _, target in
            OutgoingLink(
                source: path,
                target: target,
                lineIndex: 0,
                resolvedPath: resolveUnlocked(target: target, fromFolder: noteLinks.folder)
            )
        }
    }

    /// Unresolved outgoing targets of a note (broken links).
    public func brokenLinks(from path: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard let noteLinks = linksByPath[path] else { return [] }
        return noteLinks.outgoing.filter { resolveUnlocked(target: $0, fromFolder: noteLinks.folder) == nil }
    }

    /// All notes with title + outgoing count, for graph building.
    public func graphSnapshot() -> [(path: String, title: String, outgoing: [String])] {
        lock.lock()
        defer { lock.unlock() }
        return linksByPath.keys.sorted().map { path in
            let links = linksByPath[path]!
            return (path, links.title, links.outgoing)
        }
    }

    /// Notes that no other note links to.
    public func orphanNotes() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        var linked: Set<String> = []
        for (_, noteLinks) in linksByPath {
            for target in noteLinks.outgoing {
                if let resolved = resolveUnlocked(target: target, fromFolder: noteLinks.folder) {
                    linked.insert(resolved)
                }
            }
        }
        return linksByPath.keys.filter { !linked.contains($0) }.sorted()
    }

    /// Notes whose outgoing wiki links cannot be resolved.
    public func allBrokenLinkSources() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        var result: [String] = []
        for (path, noteLinks) in linksByPath.sorted(by: { $0.key < $1.key }) {
            if noteLinks.outgoing.contains(where: { resolveUnlocked(target: $0, fromFolder: noteLinks.folder) == nil }) {
                result.append(path)
            }
        }
        return result
    }

    public var noteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return linksByPath.count
    }

    // MARK: - Internals (caller holds lock)

    private func resolveUnlocked(target: String, fromFolder: String) -> String? {
        let clean = target.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return nil }
        if linksByPath[clean] != nil { return clean }
        let lowered = clean.lowercased()
        let candidates = pathsByTitle[lowered] ?? pathsByFileName[lowered] ?? []
        if !candidates.isEmpty {
            if let sameFolder = candidates.first(where: { ($0 as NSString).deletingLastPathComponent == fromFolder }) {
                return sameFolder
            }
            return candidates.sorted().first
        }
        return nil
    }
}
