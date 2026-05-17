import Foundation

enum Constants {
    static let backgroundRefreshTaskID = "com.healthlens.background-refresh"
    static let bundleIdentifier = "com.healthlens"

    enum API {
        static let claudeBaseURL = "https://api.anthropic.com/v1/messages"
        static let claudeAPIVersion = "2023-06-01"
        static let geminiBaseURL = "https://generativelanguage.googleapis.com/v1beta/models"
        static let bedrockRegion = "us-east-1"
    }

    enum Keychain {
        static let service = "com.healthlens.apikeys"
        static let claudeKey = "anthropic_api_key"
        static let geminiKey = "google_gemini_api_key"
        static let bedrockAccessKey = "aws_access_key_id"
        static let bedrockSecretKey = "aws_secret_access_key"
        static let bedrockSessionToken = "aws_session_token"
        static let bedrockRegion = "aws_region"
    }

    enum Health {
        static let defaultDateRangeDays = 30
        static let maxDataPointsPerQuery = 5000
        static let backgroundRefreshIntervalHours = 4
    }

    enum AI {
        /// Default max output tokens. Cloud models (Gemini, Claude) support large outputs;
        /// 8 192 is enough for a thorough, multi-section health analysis response.
        static let defaultMaxTokens = 8_192
        static let defaultTemperature = 0.3
        static let systemPromptVersion = "1.0"
    }
}
