import Foundation

/// String helpers used across the app.
public enum StringUtilities {

    /// Returns a safe, cross-platform file name derived from a title.
    public static func sanitizedFileName(_ title: String) -> String {
        var name = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "\0", with: "")
        name = name.trimmingCharacters(in: .whitespacesAndNewlines.union(["."]))
        // Collapse runs of whitespace into single spaces.
        while name.contains("  ") { name = name.replacingOccurrences(of: "  ", with: " ") }
        if name.count > 180 {
            name = String(name.prefix(180))
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines.union(["."]))
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    /// POSIX relative path from one directory to a file, using "/" separators.
    /// Returns `nil` when no relative relationship exists (different roots).
    public static func relativePath(from directory: URL, to file: URL) -> String? {
        let dirComps = directory.standardizedFileURL.pathComponents
        let fileComps = file.standardizedFileURL.pathComponents
        guard directory.hasDirectoryPath else { return relativePath(from: directory.deletingLastPathComponent(), to: file) }
        var i = 0
        while i < dirComps.count && i < fileComps.count && dirComps[i] == fileComps[i] {
            i += 1
        }
        // A trailing "." from directory paths is not a real component.
        var dirCount = dirComps.count
        if dirComps.last == "." { dirCount -= 1 }
        guard i >= 1, i <= fileComps.count else { return nil }
        var comps: [String] = []
        for _ in i..<dirCount { comps.append("..") }
        comps.append(contentsOf: fileComps[i...])
        return comps.joined(separator: "/")
    }

    /// Counts words in a Unicode-aware way: Latin-style words separated by
    /// whitespace/punctuation, and each CJK ideograph or kana counted individually.
    public static func wordCount(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if isCJK(scalar) {
                count += 1
                inWord = false
            } else if scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
                if !inWord {
                    count += 1
                    inWord = true
                }
            } else {
                inWord = false
            }
        }
        return count
    }

    static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF,      // CJK Unified Ideographs
             0x3400...0x4DBF,      // Extension A
             0x20000...0x2A6DF,    // Extension B
             0x3040...0x30FF,      // Hiragana + Katakana
             0xAC00...0xD7AF:      // Hangul syllables
            return true
        default:
            return false
        }
    }

    /// Estimated reading time in minutes (at 200 wpm, minimum 1 for non-empty text).
    public static func readingTime(minutesForWords words: Int) -> Int {
        guard words > 0 else { return 0 }
        return max(1, Int((Double(words) / 200.0).rounded()))
    }

    /// Collapses whitespace and truncates for use as a one-line excerpt.
    public static func excerpt(_ text: String, maxLength: Int = 160) -> String {
        var result = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        while result.contains("  ") { result = result.replacingOccurrences(of: "  ", with: " ") }
        result = result.trimmingCharacters(in: .whitespaces)
        if result.count > maxLength {
            result = String(result.prefix(maxLength)) + "…"
        }
        return result
    }

    /// Escapes a string for inclusion in HTML text content.
    public static func htmlEscaped(_ text: String) -> String {
        var out = text
        out = out.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        out = out.replacingOccurrences(of: "\"", with: "&quot;")
        return out
    }

    /// Percent-encodes a path component for use in URLs while keeping slashes.
    public static func urlPathEncoded(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~/")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}
