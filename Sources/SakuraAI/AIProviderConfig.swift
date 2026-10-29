import Foundation

/// Configuration for one OpenAI-compatible provider endpoint.
public struct AIProviderConfig: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// Base URL including version path, e.g. https://api.openai.com/v1
    public var baseURL: String
    public var model: String
    public var temperature: Double
    public var maxTokens: Int?
    public var requestTimeout: TimeInterval

    public init(
        id: String = UUID().uuidString,
        name: String = "OpenAI",
        baseURL: String = "https://api.openai.com/v1",
        model: String = "gpt-4o-mini",
        temperature: Double = 0.7,
        maxTokens: Int? = nil,
        requestTimeout: TimeInterval = 60
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.requestTimeout = requestTimeout
    }

    public var chatCompletionsURL: URL? {
        URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).appending("/chat/completions"))
    }

    public var modelsURL: URL? {
        URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).appending("/models"))
    }
}

public enum AIError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidConfiguration(String)
    case invalidAPIKey
    case rateLimited(retryAfterSeconds: Int?)
    case serverError(status: Int, message: String)
    case network(String)
    case invalidResponse(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key configured. Add one in Settings → AI Assistant."
        case .invalidConfiguration(let detail):
            return "The AI provider configuration is invalid: \(detail)"
        case .invalidAPIKey:
            return "The provider rejected the API key (401). Check it in Settings → AI Assistant."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "The provider rate limit was hit. Try again in \(retryAfter)s."
            }
            return "The provider rate limit was hit. Try again shortly."
        case .serverError(let status, let message):
            return "The AI provider returned an error (HTTP \(status)): \(message)"
        case .network(let detail):
            return "Network error: \(detail)"
        case .invalidResponse(let detail):
            return "The AI provider returned a malformed response: \(detail)"
        case .cancelled:
            return "The AI request was cancelled."
        }
    }
}

/// A note provided as grounding context for an AI request.
public struct AIContextNote: Equatable {
    public let title: String
    public let path: String
    public let content: String

    public init(title: String, path: String, content: String) {
        self.title = title
        self.path = path
        self.content = content
    }
}

/// One message in a chat request.
public struct AIMessage: Equatable {
    public enum Role: String {
        case system
        case user
        case assistant
    }
    public let role: Role
    public let content: String

    public init(_ role: Role, _ content: String) {
        self.role = role
        self.content = content
    }
}

/// Non-streaming chat completion result.
public struct AICompletion {
    public let text: String
    public let model: String
    public let promptTokens: Int?
    public let completionTokens: Int?
}
