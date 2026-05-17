import SwiftUI
import Charts

/// Dispatches to the correct chart type based on data category and chart suggestion.
struct HealthChartFactory: View {
    let dataPoints: [HealthDataPoint]
    let suggestion: ChartSuggestion
    var height: CGFloat = 200

    var body: some View {
        Group {
            switch suggestion.chartType {
            case "line":
                LineChartView(dataPoints: filteredPoints, title: suggestion.title)
                    .frame(height: height)
            case "bar":
                BarChartView(dataPoints: filteredPoints, title: suggestion.title)
                    .frame(height: height)
            case "scatter":
                ScatterChartView(dataPoints: filteredPoints, title: suggestion.title)
                    .frame(height: height)
            case "heatmap":
                HeatmapView(dataPoints: filteredPoints, title: suggestion.title)
                    .frame(height: height + 40)
            case "range":
                RangeChartView(dataPoints: filteredPoints, title: suggestion.title)
                    .frame(height: height)
            default:
                LineChartView(dataPoints: filteredPoints, title: suggestion.title)
                    .frame(height: height)
            }
        }
    }

    private var filteredPoints: [HealthDataPoint] {
        dataPoints
            .filter { $0.categoryRawValue == suggestion.category }
            .filter { $0.typeIdentifier.contains(suggestion.typeIdentifier.components(separatedBy: "Identifier").last ?? suggestion.typeIdentifier) }
            .sorted { $0.timestamp < $1.timestamp }
    }
}

// MARK: - Chart from serialized records (for live query views)

struct HealthChartFromRecords: View {
    let records: [SerializedHealthRecord]
    let suggestion: ChartSuggestion
    var height: CGFloat = 200

    var body: some View {
        let filtered = records
            .filter { $0.category == suggestion.category }
            .sorted { $0.date < $1.date }

        let dataPoints = filtered.map { record -> HealthDataPoint in
            let category = HealthCategory(rawValue: record.category) ?? .activity
            let timestamp = ISO8601DateFormatter().date(from: record.date) ?? Date()
            return HealthDataPoint(
                typeIdentifier: record.typeIdentifier,
                category: category,
                timestamp: timestamp,
                value: record.value,
                unit: record.unit,
                source: record.source,
                aggregation: AggregationType(rawValue: record.aggregation) ?? .raw
            )
        }

        HealthChartFactory(
            dataPoints: dataPoints,
            suggestion: suggestion,
            height: height
        )
    }
}

// MARK: - Helper: ChartDataPoint for SwiftUI Charts

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let label: String
}

extension [HealthDataPoint] {
    func toChartData() -> [ChartDataPoint] {
        map { ChartDataPoint(date: $0.timestamp, value: $0.value, label: $0.typeIdentifier) }
    }
}
