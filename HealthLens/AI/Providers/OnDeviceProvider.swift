import Foundation
import OSLog
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - On-Device Provider

/// On-device AI provider using Apple Intelligence (FoundationModels.framework, iOS 26+).
/// Produces a clear error on earlier OS versions so users know to pick a cloud provider
/// rather than silently receiving fake data.
struct OnDeviceProvider: AIProvider {
    let providerType: AIProviderType = .onDevice

    let availableModels: [AIModelDescriptor] = [
        AIModelDescriptor(
            id: "apple-foundation-model",
            displayName: "Apple Intelligence (On-Device)",
            contextWindow: 4_096,
            supportsStreaming: true,
            isOnDevice: true,
            providerType: .onDevice
        ),
    ]

    // MARK: - Complete

    func complete(_ request: AIRequest) async throws -> AIResponse {
        if #available(iOS 26.0, *) {
            return try await completeWithFoundationModel(request)
        }
        throw AIError.providerNotAvailable(
            "Apple Intelligence requires iOS 26 or later. " +
            "Please configure Claude, Gemini, or Bedrock in Settings."
        )
    }

    // MARK: - Stream

    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    if #available(iOS 26.0, *) {
                        try await streamWithFoundationModel(request, continuation: continuation)
                    } else {
                        continuation.finish(
                            throwing: AIError.providerNotAvailable(
                                "Apple Intelligence requires iOS 26 or later."
                            )
                        )
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - FoundationModels integration (iOS 26+)

    @available(iOS 26.0, *)
    private func completeWithFoundationModel(_ request: AIRequest) async throws -> AIResponse {
#if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            let reason: String
            switch model.availability {
            case .unavailable(.deviceNotEligible):
                reason = "This device does not support Apple Intelligence."
            case .unavailable(.appleIntelligenceNotEnabled):
                reason = "Apple Intelligence is not enabled. Go to Settings → Apple Intelligence & Siri to enable it."
            case .unavailable(.modelNotReady):
                reason = "The on-device model is not ready yet. It may still be downloading."
            default:
                reason = "Apple Intelligence is not available."
            }
            throw AIError.providerNotAvailable(reason)
        }

        let session = LanguageModelSession(instructions: request.systemPrompt)
        let start = Date()
        let response = try await session.respond(to: request.userMessage)
        let latency = Date().timeIntervalSince(start) * 1000
        let text = response.content

        return AIResponse(
            text: text,
            inputTokens: estimateTokens(request.systemPrompt + request.userMessage),
            outputTokens: estimateTokens(text),
            modelID: "apple-foundation-model",
            finishReason: "stop",
            latencyMS: latency
        )
#else
        throw AIError.providerNotAvailable(
            "FoundationModels.framework is not available in this build. " +
            "Build with Xcode 26 targeting iOS 26 to enable on-device AI."
        )
#endif
    }

    @available(iOS 26.0, *)
    private func streamWithFoundationModel(
        _ request: AIRequest,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
#if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            let reason: String
            switch model.availability {
            case .unavailable(.deviceNotEligible):
                reason = "This device does not support Apple Intelligence."
            case .unavailable(.appleIntelligenceNotEnabled):
                reason = "Apple Intelligence is not enabled. Go to Settings → Apple Intelligence & Siri."
            case .unavailable(.modelNotReady):
                reason = "The on-device model is not ready yet. It may still be downloading."
            default:
                reason = "Apple Intelligence is not available."
            }
            continuation.finish(throwing: AIError.providerNotAvailable(reason))
            return
        }

        let session = LanguageModelSession(instructions: request.systemPrompt)
        // streamResponse(to:) yields ResponseStream<String>.Snapshot; each snapshot
        // exposes `.content` with the cumulative text generated so far.
        var lastContent = ""
        for try await snapshot in session.streamResponse(to: request.userMessage) {
            let current = snapshot.content
            let delta = String(current.dropFirst(lastContent.count))
            if !delta.isEmpty {
                continuation.yield(delta)
            }
            lastContent = current
        }
        continuation.finish()
#else
        continuation.finish(
            throwing: AIError.providerNotAvailable(
                "FoundationModels.framework is not available in this build."
            )
        )
#endif
    }

    // MARK: - Helpers

    private func estimateTokens(_ text: String) -> Int {
        max(1, text.count / 4)
    }
}
