import Foundation

// MARK: - Provider Type

enum AIProviderType: String, CaseIterable, Codable, Hashable, Identifiable {
    case claude    = "claude"
    case gemini    = "gemini"
    case bedrock   = "bedrock"
    case onDevice  = "on_device"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude:   return "Claude (Anthropic)"
        case .gemini:   return "Gemini (Google)"
        case .bedrock:  return "Bedrock (AWS)"
        case .onDevice: return "On-Device"
        }
    }

    var systemImage: String {
        switch self {
        case .claude:   return "brain.head.profile"
        case .gemini:   return "sparkle"
        case .bedrock:  return "cloud.fill"
        case .onDevice: return "iphone"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .onDevice: return false
        default:        return true
        }
    }
}

// MARK: - Model Descriptor

struct AIModelDescriptor: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var displayName: String
    var contextWindow: Int
    var supportsStreaming: Bool
    var isOnDevice: Bool
    var providerType: AIProviderType

    var shortName: String {
        displayName.components(separatedBy: " ").prefix(2).joined(separator: " ")
    }

    /// Maximum characters to include in the health-data portion of a prompt.
    /// On-device SLMs have a ~4K token limit; cloud models scale with their context window.
    /// Gemini 2.5/3.x has a 1M-token window; we cap at 500K chars (~125K tokens) to leave
    /// room for the system prompt and response.
    var maxPromptCharacters: Int {
        if isOnDevice { return 6_000 }
        // contextWindow is in tokens; ~4 chars/token average
        let charBudget = contextWindow * 4
        return min(charBudget / 2, 500_000)
    }
}

// MARK: - Request / Response

struct AIRequest: Sendable {
    var systemPrompt: String
    var userMessage: String
    var modelID: String
    var maxTokens: Int = Constants.AI.defaultMaxTokens
    var temperature: Double = Constants.AI.defaultTemperature
    var stream: Bool = true
}

struct AIResponse: Sendable {
    var text: String
    var inputTokens: Int
    var outputTokens: Int
    var modelID: String
    var finishReason: String
    var latencyMS: Double
    var rawJSON: Data?
}

// MARK: - Provider Protocol

protocol AIProvider: Sendable {
    var providerType: AIProviderType { get }
    var availableModels: [AIModelDescriptor] { get }

    /// Non-streaming complete (for short queries or fallback)
    func complete(_ request: AIRequest) async throws -> AIResponse

    /// Streaming: emits partial text deltas. Must call `finish()` at end.
    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error>
}

// MARK: - Errors

enum AIError: LocalizedError {
    case missingAPIKey(AIProviderType)
    case rateLimited
    case contextLengthExceeded
    case invalidResponse(String)
    case networkError(Error)
    case unsupportedModel(String)
    case providerError(statusCode: Int, message: String)
    case providerNotAvailable(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let p):
            return "API key for \(p.displayName) is not configured. Go to Settings to add it."
        case .rateLimited:
            return "Rate limit reached. Please wait a moment and try again."
        case .contextLengthExceeded:
            return "Query data is too large for this model. Try a shorter date range."
        case .invalidResponse(let msg):
            return "Invalid response from AI: \(msg)"
        case .networkError(let e):
            return "Network error: \(e.localizedDescription)"
        case .unsupportedModel(let m):
            return "Model '\(m)' is not supported by this provider."
        case .providerError(let code, let msg):
            return "Provider error (\(code)): \(msg)"
        case .providerNotAvailable(let reason):
            return reason
        }
    }
}
