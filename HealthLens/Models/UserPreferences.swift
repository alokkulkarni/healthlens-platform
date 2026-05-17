import SwiftData
import Foundation

@Model
final class UserPreferences {
    @Attribute(.unique) var singletonKey: String = "default"

    var activeProviderRawValue: String
    var activeModelID: String
    var defaultDateRangeDays: Int
    var preferredUnitSystem: String       // "metric" | "imperial"
    var enableBackgroundRefresh: Bool
    var useBiometricLock: Bool
    var accentColorName: String
    var hasCompletedOnboarding: Bool
    var grantedHealthCategories: [String]

    // Bedrock-specific
    var bedrockRegion: String
    var bedrockModelID: String

    init() {
        self.activeProviderRawValue = AIProviderType.claude.rawValue
        self.activeModelID = "claude-sonnet-4-6"
        self.defaultDateRangeDays = 30
        self.preferredUnitSystem = "metric"
        self.enableBackgroundRefresh = false
        self.useBiometricLock = false
        self.accentColorName = "blue"
        self.hasCompletedOnboarding = false
        self.grantedHealthCategories = []
        self.bedrockRegion = "us-east-1"
        self.bedrockModelID = "anthropic.claude-3-sonnet-20240229-v1:0"
    }

    var activeProvider: AIProviderType {
        get { AIProviderType(rawValue: activeProviderRawValue) ?? .claude }
        set { activeProviderRawValue = newValue.rawValue }
    }

    func isHealthCategoryGranted(_ category: HealthCategory) -> Bool {
        grantedHealthCategories.contains(category.rawValue)
    }

    func markCategoryGranted(_ category: HealthCategory) {
        if !grantedHealthCategories.contains(category.rawValue) {
            grantedHealthCategories.append(category.rawValue)
        }
    }
}

/// Helper to fetch or create the singleton preferences from a ModelContext
extension UserPreferences {
    @MainActor
    static func fetch(in context: ModelContext) -> UserPreferences {
        let descriptor = FetchDescriptor<UserPreferences>(
            predicate: #Predicate { $0.singletonKey == "default" }
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let prefs = UserPreferences()
        context.insert(prefs)
        return prefs
    }
}
