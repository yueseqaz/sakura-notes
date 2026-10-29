import Foundation

/// Line-based diff used for AI edit review, version history, and conflict views.
public enum LineDiff {

    public enum Operation: Equatable {
        /// Unchanged run of lines. `lines` are the shared lines.
        case equal([String])
        /// Lines removed from the source at `line` (0-based, source coordinates).
        case delete(lines: [String], at: Int)
        /// Lines inserted at `line` (0-based, destination coordinates).
        case insert(lines: [String], at: Int)
    }

    public struct Result: Equatable {
        public let operations: [Operation]
        public let addedCount: Int
        public let removedCount: Int
    }

    /// Computes a line diff between two texts. Both texts are split on "\n"
    /// (trailing newline produces no phantom empty line).
    public static func diff(_ source: String, _ destination: String) -> Result {
        let a = splitLines(source)
        let b = splitLines(destination)
        let ops = lcsDiff(a, b)
        var added = 0
        var removed = 0
        for op in ops {
            switch op {
            case .insert(let lines, _): added += lines.count
            case .delete(let lines, _): removed += lines.count
            case .equal: break
            }
        }
        return Result(operations: ops, addedCount: added, removedCount: removed)
    }

    static func splitLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    /// Classic LCS table diff. Guards performance: above the line budget the
    /// result degrades to a whole-document replace rather than hanging.
    static func lcsDiff(_ a: [String], _ b: [String]) -> [Operation] {
        let budget = 8000
        guard a.count <= budget && b.count <= budget else {
            return [.delete(lines: a, at: 0), .insert(lines: b, at: 0)]
        }
        let n = a.count, m = b.count
        // LCS lengths table.
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                if a[i] == b[j] {
                    lcs[i][j] = lcs[i + 1][j + 1] + 1
                } else {
                    lcs[i][j] = max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }
        var ops: [Operation] = []
        var i = 0, j = 0
        var equalRun: [String] = []
        func flushEqual() {
            if !equalRun.isEmpty { ops.append(.equal(equalRun)); equalRun = [] }
        }
        while i < n && j < m {
            if a[i] == b[j] {
                equalRun.append(a[i]); i += 1; j += 1
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                flushEqual()
                var deleted = [a[i]]; i += 1
                while i < n && j < m && a[i] != b[j] && lcs[i + 1][j] >= lcs[i][j + 1] {
                    deleted.append(a[i]); i += 1
                }
                ops.append(.delete(lines: deleted, at: i - deleted.count))
            } else {
                flushEqual()
                var inserted = [b[j]]; j += 1
                while j < m && (i >= n || a[i] != b[j]) && lcs[i][j + 1] > lcs[i + 1][j] {
                    inserted.append(b[j]); j += 1
                }
                ops.append(.insert(lines: inserted, at: j - inserted.count))
            }
        }
        flushEqual()
        if i < n { ops.append(.delete(lines: Array(a[i...]), at: i)) }
        if j < m { ops.append(.insert(lines: Array(b[j...]), at: j)) }
        return ops
    }

    /// Applies an insert/delete plan produced by `diff` to the source,
    /// returning the destination text. Used to verify generated edits before
    /// they are presented to the user.
    public static func apply(operations: [Operation], to source: String) -> String {
        var lines = splitLines(source)
        // Collect index-based edits then apply bottom-up to keep indices stable.
        var edits: [(index: Int, removeCount: Int, newLines: [String])] = []
        var sourceIndex = 0
        for op in operations {
            switch op {
            case .equal(let shared):
                sourceIndex += shared.count
            case .delete(let deleted, _):
                edits.append((sourceIndex, deleted.count, []))
                sourceIndex += deleted.count
            case .insert(let inserted, _):
                edits.append((sourceIndex, 0, inserted))
            }
        }
        for edit in edits.sorted(by: { $0.index > $1.index }) {
            let end = min(edit.index + edit.removeCount, lines.count)
            lines.replaceSubrange(edit.index..<end, with: edit.newLines)
        }
        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }
}
