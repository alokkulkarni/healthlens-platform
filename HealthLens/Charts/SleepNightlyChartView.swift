import SwiftUI
import Charts

/// A purpose-built nightly sleep duration bar chart.
///
/// Each bar represents one night's total sleep, coloured by quality:
///   ≥ 7.5 h → healthGood (green)   7–7.5 h → healthOk (yellow-green)   < 7 h → healthWarning (amber)
/// A dashed goal line at 7.5 h provides a clear visual target.
struct SleepNightlyChartView: View {
    let dataPoints: [HealthDataPoint]   // one pre-summed point per night, value in hours

    private let goalHours: Double = 7.5

    private var chartData: [ChartDataPoint] { dataPoints.sorted { $0.timestamp < $1.timestamp }.toChartData() }

    private var average: Double {
        guard !chartData.isEmpty else { return 0 }
        return chartData.map(\.value).reduce(0, +) / Double(chartData.count)
    }

    private var nightsMeetingGoal: Int {
        chartData.filter { $0.value >= goalHours }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            if chartData.isEmpty {
                emptyState
            } else {
                // Summary row
                HStack(spacing: DesignTokens.Spacing.md) {
                    summaryPill(label: "Avg", value: String(format: "%.1f h", average),
                                color: qualityColor(for: average))
                    summaryPill(label: "Goal met", value: "\(nightsMeetingGoal)/\(chartData.count) nights",
                                color: .healthGood)
                    Spacer()
                }
                .padding(.bottom, 2)

                Chart {
                    // Goal band (subtle fill above goal line)
                    if let first = chartData.first, let last = chartData.last {
                        RectangleMark(
                            xStart: .value("Start", first.date),
                            xEnd:   .value("End", last.date),
                            yStart: .value("Goal", goalHours),
                            yEnd:   .value("Max",  max(goalHours + 1.5, chartData.map(\.value).max() ?? goalHours + 1))
                        )
                        .foregroundStyle(Color.healthGood.opacity(0.06))
                    }

                    // Nightly bars
                    ForEach(chartData) { point in
                        BarMark(
                            x: .value("Night", point.date, unit: .day),
                            y: .value("Hours",  point.value)
                        )
                        .foregroundStyle(barGradient(for: point.value))
                        .cornerRadius(3)
                    }

                    // Goal line
                    RuleMark(y: .value("Goal", goalHours))
                        .foregroundStyle(Color.healthGood.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                        .annotation(position: .trailing, alignment: .center) {
                            Text("7.5h")
                                .font(DesignTokens.Typography.caption2)
                                .foregroundStyle(Color.healthGood)
                        }

                    // Average line
                    RuleMark(y: .value("Average", average))
                        .foregroundStyle(Color.indigo.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartYScale(domain: 0...max(goalHours + 1.5, chartData.map(\.value).max() ?? goalHours + 1))
                .chartXAxis {
                    AxisMarks(values: axisLabelDates) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.divider)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(DesignTokens.Typography.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 4, 6, 7.5, 9]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.divider)
                        AxisValueLabel()
                            .font(DesignTokens.Typography.caption2)
                    }
                }
                .animation(DesignTokens.Animation.standard, value: chartData.count)

                // Legend
                HStack(spacing: DesignTokens.Spacing.sm) {
                    legendDot(Color.healthGood,    label: "≥7.5h")
                    legendDot(Color.yellow,        label: "7–7.5h")
                    legendDot(Color.healthWarning, label: "<7h")
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Helpers

    /// Returns 3–4 labels anchored by calendar distance, never by array index.
    /// This guarantees labels are spread across the actual date range rather than
    /// clustering wherever the data happens to be dense.
    private var axisLabelDates: [Date] {
        let dates = chartData.map(\.date).sorted()
        guard dates.count > 1 else { return dates }

        // For ≤4 bars, show every bar's label (they'll fit)
        if dates.count <= 4 { return dates }

        // Use real calendar span so labels always reflect the time range,
        // not just the density of recorded nights.
        let first = dates.first!
        let last  = dates.last!
        let totalDays = max(1, Calendar.current
            .dateComponents([.day], from: first, to: last).day ?? 1)

        // Aim for 3 labels on short ranges, 4 on longer ones.
        let targetCount = totalDays <= 14 ? 3 : 4
        let interval    = Double(totalDays) / Double(targetCount - 1)

        var result: [Date] = []
        for i in 0..<targetCount {
            let target = first.addingTimeInterval(Double(i) * interval * 86_400)
            // Pick the recorded night closest to this target time.
            if let nearest = dates.min(by: { abs($0.timeIntervalSince(target)) < abs($1.timeIntervalSince(target)) }) {
                result.append(nearest)
            }
        }
        // Deduplicate while preserving order
        var seen = Set<Date>()
        return result.filter { seen.insert($0).inserted }
    }

    private func qualityColor(for hours: Double) -> Color {
        if hours >= goalHours { return .healthGood }
        if hours >= 7.0       { return .yellow }
        return .healthWarning
    }

    private func barGradient(for hours: Double) -> LinearGradient {
        let color = qualityColor(for: hours)
        return LinearGradient(
            colors: [color.opacity(0.5), color],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    private func summaryPill(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(.tertiaryText)
            Text(value)
                .font(DesignTokens.Typography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
    }

    private func legendDot(_ color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(.secondaryText)
        }
    }

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
            .fill(Color.fillTertiary)
            .frame(height: 130)
            .overlay {
                Text("No sleep data available")
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(.tertiaryText)
            }
    }
}
