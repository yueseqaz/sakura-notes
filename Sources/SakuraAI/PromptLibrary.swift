import Foundation

/// Built-in AI actions for the current note.
public enum AIAction: String, CaseIterable, Identifiable {
    case summarize
    case proofread
    case expand
    case shorten
    case translate
    case formalTone
    case casualTone
    case generateTitle
    case generateOutline
    case generateKeywords
    case generateTableOfContents
    case makeTable
    case makeChecklist
    case explainSelection
    case generateFlashcards
    case generateQuestions

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .summarize: return "Summarize"
        case .proofread: return "Proofread"
        case .expand: return "Expand"
        case .shorten: return "Shorten"
        case .translate: return "Translate…"
        case .formalTone: return "Make Formal"
        case .casualTone: return "Make Casual"
        case .generateTitle: return "Suggest Title"
        case .generateOutline: return "Generate Outline"
        case .generateKeywords: return "Extract Keywords"
        case .generateTableOfContents: return "Generate Table of Contents"
        case .makeTable: return "Convert to Table"
        case .makeChecklist: return "Convert to Checklist"
        case .explainSelection: return "Explain Selection"
        case .generateFlashcards: return "Generate Flashcards"
        case .generateQuestions: return "Generate Questions"
        }
    }

    public var symbolName: String {
        switch self {
        case .summarize: return "text.alignleft"
        case .proofread: return "checkmark.circle"
        case .expand: return "arrow.up.left.and.arrow.down.right"
        case .shorten: return "arrow.down.right.and.arrow.up.left"
        case .translate: return "globe"
        case .formalTone: return "person.crop.square.badge.clock"
        case .casualTone: return "person.crop.circle.badge.questionmark"
        case .generateTitle: return "textformat"
        case .generateOutline: return "list.bullet.indent"
        case .generateKeywords: return "number"
        case .generateTableOfContents: return "list.number"
        case .makeTable: return "tablecells"
        case .makeChecklist: return "checklist"
        case .explainSelection: return "questionmark.bubble"
        case .generateFlashcards: return "rectangle.on.rectangle"
        case .generateQuestions: return "bubble.left.and.bubble.right"
        }
    }

    /// Whether the action operates on a text selection (vs. the whole note).
    public var requiresSelection: Bool {
        switch self {
        case .explainSelection, .proofread, .expand, .shorten, .translate, .formalTone, .casualTone, .makeTable, .makeChecklist:
            return true
        default:
            return false
        }
    }

    /// How the result should be applied when the user accepts it.
    public enum ResultMode {
        /// Replace the text the action was invoked on.
        case replaceSelection
        /// Insert at the end of the note (append a section).
        case appendToNote
        /// Display only.
        case displayOnly
    }

    public var resultMode: ResultMode {
        switch self {
        case .summarize, .proofread, .expand, .shorten, .translate, .formalTone, .casualTone, .makeTable, .makeChecklist:
            return .replaceSelection
        case .generateTitle, .generateKeywords:
            return .displayOnly
        case .generateOutline, .generateTableOfContents, .generateFlashcards, .generateQuestions:
            return .appendToNote
        case .explainSelection:
            return .displayOnly
        }
    }

    /// Builds the system and user prompts.
    /// - Parameters:
    ///   - selection: selected text (may be empty for whole-note actions)
    ///   - noteTitle: the note's title
    ///   - noteContent: full note content (whole-note actions use this)
    ///   - language: target language for translation, e.g. "Japanese"
    public func prompts(
        selection: String,
        noteTitle: String,
        noteContent: String,
        language: String = "English"
    ) -> (system: String, user: String) {
        let system = """
        You are a precise writing assistant embedded in a Markdown note-taking app.
        Rules:
        - Respond in Markdown.
        - Preserve the meaning and any factual content of the source text.
        - Do not add commentary about yourself; output only the requested result.
        - When asked to output structured content, output only that content.
        """
        switch self {
        case .summarize:
            return (system, "Summarize the following note as a short Markdown section titled '## Summary':\n\n\(noteContent)")
        case .proofread:
            return (system, "Fix grammar, spelling, and punctuation in the following text. Keep the original language, tone, and Markdown formatting. Return only the corrected text:\n\n\(selection)")
        case .expand:
            return (system, "Expand the following text with more detail and clarity, keeping its voice. Return only the expanded text:\n\n\(selection)")
        case .shorten:
            return (system, "Shorten the following text while keeping every key point. Return only the shortened text:\n\n\(selection)")
        case .translate:
            return (system, "Translate the following text into \(language). Keep Markdown formatting. Return only the translation:\n\n\(selection)")
        case .formalTone:
            return (system, "Rewrite the following text in a formal, professional tone. Return only the rewritten text:\n\n\(selection)")
        case .casualTone:
            return (system, "Rewrite the following text in a friendly, casual tone. Return only the rewritten text:\n\n\(selection)")
        case .generateTitle:
            return (system, system + "\n- Output only the title text, no quotes, no punctuation at the end.")
        case .generateOutline:
            return (system, "Create a hierarchical Markdown outline (##, ###, bullet points) for the following note:\n\n\(noteContent)")
        case .generateKeywords:
            return (system, "Extract 5-10 keywords or tags from the following note. Return them as a comma-separated list, one line, no hashtag characters:\n\n\(noteContent)")
        case .generateTableOfContents:
            return (system, "Generate a Markdown table of contents as a nested bullet list with links of the form `[Section](#section)` for the following note:\n\n\(noteContent)")
        case .makeTable:
            return (system, "Convert the following text into a Markdown table where the columns make sense for the content. Return only the table:\n\n\(selection)")
        case .makeChecklist:
            return (system, "Convert the following text into a Markdown task list using `- [ ]` items. Return only the task list:\n\n\(selection)")
        case .explainSelection:
            return (system, system + "\n- If the text contains code, explain what it does step by step. If it contains an error message, explain the likely cause and fixes. Otherwise explain the concept clearly.")
        case .generateFlashcards:
            return (system, "Generate flashcards from the following note in Markdown format. Use `- Q: … / A: …` list items:\n\n\(noteContent)")
        case .generateQuestions:
            return (system, "Generate 5 thoughtful study questions the following note answers, as a Markdown numbered list:\n\n\(noteContent)")
        }
    }
}
