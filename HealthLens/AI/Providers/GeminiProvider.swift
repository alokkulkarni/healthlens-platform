import Foundation
import OSLog

struct GeminiProvider: AIProvider {
    let providerType: AIProviderType = .gemini
    private let keyStore: APIKeyStore
    private let session: URLSession

    let availableModels: [AIModelDescriptor] = [
        // Gemini 2.5 stable models (recommended)
        AIModelDescriptor(
            id: "gemini-2.5-flash",
            displayName: "Gemini 2.5 Flash",
            contextWindow: 1_048_576,
            supportsStreaming: true,
            isOnDevice: false,
            providerType: .gemini
        ),
        AIModelDescriptor(
            id: "gemini-2.5-pro",
            displayName: "Gemini 2.5 Pro",
            contextWindow: 1_048_576,
            supportsStreaming: true,
            isOnDevice: false,
            providerType: .gemini
        ),
        // Gemini 3 preview models
        AIModelDescriptor(
            id: "gemini-3.1-pro-preview",
            displayName: "Gemini 3.1 Pro (Preview)",
            contextWindow: 1_048_576,
            supportsStreaming: true,
            isOnDevice: false,
            providerType: .gemini
        ),
        AIModelDescriptor(
            id: "gemini-3-flash-preview",
            displayName: "Gemini 3 Flash (Preview)",
            contextWindow: 1_048_576,
            supportsStreaming: true,
            isOnDevice: false,
            providerType: .gemini
        ),
        AIModelDescriptor(
            id: "gemini-3.1-flash-lite-preview",
            displayName: "Gemini 3.1 Flash Lite (Preview)",
            contextWindow: 1_048_576,
            supportsStreaming: true,
            isOnDevice: false,
            providerType: .gemini
        ),
    ]

    init(keyStore: APIKeyStore, session: URLSession = .shared) {
        self.keyStore = keyStore
        self.session = session
    }

    // MARK: - Complete

    func complete(_ request: AIRequest) async throws -> AIResponse {
        let apiKey = try getAPIKey()
        let url = try buildURL(modelID: request.modelID, streaming: false)
        let urlRequest = try buildRequest(request: request, url: url, apiKey: apiKey)
        let start = Date()
        let (data, response) = try await session.data(for: urlRequest)
        let latency = Date().timeIntervalSince(start) * 1000
        try validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let text = decoded.candidates?.first?.content?.parts?.first?.text ?? ""
        let inputTokens = decoded.usageMetadata?.promptTokenCount ?? 0
        let outputTokens = decoded.usageMetadata?.candidatesTokenCount ?? 0

        return AIResponse(
            text: text,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            modelID: request.modelID,
            finishReason: decoded.candidates?.first?.finishReason ?? "STOP",
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
                    // ?alt=sse forces SSE format: one "data: <json>" line per chunk
                    let url = try buildURL(modelID: request.modelID, streaming: true)
                    let urlRequest = try buildRequest(request: request, url: url, apiKey: apiKey)
                    let (bytes, response) = try await session.bytes(for: urlRequest)

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

                    // SSE format: each line is "data: <json>" or blank
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        guard jsonString != "[DONE]",
                              let data = jsonString.data(using: .utf8),
                              let text = StreamingDecoder.extractGeminiText(from: data),
                              !text.isEmpty
                        else { continue }
                        continuation.yield(text)
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
            return try keyStore.retrieveGeminiKey()
        } catch {
            throw AIError.missingAPIKey(.gemini)
        }
    }

    private func buildURL(modelID: String, streaming: Bool) throws -> URL {
        let action = streaming ? "streamGenerateContent" : "generateContent"
        // alt=sse → server-sent events format: one "data: <json>" line per chunk (reliable parsing)
        let suffix = streaming ? "?alt=sse" : ""
        let urlString = "\(Constants.API.geminiBaseURL)/\(modelID):\(action)\(suffix)"
        guard let url = URL(string: urlString) else {
            throw AIError.invalidResponse("Could not build Gemini URL")
        }
        return url
    }

    private func buildRequest(request: AIRequest, url: URL, apiKey: String) throws -> URLRequest {
        let body = GeminiRequest(
            systemInstruction: GeminiContent(
                parts: [GeminiPart(text: request.systemPrompt)]
            ),
            contents: [
                GeminiContent(
                    role: "user",
                    parts: [GeminiPart(text: request.userMessage)]
                )
            ],
            generationConfig: GeminiGenerationConfig(
                maxOutputTokens: request.maxTokens,
                temperature: request.temperature
            )
        )
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.timeoutInterval = 120
        urlRequest.httpBody = try JSONEncoder().encode(body)
        return urlRequest
    }

}

// MARK: - Codable types

private struct GeminiRequest: Encodable {
    let systemInstruction: GeminiContent?
    let contents: [GeminiContent]
    let generationConfig: GeminiGenerationConfig?

    enum CodingKeys: String, CodingKey {
        case systemInstruction = "system_instruction"
        case contents
        case generationConfig = "generation_config"
    }
}

private struct GeminiContent: Encodable {
    var role: String?
    let parts: [GeminiPart]

    // Omit the `role` key entirely when nil (rather than encoding "role": null)
    // so the system_instruction object passes Gemini API validation.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encode(parts, forKey: .parts)
    }

    private enum CodingKeys: String, CodingKey { case role, parts }
}

private struct GeminiPart: Encodable {
    let text: String
}

private struct GeminiGenerationConfig: Encodable {
    let maxOutputTokens: Int
    let temperature: Double

    enum CodingKeys: String, CodingKey {
        case maxOutputTokens = "maxOutputTokens"
        case temperature
    }
}

private struct GeminiResponse: Decodable {
    let candidates: [Candidate]?
    let usageMetadata: UsageMetadata?

    struct Candidate: Decodable {
        let content: Content?
        let finishReason: String?

        struct Content: Decodable {
            let parts: [Part]?

            struct Part: Decodable {
                let text: String?
            }
        }
    }

    struct UsageMetadata: Decodable {
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?
    }
}
