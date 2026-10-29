import Foundation

/// A parsed YAML front matter block. Only a pragmatic subset of YAML is
/// understood (scalar keys, scalar values, and simple lists). Unknown keys are
/// preserved verbatim so round-tripping never destroys content the app does
/// not model.
public struct FrontMatter: Equatable {
    /// Ordered key/value pairs. List values are stored as `FrontMatter.Value.list`.
    public var entries: [(key: String, value: Value)]

    public enum Value: Equatable {
        case scalar(String)
        case list([String])
    }

    public init(entries: [(key: String, value: Value)] = []) {
        self.entries = entries
    }

    public static func == (lhs: FrontMatter, rhs: FrontMatter) -> Bool {
        guard lhs.entries.count == rhs.entries.count else { return false }
        for (l, r) in zip(lhs.entries, rhs.entries) {
            if l.key != r.key || l.value != r.value { return false }
        }
        return true
    }

    // MARK: - Convenience accessors

    public subscript(key: String) -> Value? {
        get { entries.first(where: { $0.key.lowercased() == key.lowercased() })?.value }
        set {
            guard let newValue else {
                entries.removeAll { $0.key.lowercased() == key.lowercased() }
                return
            }
            if let index = entries.firstIndex(where: { $0.key.lowercased() == key.lowercased() }) {
                entries[index].value = newValue
            } else {
                entries.append((key, newValue))
            }
        }
    }

    public var title: String? {
        if case .scalar(let s)? = self["title"] { return s }
        return nil
    }

    public var tags: [String] {
        switch self["tags"] {
        case .scalar(let s)?: return splitTags(s)
        case .list(let items)?: return items.flatMap { splitTags($0) }
        default: return []
        }
    }

    private func splitTags(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Parsing

    public static func extract(from text: String) -> (matter: FrontMatter, bodyRange: Range<String.Index>?) {
        guard text.hasPrefix("---") else { return (FrontMatter(), nil) }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // Handle the case where the file starts with "---\r\n".
        lines = lines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        guard lines.count >= 2, lines[0].trimmingCharacters(in: .whitespaces) == "---" else {
            return (FrontMatter(), nil)
        }
        var endLine: Int? = nil
        for i in 1..<lines.count where lines[i].trimmingCharacters(in: .whitespaces) == "---" {
            endLine = i
            break
        }
        guard let end = endLine else { return (FrontMatter(), nil) }
        var entries: [(String, Value)] = []
        var currentKey: String? = nil
        var currentList: [String]? = nil

        func flush() {
            if let key = currentKey {
                if let list = currentList {
                    entries.append((key, .list(list)))
                } else {
                    entries.append((key, .scalar("")))
                }
            }
            currentKey = nil
            currentList = nil
        }

        for line in lines[1..<end] {
            if line.hasPrefix("- ") || line == "-" {
                let item = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if currentList == nil { currentList = [] }
                currentList?.append(item)
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            flush()
            if rawValue.isEmpty {
                currentKey = key
            } else {
                // Flow-style list: tags: [a, b]
                let trimmedValue = rawValue.trimmingCharacters(in: .whitespaces)
                if trimmedValue.hasPrefix("[") && trimmedValue.hasSuffix("]") {
                    let inner = String(trimmedValue.dropFirst().dropLast())
                    let items = inner.split(separator: ",").map {
                        $0.trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    }
                    .filter { !$0.isEmpty }
                    entries.append((key, .list(items)))
                } else {
                    let value = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    entries.append((key, .scalar(value)))
                }
            }
        }
        flush()

        // Locate the end of the closing delimiter line in the original text.
        let bodyStart = end + 1
        if bodyStart < lines.count {
            var index = text.startIndex
            var newlines = 0
            for ch in text {
                if ch == "\n" {
                    newlines += 1
                    if newlines == bodyStart {
                        index = text.index(after: index)
                        return (FrontMatter(entries: entries), index..<text.endIndex)
                    }
                }
                index = text.index(after: index)
            }
        }
        return (FrontMatter(entries: entries), nil)
    }

    // MARK: - Serialization

    /// Serializes front matter with the closing delimiter and a blank line.
    public func serialized() -> String {
        guard !entries.isEmpty else { return "" }
        var out = "---\n"
        for (key, value) in entries {
            switch value {
            case .scalar(let s):
                if needsQuoting(s) {
                    out += "\(key): \"\(s.replacingOccurrences(of: "\"", with: "\\\""))\"\n"
                } else {
                    out += "\(key): \(s)\n"
                }
            case .list(let items):
                out += "\(key):\n"
                for item in items {
                    if needsQuoting(item) {
                        out += "  - \"\(item.replacingOccurrences(of: "\"", with: "\\\""))\"\n"
                    } else {
                        out += "  - \(item)\n"
                    }
                }
            }
        }
        out += "---\n\n"
        return out
    }

    private func needsQuoting(_ s: String) -> Bool {
        if s.isEmpty { return true }
        let special = CharacterSet(charactersIn: ":#[]{}|>&*!%@`\"'-,?{}")
        return s.rangeOfCharacter(from: special) != nil
            || s.trimmingCharacters(in: .whitespaces) != s
    }
}
