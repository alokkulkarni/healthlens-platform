import SwiftUI
import Charts

struct BarChartView: View {
    let dataPoints: [HealthDataPoint]
    var title: String = ""
    var color: Color = .green
    var showGoalLine: Double? = nil

    private var chartData: [ChartDataPoint] { dataPoints.toChartData() }

    private var maxValue: Double {
        chartData.map(\.value).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            if !title.isEmpty {
                Text(title)
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(.secondaryText)
            }

            if chartData.isEmpty {
                emptyState
            } else {
                Chart {
                    ForEach(chartData) { point in
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(barColor(for: point.value))
                        .cornerRadius(4)
                    }

                    if let goal = showGoalLine {
                        RuleMark(y: .value("Goal", goal))
                            .foregroundStyle(.orange.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                            .annotation(position: .trailing) {
                                Text("Goal")
                                    .font(DesignTokens.Typography.caption2)
                                    .foregroundStyle(.orange)
                            }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.divider)
                        AxisValueLabel(format: .dateTime.day())
                            .font(.system(size: 9))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.divider)
                        AxisValueLabel()
                            .font(DesignTokens.Typography.caption2)
                    }
                }
                .animation(DesignTokens.Animation.standard, value: chartData.count)
            }
        }
    }

    private func barColor(for value: Double) -> some ShapeStyle {
        let fraction = maxValue > 0 ? value / maxValue : 0
        return LinearGradient(
            colors: [color, color.opacity(0.6 + fraction * 0.4)],
            startPoint: .bottom,
            endPoint: .top
        )
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
