import Foundation

/// Decodes SSE (Server-Sent Events) streams from various AI providers.
enum StreamingDecoder {

    // MARK: - Claude SSE Format
    // Lines: "data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"..."}}"

    struct ClaudeDelta: Decodable {
        let type: String
        let delta: DeltaContent?
        let usage: Usage?

        struct DeltaContent: Decodable {
            let type: String?
            let text: String?
        }

        struct Usage: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?

            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
            }
        }
    }

    static func extractClaudeText(from line: String) -> String? {
        guard line.hasPrefix("data: ") else { return nil }
        let jsonString = String(line.dropFirst(6))
        guard jsonString != "[DONE]",
              let data = jsonString.data(using: .utf8),
              let delta = try? JSONDecoder().decode(ClaudeDelta.self, from: data)
        else { return nil }

        if delta.type == "content_block_delta",
           delta.delta?.type == "text_delta",
           let text = delta.delta?.text {
            return text
        }
        return nil
    }

    // MARK: - Gemini SSE Format
    // Lines: JSON objects with candidates[0].content.parts[0].text

    struct GeminiChunk: Decodable {
        let candidates: [Candidate]?

        struct Candidate: Decodable {
            let content: Content?

            struct Content: Decodable {
                let parts: [Part]?

                struct Part: Decodable {
                    let text: String?
                }
            }
        }
    }

    static func extractGeminiText(from data: Data) -> String? {
        guard let chunk = try? JSONDecoder().decode(GeminiChunk.self, from: data) else {
            return nil
        }
        return chunk.candidates?.first?.content?.parts?.first?.text
    }

    // MARK: - Bedrock Claude format (similar to direct Claude but wrapped)

    struct BedrockDelta: Decodable {
        let type: String?
        let delta: Delta?
        let bytes: String?  // Base64 encoded chunk from Bedrock

        struct Delta: Decodable {
            let type: String?
            let text: String?
        }
    }

    static func extractBedrockText(from data: Data) -> String? {
        // Bedrock returns JSON with "bytes" field containing base64 of inner JSON
        if let wrapper = try? JSONDecoder().decode(BedrockDelta.self, from: data),
           let base64 = wrapper.bytes,
           let innerData = Data(base64Encoded: base64),
           let delta = try? JSONDecoder().decode(ClaudeDelta.self, from: innerData) {
            return delta.delta?.text
        }
        // Direct text
        if let delta = try? JSONDecoder().decode(BedrockDelta.self, from: data) {
            return delta.delta?.text
        }
        return nil
    }
}

// MARK: - HTTP Response Validation

extension AIProvider {
    func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse("Non-HTTP response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            if httpResponse.statusCode == 429 {
                throw AIError.rateLimited
            }
            throw AIError.providerError(statusCode: httpResponse.statusCode, message: message)
        }
    }
}
