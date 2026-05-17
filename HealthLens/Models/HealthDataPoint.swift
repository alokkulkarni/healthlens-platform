import Foundation

// Plain value type — no SwiftData @Model needed since HealthDataPoints
// are constructed in-memory from HealthKit fetches and not queried independently.
struct HealthDataPoint: Identifiable, Equatable, Codable {
    var id: UUID
    var typeIdentifier: String
    var categoryRawValue: String
    var timestamp: Date
    var value: Double
    var unit: String
    var sourceApp: String
    var aggregationRawValue: String   // "sum"|"average"|"min"|"max"|"raw"

    init(
        typeIdentifier: String,
        category: HealthCategory,
        timestamp: Date,
        value: Double,
        unit: String,
        source: String = "unknown",
        aggregation: AggregationType = .raw
    ) {
        self.id = UUID()
        self.typeIdentifier = typeIdentifier
        self.categoryRawValue = category.rawValue
        self.timestamp = timestamp
        self.value = value
        self.unit = unit
        self.sourceApp = source
        self.aggregationRawValue = aggregation.rawValue
    }

    var category: HealthCategory? {
        HealthCategory(rawValue: categoryRawValue)
    }

    var aggregation: AggregationType {
        AggregationType(rawValue: aggregationRawValue) ?? .raw
    }
}

enum AggregationType: String, Codable {
    case sum, average, min, max, raw
}
