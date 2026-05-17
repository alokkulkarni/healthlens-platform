import Foundation
import OSLog

struct ClaudeProvider: AIProvider {
    let providerType: AIProviderType = .claude
    private let keyStore: APIKeyStore
    private let session: URLSession

    private static let endpoint = URL(string: Constants.API.claudeBaseURL)!

    let availableModels: [AIModelDescriptor] = [
        AIModelDescriptor(
            id: "claude-opus-4-6",
            displayName: "Claude Opus 4.6",
            contextWindow: 1_048_576,
            supportsStreaming: true,
            isOnDevice: false,
            providerType: .claude
        ),
        AIModelDescriptor(
            id: "claude-sonnet-4-6",
            displayName: "Claude Sonnet 4.6",
            contextWindow: 1_048_576,
            supportsStreaming: true,
            isOnDevice: false,
            providerType: .claude
        ),
        AIModelDescriptor(
            id: "claude-haiku-4-5-20251001",
            displayName: "Claude Haiku 4.5",
            contextWindow: 200_000,
            supportsStreaming: true,
            isOnDevice: false,
            providerType: .claude
        ),
    ]

    init(keyStore: APIKeyStore, session: URLSession = .shared) {
        self.keyStore = keyStore
        self.session = session
    }

    // MARK: - Complete (non-streaming)

    func complete(_ request: AIRequest) async throws -> AIResponse {
        let apiKey = try getAPIKey()
        let urlRequest = try buildRequest(request: request, apiKey: apiKey, streaming: false)
        let start = Date()
        let (data, response) = try await session.data(for: urlRequest)
        let latency = Date().timeIntervalSince(start) * 1000
        try validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(ClaudeResponseBody.self, from: data)
        return AIResponse(
            text: decoded.content.first?.text ?? "",
            inputTokens: decoded.usage.inputTokens,
            outputTokens: decoded.usage.outputTokens,
            modelID: decoded.model,
            finishReason: decoded.stopReason ?? "end_turn",
            latencyMS: latency,
            rawJSON: data
        )
    }

    // MARK: - Stream

    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let apiKey = try getAPIKey()
                    let urlRequest = try buildRequest(request: request, apiKey: apiKey, streaming: true)
                    let (bytes, response) = try await session.bytes(for: urlRequest)

                    // Read error body when server returns non-2xx so the user sees a helpful message.
                    if let httpResponse = response as? HTTPURLResponse,
                       !(200...299).contains(httpResponse.statusCode) {
                        var errorData = Data()
                        for try await byte in bytes {
                            errorData.append(byte)
                            if errorData.count > 4096 { break }
                        }
                        let body = String(data: errorData, encoding: .utf8) ?? ""
                        if httpResponse.statusCode == 429 {
                            continuation.finish(throwing: AIError.rateLimited)
                        } else {
                            continuation.finish(throwing: AIError.providerError(
                                statusCode: httpResponse.statusCode,
                                message: body.isEmpty ? "HTTP \(httpResponse.statusCode)" : body
                            ))
                        }
                        return
                    }

                    for try await line in bytes.lines {
                        if let text = StreamingDecoder.extractClaudeText(from: line) {
                            continuation.yield(text)
                        }
                        if line.contains("\"type\":\"message_stop\"") {
                            break
                        }
                    }
                    continuation.finish()
                } catch let error as AIError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: AIError.networkError(error))
                }
            }
        }
    }

    // MARK: - Helpers

    private func getAPIKey() throws -> String {
        do {
            return try keyStore.retrieveClaudeKey()
        } catch {
            throw AIError.missingAPIKey(.claude)
        }
    }

    private func buildRequest(
        request: AIRequest,
        apiKey: String,
        streaming: Bool
    ) throws -> URLRequest {
        let body = ClaudeRequestBody(
            model: request.modelID,
            maxTokens: request.maxTokens,
            system: request.systemPrompt,
            messages: [ClaudeMessage(role: "user", content: request.userMessage)],
            stream: streaming,
            temperature: request.temperature
        )
        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Constants.API.claudeAPIVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.timeoutInterval = 120
        urlRequest.httpBody = try JSONEncoder().encode(body)
        return urlRequest
    }
}

// MARK: - Codable types

private struct ClaudeRequestBody: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [ClaudeMessage]
    let stream: Bool
    let temperature: Double

    enum CodingKeys: String, CodingKey {
        case model, system, messages, stream, temperature
        case maxTokens = "max_tokens"
    }
}

private struct ClaudeMessage: Encodable {
    let role: String
    let content: String
}

private struct ClaudeResponseBody: Decodable {
    let id: String
    let model: String
    let content: [ContentBlock]
    let usage: UsageBlock
    let stopReason: String?

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    struct UsageBlock: Decodable {
        let inputTokens: Int
        let outputTokens: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, model, content, usage
        case stopReason = "stop_reason"
    }
}
