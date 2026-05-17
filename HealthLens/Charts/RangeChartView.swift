import SwiftUI
import Charts

/// Displays min/max ranges (e.g. blood pressure systolic/diastolic).
struct RangeChartView: View {
    let dataPoints: [HealthDataPoint]
    var title: String = ""
    var color: Color = .teal

    // Expects dataPoints to contain both systolic and diastolic values
    // typeIdentifier distinguishes them
    private var chartData: [RangeDataPoint] {
        let sorted = dataPoints.sorted { $0.timestamp < $1.timestamp }
        var grouped: [Date: (hi: Double?, lo: Double?)] = [:]

        for point in sorted {
            let day = Calendar.current.startOfDay(for: point.timestamp)
            if point.typeIdentifier.contains("Systolic") || point.typeIdentifier.lowercased().contains("systolic") {
                grouped[day, default: (nil, nil)].hi = point.value
            } else if point.typeIdentifier.contains("Diastolic") || point.typeIdentifier.lowercased().contains("diastolic") {
                grouped[day, default: (nil, nil)].lo = point.value
            } else {
                // Single metric: use as center, estimate range
                let val = point.value
                grouped[day, default: (nil, nil)] = (hi: val * 1.05, lo: val * 0.95)
            }
        }

        return grouped
            .compactMap { date, pair -> RangeDataPoint? in
                guard let hi = pair.hi, let lo = pair.lo else { return nil }
                return RangeDataPoint(date: date, high: hi, low: lo)
            }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            if !title.isEmpty {
                Text(title)
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(.secondaryText)
            }

            if chartData.isEmpty {
                // Fall back to simple line chart
                if !dataPoints.isEmpty {
                    LineChartView(dataPoints: dataPoints, title: "", color: color)
                } else {
                    emptyState
                }
            } else {
                Chart {
                    // Healthy range band (e.g. normal BP: 80–120)
                    if let first = chartData.first, let last = chartData.last {
                        RectangleMark(
                            xStart: .value("Start", first.date),
                            xEnd: .value("End", last.date),
                            yStart: .value("Normal Low", normalRangeLow),
                            yEnd: .value("Normal High", normalRangeHigh)
                        )
                        .foregroundStyle(Color.healthGood.opacity(0.08))
                    }

                    // Range bars
                    ForEach(chartData) { point in
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            yStart: .value("Low", point.low),
                            yEnd: .value("High", point.high)
                        )
                        .foregroundStyle(barColor(for: point))
                        .cornerRadius(2)
                    }

                    // High line
                    ForEach(chartData) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("High", point.high),
                            series: .value("Series", "High")
                        )
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.catmullRom)
                    }

                    // Low line
                    ForEach(chartData) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Low", point.low),
                            series: .value("Series", "Low")
                        )
                        .foregroundStyle(color.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(1, chartData.count / 5))) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.divider)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(DesignTokens.Typography.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.divider)
                        AxisValueLabel()
                            .font(DesignTokens.Typography.caption2)
                    }
                }
                .chartLegend(position: .topTrailing)
                .animation(DesignTokens.Animation.standard, value: chartData.count)
            }
        }
    }

    // Normal BP range (adjust per metric type in production)
    private var normalRangeLow: Double { 60 }
    private var normalRangeHigh: Double { 120 }

    private func barColor(for point: RangeDataPoint) -> Color {
        if point.high > 140 || point.low > 90 {
            return .healthCritical.opacity(0.7)
        } else if point.high > 130 || point.low > 80 {
            return .healthWarning.opacity(0.7)
        }
        return color.opacity(0.5)
    }

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
            .fill(Color.fillTertiary)
            .overlay {
                Text("No data available")
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(.tertiaryText)
            }
    }
}

private struct RangeDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let high: Double
    let low: Double
}
