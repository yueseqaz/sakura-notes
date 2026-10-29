import Foundation
import Combine

/// Observable state shared by AI runners, suitable for panel UIs.
public final class AIActionRunner: ObservableObject {

    public enum Phase: Equatable {
        case idle
        case streaming
        case finished
        case failed(String)
        case cancelled
    }

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var streamedText: String = ""
    @Published public private(set) var lastRequestSummary: String = ""

    private let client: OpenAIClient
    private var task: Task<Void, Never>?

    public init(client: OpenAIClient = OpenAIClient()) {
        self.client = client
    }

    public var isBusy: Bool { phase == .streaming }

    /// Runs a current-note action with streaming output.
    /// - Parameters:
    ///   - contextNotes: additional notes to ground the answer (may be empty).
    ///   - allowedContextSummary: human-readable description of what will be sent.
    public func run(
        action: AIAction,
        selection: String,
        noteTitle: String,
        noteContent: String,
        language: String,
        config: AIProviderConfig,
        apiKey: String,
        contextNotes: [AIContextNote] = []
    ) {
        cancel()
        let prompts = action.prompts(
            selection: selection,
            noteTitle: noteTitle,
            noteContent: noteContent,
            language: language
        )
        var messages: [AIMessage] = [AIMessage(.system, prompts.system)]
        if !contextNotes.isEmpty {
            let context = AIContextBuilder.renderContextNotes(contextNotes)
            messages.append(AIMessage(.system, "Reference material from the user's other notes (for context only, do not quote at length):\n\n\(context)"))
        }
        messages.append(AIMessage(.user, prompts.user))
        lastRequestSummary = Self.requestSummary(
            action: action,
            characterCount: prompts.user.count + contextNotes.reduce(0) { $0 + $1.content.count },
            noteCount: contextNotes.count
        )
        startStreaming(messages: messages, config: config, apiKey: apiKey)
    }

    /// Free-form question across the given context notes.
    public func ask(
        question: String,
        contextNotes: [AIContextNote],
        config: AIProviderConfig,
        apiKey: String
    ) {
        cancel()
        let system = """
        You answer questions using ONLY the reference material provided, unless the question is general knowledge.
        Rules:
        - When you use information from a specific note, cite it inline as [[Note Title]].
        - Clearly separate grounded statements (from the notes) from your own inference; label inference as "Inference:".
        - If the notes do not contain the answer, say so plainly.
        - Respond in Markdown.
        """
        var messages: [AIMessage] = [AIMessage(.system, system)]
        if !contextNotes.isEmpty {
            messages.append(AIMessage(.system, "Reference material:\n\n\(AIContextBuilder.renderContextNotes(contextNotes))"))
        }
        messages.append(AIMessage(.user, question))
        lastRequestSummary = Self.requestSummary(
            action: nil,
            characterCount: question.count + contextNotes.reduce(0) { $0 + $1.content.count },
            noteCount: contextNotes.count
        )
        startStreaming(messages: messages, config: config, apiKey: apiKey)
    }

    private func startStreaming(messages: [AIMessage], config: AIProviderConfig, apiKey: String) {
        DispatchQueue.main.async {
            self.phase = .streaming
            self.streamedText = ""
        }
        task = Task { [client] in
            do {
                let stream = client.stream(messages: messages, config: config, apiKey: apiKey)
                for try await delta in stream {
                    let appended = delta
                    await MainActor.run {
                        self.streamedText += appended
                    }
                }
                await MainActor.run {
                    if self.phase == .streaming { self.phase = .finished }
                }
            } catch let error as AIError {
                await MainActor.run {
                    switch error {
                    case .cancelled: self.phase = .cancelled
                    default: self.phase = .failed(error.errorDescription ?? "Unknown error")
                    }
                }
            } catch {
                await MainActor.run {
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
        if phase == .streaming {
            DispatchQueue.main.async { self.phase = .cancelled }
        }
    }

    public func reset() {
        cancel()
        DispatchQueue.main.async {
            self.phase = .idle
            self.streamedText = ""
        }
    }

    /// Short, content-free description of what a request will send. Shown to
    /// the user before the first send for transparency; contains counts only.
    static func requestSummary(action: AIAction?, characterCount: Int, noteCount: Int) -> String {
        let actionName = action?.label ?? "Workspace question"
        if noteCount > 0 {
            return "\(actionName) — \(noteCount) note(s), ~\(characterCount) characters will be sent to the provider."
        }
        return "\(actionName) — ~\(characterCount) characters will be sent to the provider."
    }
}

/// Builds bounded context payloads for AI requests.
public enum AIContextBuilder {

    /// Upper bound on characters sent as context by default (~24k chars).
    public static let defaultContextBudget = 24_000

    public static func renderContextNotes(_ notes: [AIContextNote], budget: Int = defaultContextBudget) -> String {
        var parts: [String] = []
        var used = 0
        for note in notes {
            var body = note.content
            if used + body.count > budget {
                let remaining = budget - used
                guard remaining > 200 else { break }
                body = String(body.prefix(remaining)) + "\n…(truncated)"
            }
            parts.append("### Note: \(note.title)\nPath: \(note.path)\n\n\(body)")
            used += body.count
            if used >= budget { break }
        }
        return parts.joined(separator: "\n\n---\n\n")
    }

    /// Selects notes for context: the primary note plus optional extras,
    /// capped by count and budget.
    public static func selectContext(primary: AIContextNote?, extras: [AIContextNote], maxNotes: Int = 8, budget: Int = defaultContextBudget) -> [AIContextNote] {
        var result: [AIContextNote] = []
        if let primary { result.append(primary) }
        for extra in extras where result.count < maxNotes {
            result.append(extra)
        }
        return result
    }
}
