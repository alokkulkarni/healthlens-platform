import Foundation
import HealthKit

/// Describes a logical permission group that can be requested together.
struct PermissionGroup {
    let tier: Int
    let categories: [HealthCategory]
    let title: String
    let description: String
}

enum HealthKitPermissions {
    /// Tier 0 — requested during onboarding (all non-sensitive categories at once
    /// so the permission sheet appears only once).
    static let onboarding = PermissionGroup(
        tier: 0,
        categories: [.activity, .body, .heart, .sleep, .nutrition, .vitals, .mindfulness, .labs, .environment],
        title: "Health Data Access",
        description: "HealthLens reads your health data to provide AI-powered insights and personalised recommendations."
    )

    /// Tier 1 — (legacy; kept for API compatibility, no longer shown separately)
    static let tier1Groups: [PermissionGroup] = []

    /// Tier 2 — explicit opt-in only (sensitive reproductive data)
    static let sensitiveGroup = PermissionGroup(
        tier: 2,
        categories: [.reproductive],
        title: "Reproductive Health",
        description: "Sensitive health data — only shared with AI when you choose."
    )

    /// All tiers flattened
    static let allGroups: [PermissionGroup] = [onboarding, sensitiveGroup]

    /// Returns the permission group that covers a given category
    static func group(for category: HealthCategory) -> PermissionGroup? {
        allGroups.first { $0.categories.contains(category) }
    }

    /// Returns categories that need to be requested for a given tier and below
    static func categories(upToTier tier: Int) -> [HealthCategory] {
        allGroups
            .filter { $0.tier <= tier }
            .flatMap(\.categories)
    }
}
