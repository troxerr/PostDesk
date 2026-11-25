import Foundation

/// Sends one HTTP request. The app uses URLSession; tests use a fake.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

public enum ClaudeError: LocalizedError, Equatable {
    case missingKey
    case http(Int, String)
    case noText

    public var errorDescription: String? {
        switch self {
        case .missingKey: "Add your Anthropic API key in Settings > Keys."
        case .http(401, _): "Claude didn't accept the API key. Check it in Settings > Keys."
        case .http(let status, let message): "Claude returned an error (\(status)): \(message)"
        case .noText: "Claude's answer had no text in it."
        }
    }
}

/// The Claude Messages API over plain HTTP, asking for JSON that matches a schema.
public struct ClaudeClient: Sendable {
    public static let defaultModel = "claude-opus-5-5"
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    public var apiKey: String
    public var model: String
    public var transport: any HTTPTransport

    public init(apiKey: String, model: String = ClaudeClient.defaultModel,
                transport: any HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.model = model.isEmpty ? Self.defaultModel : model
        self.transport = transport
    }

    /// Returns the JSON text of the answer, or nil when every model declined.
    public func structured(system: String, user: String, schema: String,
                           effort: String = "low", maxTokens: Int = 8000) async throws -> Data? {
        guard !apiKey.isEmpty else { throw ClaudeError.missingKey }
        let request = try makeRequest(system: system, user: user, schema: schema, effort: effort, maxTokens: maxTokens)
        let (data, response) = try await transport.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.message
                ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw ClaudeError.http(status, message)
        }
        let message = try JSONDecoder().decode(MessageBody.self, from: data)
        if message.stopReason == "refusal" { return nil }
        guard let text = message.content.first(where: { $0.type == "text" })?.text else { throw ClaudeError.noText }
        return Data(text.utf8)
    }

    func makeRequest(system: String, user: String, schema: String, effort: String, maxTokens: Int) throws -> URLRequest {
        let schemaObject = try JSONSerialization.jsonObject(with: Data(schema.utf8))
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": user]],
            "output_config": ["effort": effort, "format": ["type": "json_schema", "schema": schemaObject]],
            // If a model declines, the API tries another model in the same call.
            "fallbacks": "default",
        ]
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    struct MessageBody: Decodable {
        struct Block: Decodable {
            var type: String
            var text: String?
        }
        var content: [Block]
        var stopReason: String?

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }
    }

    struct ErrorBody: Decodable {
        struct Detail: Decodable { var message: String }
        var error: Detail
    }
}
