import Foundation

/// Parsed representation of a search query supporting operators:
///
///     apple banana            — all terms (AND)
///     "exact phrase"          — quoted phrase
///     -word                   — exclusion
///     tag:project             — note tagged with `project` (front matter or inline)
///     path:journal/2026       — path contains substring
///     ext:md                  — file extension
///     title:invoice           — title contains substring
///     before:2026-01-01       — modified before date
///     after:2025-12-31        — modified after date
public struct SearchQuery: Equatable {
    public var terms: [String] = []
    public var phrases: [String] = []
    public var excludedTerms: [String] = []
    public var requiredTags: [String] = []
    public var pathFilters: [String] = []
    public var extensions: [String] = []
    public var titleFilters: [String] = []
    public var modifiedBefore: Date? = nil
    public var modifiedAfter: Date? = nil

    public var isEmpty: Bool {
        terms.isEmpty && phrases.isEmpty && excludedTerms.isEmpty && requiredTags.isEmpty
            && pathFilters.isEmpty && extensions.isEmpty && titleFilters.isEmpty
            && modifiedBefore == nil && modifiedAfter == nil
    }

    /// Plain terms + phrases, suitable for an FTS match prefix.
    public var ftsTerms: [String] { terms + phrases }

    public init() {}

    /// Parses a raw query string.
    public static func parse(_ raw: String) -> SearchQuery {
        var query = SearchQuery()
        let scanner = raw
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        for ch in scanner {
            if ch == "\"" { inQuotes.toggle(); current.append(ch); continue }
            if ch.isWhitespace && !inQuotes {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current

        for var token in tokens {
            if token.count > 1 && token.hasPrefix("-") {
                query.excludedTerms.append(String(token.dropFirst()).lowercased())
                continue
            }
            let lower = token.lowercased()
            if lower.hasPrefix("tag:") {
                let value = String(token.dropFirst(4)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if !value.isEmpty { query.requiredTags.append(value.lowercased()) }
            } else if lower.hasPrefix("path:") {
                let value = String(token.dropFirst(5)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if !value.isEmpty { query.pathFilters.append(value) }
            } else if lower.hasPrefix("ext:") {
                var value = String(token.dropFirst(4)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if value.hasPrefix(".") { value = String(value.dropFirst()) }
                if !value.isEmpty { query.extensions.append(value.lowercased()) }
            } else if lower.hasPrefix("title:") {
                let value = String(token.dropFirst(6)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if !value.isEmpty { query.titleFilters.append(value.lowercased()) }
            } else if lower.hasPrefix("before:") {
                let value = String(token.dropFirst(7))
                // Inclusive of the whole given day.
                if let date = dateFormatter.date(from: value) {
                    query.modifiedBefore = date.addingTimeInterval(86_400)
                }
            } else if lower.hasPrefix("after:") {
                let value = String(token.dropFirst(6))
                if let date = dateFormatter.date(from: value) {
                    // "after:" is inclusive of the whole given day.
                    query.modifiedAfter = date.addingTimeInterval(86_400)
                }
            } else if token.hasPrefix("\"") && token.hasSuffix("\"") && token.count >= 2 {
                let phrase = String(token.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if !phrase.isEmpty { query.phrases.append(phrase) }
            } else {
                query.terms.append(token)
            }
        }
        return query
    }
}
