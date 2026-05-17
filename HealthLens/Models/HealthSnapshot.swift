import SwiftData
import Foundation

@Model
final class HealthSnapshot {
    var id: UUID
    var capturedAt: Date
    var dateRangeStart: Date
    var dateRangeEnd: Date

    // dataPoints are constructed from payloadJSON on-demand; not persisted
    // separately because HealthDataPoint is a plain struct, not a @Model.
    @Transient var dataPoints: [HealthDataPoint] = []

    // Full JSON payload sent to AI — used for exact replay context
    var payloadJSON: Data

    init(start: Date, end: Date, payloadJSON: Data) {
        self.id = UUID()
        self.capturedAt = Date()
        self.dateRangeStart = start
        self.dateRangeEnd = end
        self.payloadJSON = payloadJSON
    }

    var dateRange: DateInterval {
        DateInterval(start: dateRangeStart, end: dateRangeEnd)
    }

    var formattedDateRange: String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: dateRangeStart, to: dateRangeEnd)
    }

    func dataPoints(for category: HealthCategory) -> [HealthDataPoint] {
        dataPoints.filter { $0.categoryRawValue == category.rawValue }
    }
}
