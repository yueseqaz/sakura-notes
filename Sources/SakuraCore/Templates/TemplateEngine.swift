import Foundation

/// Expands template variables in note templates.
///
/// Supported variables:
/// - `{{title}}` — the new note's title
/// - `{{date}}`, `{{time}}`, `{{weekday}}` — localized creation date parts
/// - `{{year}}`, `{{month}}`, `{{day}}` — numeric date parts
/// - `{{date:FORMAT}}` — custom DateFormatter pattern, e.g. `{{date:yyyy-MM-dd}}`
public struct TemplateEngine {

    public let title: String
    public let date: Date
    public let locale: Locale
    public let timeZone: TimeZone

    public init(title: String, date: Date = Date(), locale: Locale = .current, timeZone: TimeZone = .current) {
        self.title = title
        self.date = date
        self.locale = locale
        self.timeZone = timeZone
    }

    public func expand(_ template: String) -> String {
        guard template.contains("{{") else { return template }
        let calendar = Calendar.current
        var out = template
        out = out.replacingOccurrences(of: "{{title}}", with: title)
        out = out.replacingOccurrences(of: "{{year}}", with: String(calendar.component(.year, from: date)))
        out = out.replacingOccurrences(of: "{{month}}", with: String(calendar.component(.month, from: date)))
        out = out.replacingOccurrences(of: "{{day}}", with: String(calendar.component(.day, from: date)))
        out = out.replacingOccurrences(of: "{{date}}", with: formatted("yyyy-MM-dd"))
        out = out.replacingOccurrences(of: "{{time}}", with: formatted("HH:mm"))
        let weekday = calendar.component(.weekday, from: date)
        let weekdayName = calendar.weekdaySymbols[weekday - 1]
        out = out.replacingOccurrences(of: "{{weekday}}", with: weekdayName)
        // Custom formats: {{date:...}}
        if let regex = try? NSRegularExpression(pattern: #"\{\{date:([^}]+)\}\}"#) {
            let ns = out as NSString
            let matches = regex.matches(in: out, range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() {
                let format = ns.substring(with: match.range(at: 1))
                let replacement = formatted(format)
                out = (out as NSString).replacingCharacters(in: match.range, with: replacement)
            }
        }
        return out
    }

    private func formatted(_ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
