import Foundation

/// Client for OpenAI-compatible chat completion APIs, with streaming support.
///
/// Only talks to the user-configured endpoint with the user's own API key.
/// Note content is sent only for explicit requests.
public final class OpenAIClient {

    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 600
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Non-streaming completion

    public func complete(
        messages: [AIMessage],
        config: AIProviderConfig,
        apiKey: String
    ) async throws -> AICompletion {
        guard let url = config.chatCompletionsURL else {
            throw AIError.invalidConfiguration("endpoint URL is malformed")
        }
        var request = URLRequest(url: url, timeoutInterval: config.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": config.model,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "temperature": config.temperature,
        ]
        if let maxTokens = config.maxTokens {
            body["max_tokens"] = maxTokens
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw AIError.cancelled
        } catch let error as URLError {
            if error.code == .cancelled { throw AIError.cancelled }
            throw AIError.network(error.localizedDescription)
        }
        try Self.validate(response: response, data: data)
        return try Self.parseCompletion(data: data, fallbackModel: config.model)
    }

    // MARK: - Streaming completion

    /// Streams assistant deltas as they arrive. Terminates with the full text
    /// as the final value.
    public func stream(
        messages: [AIMessage],
        config: AIProviderConfig,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = config.chatCompletionsURL else {
                        throw AIError.invalidConfiguration("endpoint URL is malformed")
                    }
                    var request = URLRequest(url: url, timeoutInterval: config.requestTimeout)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    var body: [String: Any] = [
                        "model": config.model,
                        "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
                        "temperature": config.temperature,
                        "stream": true,
                    ]
                    if let maxTokens = config.maxTokens {
                        body["max_tokens"] = maxTokens
                    }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await session.bytes(for: request)
                    try Self.validate(response: response, data: Data())

                    var full = ""
                    for try await line in bytes.lines {
                        if Task.isCancelled { throw AIError.cancelled }
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let jsonData = payload.data(using: .utf8) else { continue }
                        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { continue }
                        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                            throw AIError.serverError(status: 200, message: message)
                        }
                        guard let choices = json["choices"] as? [[String: Any]] else { continue }
                        if let delta = choices.first?["delta"] as? [String: Any],
                           let content = delta["content"] as? String, !content.isEmpty {
                            full += content
                            continuation.yield(content)
                        }
                    }
                    _ = full
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: AIError.cancelled)
                } catch let error as URLError {
                    if error.code == .cancelled {
                        continuation.finish(throwing: AIError.cancelled)
                    } else {
                        continuation.finish(throwing: AIError.network(error.localizedDescription))
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Models list

    public func listModels(config: AIProviderConfig, apiKey: String) async throws -> [String] {
        guard let url = config.modelsURL else {
            throw AIError.invalidConfiguration("endpoint URL is malformed")
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw AIError.cancelled
        } catch let error as URLError {
            throw AIError.network(error.localizedDescription)
        }
        try Self.validate(response: response, data: data)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else {
            throw AIError.invalidResponse("models payload")
        }
        let ids = list.compactMap { $0["id"] as? String }.sorted()
        return ids
    }

    // MARK: - Response validation & parsing

    static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AIError.invalidResponse("not an HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(2000), encoding: .utf8) ?? ""
            var message = body
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let errorMessage = error["message"] as? String {
                message = errorMessage
            }
            switch http.statusCode {
            case 401, 403:
                throw AIError.invalidAPIKey
            case 429:
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) }
                throw AIError.rateLimited(retryAfterSeconds: retryAfter)
            default:
                throw AIError.serverError(status: http.statusCode, message: message)
            }
        }
    }

    static func parseCompletion(data: Data, fallbackModel: String) throws -> AICompletion {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.invalidResponse("top-level JSON")
        }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            throw AIError.serverError(status: 200, message: message)
        }
        guard let choices = json["choices"] as? [[String: Any]], let first = choices.first else {
            throw AIError.invalidResponse("no choices")
        }
        let message = first["message"] as? [String: Any]
        let content = message?["content"] as? String
            ?? first["text"] as? String
            ?? ""
        let usage = json["usage"] as? [String: Any]
        return AICompletion(
            text: content,
            model: (json["model"] as? String) ?? fallbackModel,
            promptTokens: usage?["prompt_tokens"] as? Int,
            completionTokens: usage?["completion_tokens"] as? Int
        )
    }
}
