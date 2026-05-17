import SwiftData
import Foundation

@Model
final class AnalysisSession {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date

    // User input
    var queryText: String

    // AI response
    var responseText: String
    var isStreaming: Bool

    // Provider metadata
    var providerRawValue: String
    var providerModel: String
    var inputTokens: Int
    var outputTokens: Int
    var latencyMS: Double

    // Categorization for history grouping
    var healthCategoryRawValues: [String]

    // Associated data snapshot
    @Relationship(deleteRule: .cascade)
    var snapshot: HealthSnapshot?

    // Serialized chart configs for replay
    var chartConfigsJSON: Data?

    // User engagement
    var isFavorited: Bool
    var userRating: Int  // 0 = unrated, 1–5

    init(
        queryText: String,
        providerRawValue: String,
        providerModel: String,
        categories: [HealthCategory] = []
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.queryText = queryText
        self.responseText = ""
        self.isStreaming = false
        self.providerRawValue = providerRawValue
        self.providerModel = providerModel
        self.inputTokens = 0
        self.outputTokens = 0
        self.latencyMS = 0
        self.healthCategoryRawValues = categories.map(\.rawValue)
        self.isFavorited = false
        self.userRating = 0
    }

    var provider: AIProviderType? {
        AIProviderType(rawValue: providerRawValue)
    }

    var categories: [HealthCategory] {
        healthCategoryRawValues.compactMap { HealthCategory(rawValue: $0) }
    }

    var formattedDate: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    var queryPreview: String {
        String(queryText.prefix(80))
    }
}
