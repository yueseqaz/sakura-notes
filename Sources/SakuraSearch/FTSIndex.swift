import Foundation
import SQLite3
import SakuraCore

/// A single search hit.
public struct SearchResult: Identifiable, Equatable {
    public var id: String { path }
    public let path: String
    public let title: String
    /// Snippet with `<mark>` around matched terms (app layer converts to rich text).
    public let snippet: String
    public let matchedInTitle: Bool
    public let modificationDate: Date
}

/// Result of an index status check, for the UI's "index status" affordance.
public struct IndexStatus: Equatable {
    public var noteCount: Int
    public var isReady: Bool
    public var lastError: String?
}

/// Full-text index over the vault, backed by SQLite FTS5.
///
/// The index is fully derived state: it can be deleted and rebuilt from the
/// underlying Markdown files at any time, and index failures never make notes
/// inaccessible (the caller falls back to listing).
///
/// Thread safety: all operations run on an internal serial queue. Search is
/// synchronous but fast; callers should still invoke from background queues.
public final class FTSIndex {

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.sakuranotes.ftsindex", qos: .userInitiated)
    private let databaseURL: URL

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
        var dbPointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(databaseURL.path, &dbPointer, flags, nil)
        guard result == SQLITE_OK, let dbPointer else {
            sqlite3_close(dbPointer)
            self.db = nil
            return
        }
        self.db = dbPointer
        queue.sync { setupSchema() }
    }

    public var isAvailable: Bool { db != nil }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Schema

    private func setupSchema() {
        exec("PRAGMA journal_mode=WAL")
        exec("""
        CREATE TABLE IF NOT EXISTS notes (
            id INTEGER PRIMARY KEY,
            path TEXT UNIQUE NOT NULL,
            title TEXT NOT NULL DEFAULT '',
            folder TEXT NOT NULL DEFAULT '',
            tags TEXT NOT NULL DEFAULT '',
            ext TEXT NOT NULL DEFAULT '',
            mtime REAL NOT NULL DEFAULT 0
        )
        """)
        exec("""
        CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
            title, body, tags,
            tokenize = 'unicode61 remove_diacritics 2'
        )
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_notes_mtime ON notes(mtime)")
    }

    private func exec(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func lastErrorMessage() -> String {
        guard let db else { return "database unavailable" }
        return String(cString: sqlite3_errmsg(db))
    }

    // MARK: - Indexing

    public struct IndexedNote {
        public let path: String
        public let title: String
        public let body: String
        public let tags: [String]
        public let modificationDate: Date

        public init(path: String, title: String, body: String, tags: [String], modificationDate: Date) {
            self.path = path
            self.title = title
            self.body = body
            self.tags = tags
            self.modificationDate = modificationDate
        }
    }

    /// Adds or replaces a note in the index.
    public func indexNote(_ note: IndexedNote) {
        queue.sync {
            guard let db else { return }
            removeInternal(note.path)
            let ext = (note.path as NSString).pathExtension.lowercased()
            let folder = (note.path as NSString).deletingLastPathComponent
            let tags = "," + note.tags.joined(separator: ",").lowercased() + ","

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, "INSERT INTO notes(path, title, folder, tags, ext, mtime) VALUES(?,?,?,?,?,?)", -1, &statement, nil) == SQLITE_OK else { return }
            bind(statement, 1, note.path)
            bind(statement, 2, note.title)
            bind(statement, 3, folder)
            bind(statement, 4, tags)
            bind(statement, 5, ext)
            sqlite3_bind_double(statement, 6, note.modificationDate.timeIntervalSince1970)
            guard sqlite3_step(statement) == SQLITE_DONE else { return }
            let rowID = sqlite3_last_insert_rowid(db)

            var ftsStatement: OpaquePointer?
            defer { sqlite3_finalize(ftsStatement) }
            guard sqlite3_prepare_v2(db, "INSERT INTO notes_fts(rowid, title, body, tags) VALUES(?,?,?,?)", -1, &ftsStatement, nil) == SQLITE_OK else { return }
            sqlite3_bind_int64(ftsStatement, 1, rowID)
            bind(ftsStatement, 2, note.title)
            bind(ftsStatement, 3, note.body)
            bind(ftsStatement, 4, tags)
            _ = sqlite3_step(ftsStatement)
        }
    }

    public func removeNote(_ path: String) {
        queue.sync {
            removeInternal(path)
        }
    }

    private func removeInternal(_ path: String) {
        guard let db else { return }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT id FROM notes WHERE path = ?", -1, &statement, nil) == SQLITE_OK else { return }
        bind(statement, 1, path)
        if sqlite3_step(statement) == SQLITE_ROW {
            let rowID = sqlite3_column_int64(statement, 0)
            var deleteFTS: OpaquePointer?
            defer { sqlite3_finalize(deleteFTS) }
            if sqlite3_prepare_v2(db, "DELETE FROM notes_fts WHERE rowid = ?", -1, &deleteFTS, nil) == SQLITE_OK {
                sqlite3_bind_int64(deleteFTS, 1, rowID)
                _ = sqlite3_step(deleteFTS)
            }
            var deleteNote: OpaquePointer?
            defer { sqlite3_finalize(deleteNote) }
            if sqlite3_prepare_v2(db, "DELETE FROM notes WHERE id = ?", -1, &deleteNote, nil) == SQLITE_OK {
                sqlite3_bind_int64(deleteNote, 1, rowID)
                _ = sqlite3_step(deleteNote)
            }
        }
    }

    public func removeAll() {
        queue.sync {
            exec("DELETE FROM notes")
            exec("DELETE FROM notes_fts")
        }
    }

    public func noteCount() -> Int {
        queue.sync {
            guard let db else { return 0 }
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM notes", -1, &statement, nil) == SQLITE_OK else { return 0 }
            guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    public func indexedPaths() -> [String] {
        queue.sync {
            guard let db else { return [] }
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, "SELECT path FROM notes", -1, &statement, nil) == SQLITE_OK else { return [] }
            var paths: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let cPath = sqlite3_column_text(statement, 0) {
                    paths.append(String(cString: cPath))
                }
            }
            return paths
        }
    }

    // MARK: - Searching

    /// Executes a parsed query. Returns up to `limit` results ordered by rank.
    public func search(_ query: SearchQuery, limit: Int = 200) -> [SearchResult] {
        queue.sync { () -> [SearchResult] in
            guard let db else { return [] }
            guard !query.isEmpty else { return [] }

            let matchExpression = Self.buildMatchExpression(query)
            var whereClauses: [String] = []
            var params: [String] = []
            if let matchExpression {
                whereClauses.append("notes_fts MATCH ?")
                params.append(matchExpression)
            }
            // CJK-only queries cannot use the word tokenizer; fall back to
            // substring matching over the stored text.
            if matchExpression == nil {
                let cjkTerms = (query.terms + query.phrases).filter { $0.containsCJK }
                for term in cjkTerms {
                    whereClauses.append("(notes_fts.body LIKE ? OR LOWER(n.title) LIKE ?)")
                    params.append("%\(term)%")
                    params.append("%\(term.lowercased())%")
                }
            }
            for tag in query.requiredTags {
                whereClauses.append("n.tags LIKE ?")
                params.append("%,\(tag.lowercased()),%")
            }
            for path in query.pathFilters {
                whereClauses.append("n.folder LIKE ?")
                params.append("%\(path)%")
            }
            if !query.extensions.isEmpty {
                let placeholders = query.extensions.map { _ in "?" }.joined(separator: ",")
                whereClauses.append("n.ext IN (\(placeholders))")
                params.append(contentsOf: query.extensions.map { $0.lowercased() })
            }
            for title in query.titleFilters {
                whereClauses.append("LOWER(n.title) LIKE ?")
                params.append("%\(title.lowercased())%")
            }
            if let before = query.modifiedBefore {
                whereClauses.append("n.mtime <= ?")
                params.append(String(before.timeIntervalSince1970))
            }
            if let after = query.modifiedAfter {
                whereClauses.append("n.mtime >= ?")
                params.append(String(after.timeIntervalSince1970))
            }
            var excludedClauses: [String] = []
            for excluded in query.excludedTerms {
                excludedClauses.append("(LOWER(n.title) NOT LIKE ? AND LOWER(n.tags) NOT LIKE ?)")
                params.append("%\(excluded.lowercased())%")
                params.append("%\(excluded.lowercased())%")
            }
            whereClauses.append(contentsOf: excludedClauses)

            // Prefer title matches, then FTS rank, then recency.
            let titleParamIndex = params.count + 1
            let firstTerm = (query.terms.first ?? query.phrases.first ?? "").lowercased()
            let orderBy = matchExpression != nil ? "in_title DESC, rank" : "n.mtime DESC"
            let sql = """
            SELECT n.path, n.title, snippet(notes_fts, 1, '<mark>', '</mark>', '…', 24) AS snip,
                   n.mtime,
                   (LOWER(n.title) LIKE ?) AS in_title
            FROM notes_fts
            JOIN notes n ON n.id = notes_fts.rowid
            WHERE \(whereClauses.joined(separator: " AND "))
            ORDER BY \(orderBy)
            LIMIT \(max(1, limit))
            """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
            var index: Int32 = 1
            for param in params {
                bind(statement, index, param)
                index += 1
            }
            bind(statement, Int32(titleParamIndex), "%\(firstTerm)%")
            var results: [SearchResult] = []
            while sqlite3_step(statement) == SQLITE_ROW, results.count < limit {
                let path = columnString(statement, 0)
                let title = columnString(statement, 1)
                let snippet = columnString(statement, 2)
                let mtime = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
                let inTitle = sqlite3_column_int64(statement, 4) != 0
                results.append(SearchResult(path: path, title: title, snippet: snippet, matchedInTitle: inTitle, modificationDate: mtime))
            }
            return results
        }
    }

    /// Builds an FTS5 MATCH expression from the parsed query, or nil when the
    /// query should fall back to filters-only (e.g. CJK terms, which the
    /// unicode61 tokenizer does not segment).
    static func buildMatchExpression(_ query: SearchQuery) -> String? {
        var parts: [String] = []
        func escape(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }

        let latinTerms = (query.terms + query.phrases).filter { !$0.containsCJK }
        let cjkTerms = (query.terms + query.phrases).filter { $0.containsCJK }

        for term in latinTerms where !term.isEmpty {
            if term.contains(where: { $0.isWhitespace }) {
                parts.append(escape(term))
            } else {
                parts.append("\(escape(term))*")
            }
        }
        if !cjkTerms.isEmpty {
            // CJK text is not tokenized into words; match via quoted literals
            // only works if a token boundary aligns, so we signal fallback.
            if parts.isEmpty { return nil }
        }
        if parts.isEmpty { return nil }
        var expression = parts.joined(separator: " ")
        for excluded in query.excludedTerms where !excluded.isEmpty {
            if !excluded.containsCJK {
                expression += " NOT \(escape(excluded))*"
            }
        }
        return expression
    }

    /// Notes whose body or title contains `text` as a substring, excluding
    /// `excludingPath`. Used for unlinked-mention suggestions.
    public func notesContaining(text: String, excludingPath: String, limit: Int = 50) -> [String] {
        queue.sync { () -> [String] in
            guard let db, !text.isEmpty else { return [] }
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            let sql = """
            SELECT n.path FROM notes_fts
            JOIN notes n ON n.id = notes_fts.rowid
            WHERE (notes_fts.body LIKE ? OR n.title LIKE ?) AND n.path != ?
            ORDER BY n.mtime DESC
            LIMIT ?
            """
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
            bind(statement, 1, "%\(text)%")
            bind(statement, 2, "%\(text)%")
            bind(statement, 3, excludingPath)
            sqlite3_bind_int64(statement, 4, Int64(limit))
            var paths: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                paths.append(columnString(statement, 0))
            }
            return paths
        }
    }

    // MARK: - Binding helpers

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, value, -1, Self.SQLITE_TRANSIENT)
    }

    private func columnString(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: cString)
    }

    static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

extension String {
    var containsCJK: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3040...0x30FF).contains(scalar.value)
                || (0xAC00...0xD7AF).contains(scalar.value)
        }
    }
}
