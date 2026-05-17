import SwiftUI

struct SuggestedQueryChip: View {
    let text: String
    var onTap: (String) -> Void = { _ in }

    var body: some View {
        Button {
            triggerHaptic(.light)
            onTap(text)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkle")
                    .font(.system(size: 10))
                Text(text)
                    .font(DesignTokens.Typography.footnote)
                    .lineLimit(1)
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.1))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Curated suggestions per category

enum QuerySuggestions {
    static let general = [
        "How has my overall health changed this month?",
        "What trends should I be aware of?",
        "Give me a summary of my health data",
        "What are my top health improvements this year?",
    ]

    static let byCategory: [HealthCategory: [String]] = [
        .activity: [
            "How many steps have I averaged this week?",
            "What's my most active day of the week?",
            "How does my exercise compare to last month?",
            "Am I meeting my fitness goals?",
        ],
        .heart: [
            "Is my resting heart rate improving?",
            "What does my HRV trend say about recovery?",
            "How has my VO₂ Max changed over time?",
            "Are there any concerning heart rate patterns?",
        ],
        .sleep: [
            "How has my sleep quality changed this month?",
            "What is my average sleep duration?",
            "Do I get enough deep sleep?",
            "How does my weekday vs weekend sleep compare?",
        ],
        .body: [
            "How has my weight changed over 3 months?",
            "Is my BMI in a healthy range?",
            "What's the trend in my body composition?",
        ],
        .nutrition: [
            "Am I hitting my daily calorie targets?",
            "How balanced is my macronutrient intake?",
            "Am I drinking enough water?",
        ],
        .vitals: [
            "Is my blood pressure in a healthy range?",
            "How has my blood oxygen varied?",
            "Are my vital signs trending well?",
        ],
        .mindfulness: [
            "How consistent is my meditation practice?",
            "Does meditation correlate with better sleep?",
        ],
        .labs: [
            "How has my blood glucose trended?",
            "Are my lab results within normal ranges?",
        ],
        .reproductive: [
            "What patterns do I see in my cycle data?",
        ],
    ]

    static func suggestions(for categories: [HealthCategory]) -> [String] {
        if categories.isEmpty { return general }
        let categorySpecific = categories.flatMap { byCategory[$0] ?? [] }
        return Array((categorySpecific + general).prefix(6))
    }
}
