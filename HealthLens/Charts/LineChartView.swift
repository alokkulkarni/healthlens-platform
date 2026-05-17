import SwiftUI
import Charts

struct LineChartView: View {
    let dataPoints: [HealthDataPoint]
    var title: String = ""
    var color: Color = .blue
    var showPoints: Bool = true
    var showAverage: Bool = true

    private var chartData: [ChartDataPoint] { dataPoints.toChartData() }

    private var average: Double {
        guard !chartData.isEmpty else { return 0 }
        return chartData.map(\.value).reduce(0, +) / Double(chartData.count)
    }

    private var yRange: ClosedRange<Double> {
        guard !chartData.isEmpty else { return 0...1 }
        let values = chartData.map(\.value)
        let min = values.min() ?? 0
        let max = values.max() ?? 1
        let padding = (max - min) * 0.1
        return (min - padding)...(max + padding)
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
                    // Area fill
                    ForEach(chartData) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [color.opacity(0.3), color.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }

                    // Line
                    ForEach(chartData) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                    }

                    // Points
                    if showPoints && chartData.count <= 30 {
                        ForEach(chartData) { point in
                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(color)
                            .symbolSize(25)
                        }
                    }

                    // Average line
                    if showAverage {
                        RuleMark(y: .value("Average", average))
                            .foregroundStyle(color.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .trailing, alignment: .center) {
                                Text("avg")
                                    .font(DesignTokens.Typography.caption2)
                                    .foregroundStyle(color.opacity(0.7))
                            }
                    }
                }
                .chartYScale(domain: yRange)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.divider)
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
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
