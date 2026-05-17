import Foundation

/// Typed API key read/write per AI provider.
struct APIKeyStore {
    private let keychain = KeychainService()

    // MARK: - Claude / Anthropic

    func saveClaudeKey(_ key: String) throws {
        try keychain.save(key, for: Constants.Keychain.claudeKey)
    }

    func retrieveClaudeKey() throws -> String {
        try keychain.retrieve(for: Constants.Keychain.claudeKey)
    }

    func deleteClaudeKey() throws {
        try keychain.delete(for: Constants.Keychain.claudeKey)
    }

    // MARK: - Gemini

    func saveGeminiKey(_ key: String) throws {
        try keychain.save(key, for: Constants.Keychain.geminiKey)
    }

    func retrieveGeminiKey() throws -> String {
        try keychain.retrieve(for: Constants.Keychain.geminiKey)
    }

    func deleteGeminiKey() throws {
        try keychain.delete(for: Constants.Keychain.geminiKey)
    }

    // MARK: - AWS Bedrock

    func saveBedrockCredentials(accessKey: String, secretKey: String, sessionToken: String? = nil, region: String = "") throws {
        try keychain.save(accessKey, for: Constants.Keychain.bedrockAccessKey)
        try keychain.save(secretKey, for: Constants.Keychain.bedrockSecretKey)
        if let sessionToken {
            try keychain.save(sessionToken, for: Constants.Keychain.bedrockSessionToken)
        }
        if !region.isEmpty {
            try keychain.save(region, for: Constants.Keychain.bedrockRegion)
        }
    }

    func retrieveBedrockCredentials() throws -> BedrockCredentials {
        let accessKey = try keychain.retrieve(for: Constants.Keychain.bedrockAccessKey)
        let secretKey = try keychain.retrieve(for: Constants.Keychain.bedrockSecretKey)
        let sessionToken = try? keychain.retrieve(for: Constants.Keychain.bedrockSessionToken)
        let region = (try? keychain.retrieve(for: Constants.Keychain.bedrockRegion)) ?? ""
        return BedrockCredentials(accessKeyID: accessKey, secretAccessKey: secretKey, sessionToken: sessionToken, region: region)
    }

    func deleteBedrockCredentials() throws {
        try keychain.delete(for: Constants.Keychain.bedrockAccessKey)
        try keychain.delete(for: Constants.Keychain.bedrockSecretKey)
        try? keychain.delete(for: Constants.Keychain.bedrockSessionToken)
        try? keychain.delete(for: Constants.Keychain.bedrockRegion)
    }

    // MARK: - Generic key retrieval by provider type

    func retrieveKey(for provider: AIProviderType) throws -> String {
        switch provider {
        case .claude:
            return try retrieveClaudeKey()
        case .gemini:
            return try retrieveGeminiKey()
        case .bedrock:
            // Returns access key; secret handled separately
            return try keychain.retrieve(for: Constants.Keychain.bedrockAccessKey)
        case .onDevice:
            return ""  // No API key needed
        }
    }

    func hasKey(for provider: AIProviderType) -> Bool {
        switch provider {
        case .claude:
            return keychain.exists(for: Constants.Keychain.claudeKey)
        case .gemini:
            return keychain.exists(for: Constants.Keychain.geminiKey)
        case .bedrock:
            return keychain.exists(for: Constants.Keychain.bedrockAccessKey)
        case .onDevice:
            return true
        }
    }
}

struct BedrockCredentials {
    let accessKeyID: String
    let secretAccessKey: String
    let sessionToken: String?
    var region: String = ""
}
