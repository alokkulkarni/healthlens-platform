import Foundation
import Observation

/// Routes AI requests to the currently active provider.
/// Supports dynamic switching between Claude, Gemini, Bedrock, and On-Device.
@MainActor
@Observable
final class AIServiceRouter {
    private(set) var activeProviderType: AIProviderType = .onDevice
    private(set) var activeModelID: String = "apple-foundation-model"

    private let keyStore: APIKeyStore
    private var providerCache: [AIProviderType: any AIProvider] = [:]

    init(keyStore: APIKeyStore) {
        self.keyStore = keyStore
    }

    // MARK: - Provider Selection

    func setProvider(_ type: AIProviderType, modelID: String) {
        activeProviderType = type
        activeModelID = modelID
        providerCache.removeValue(forKey: type)  // force rebuild
    }

    var activeProvider: any AIProvider {
        if let cached = providerCache[activeProviderType] {
            return cached
        }
        let provider = buildProvider(activeProviderType)
        providerCache[activeProviderType] = provider
        return provider
    }

    var availableModels: [AIModelDescriptor] {
        activeProvider.availableModels
    }

    var activeModelDescriptor: AIModelDescriptor? {
        availableModels.first { $0.id == activeModelID }
    }

    var allProviderModels: [(AIProviderType, [AIModelDescriptor])] {
        AIProviderType.allCases.map { type in
            (type, buildProvider(type).availableModels)
        }
    }

    // MARK: - Execution

    func complete(_ request: AIRequest) async throws -> AIResponse {
        var req = request
        req.modelID = activeModelID
        req.stream = false
        return try await activeProvider.complete(req)
    }

    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error> {
        var req = request
        req.modelID = activeModelID
        req.stream = true
        return activeProvider.stream(req)
    }

    func hasKeyConfigured(for provider: AIProviderType) -> Bool {
        keyStore.hasKey(for: provider)
    }

    /// Call after saving a new API key so the cached provider is rebuilt with the fresh key.
    func invalidateCache(for provider: AIProviderType) {
        providerCache.removeValue(forKey: provider)
    }

    // MARK: - Provider Construction

    private func buildProvider(_ type: AIProviderType) -> any AIProvider {
        switch type {
        case .claude:
            return ClaudeProvider(keyStore: keyStore)
        case .gemini:
            return GeminiProvider(keyStore: keyStore)
        case .bedrock:
            return BedrockProvider(keyStore: keyStore)
        case .onDevice:
            return OnDeviceProvider()
        }
    }
}
