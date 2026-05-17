import SwiftUI
import Charts

struct ScatterChartView: View {
    let dataPoints: [HealthDataPoint]
    var title: String = ""
    var color: Color = .purple

    private var chartData: [ChartDataPoint] { dataPoints.toChartData() }

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
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(color.opacity(0.7))
                        .symbolSize(40)
                    }

                    // Trend line using linear regression
                    if chartData.count >= 3,
                       let (slope, intercept) = linearRegression(chartData) {
                        let firstDate = chartData.first!.date
                        let lastDate = chartData.last!.date
                        let firstValue = slope * 0 + intercept
                        let lastValue = slope * Double(chartData.count - 1) + intercept

                        LineMark(
                            x: .value("Date", firstDate),
                            y: .value("Trend", firstValue)
                        )
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                        LineMark(
                            x: .value("Date", lastDate),
                            y: .value("Trend", lastValue)
                        )
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { value in
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
                .animation(DesignTokens.Animation.standard, value: chartData.count)
            }
        }
    }

    private func linearRegression(_ data: [ChartDataPoint]) -> (slope: Double, intercept: Double)? {
        let n = Double(data.count)
        guard n >= 2 else { return nil }
        let xs = (0..<data.count).map { Double($0) }
        let ys = data.map(\.value)
        let xMean = xs.reduce(0, +) / n
        let yMean = ys.reduce(0, +) / n
        let numerator = zip(xs, ys).map { (($0 - xMean) * ($1 - yMean)) }.reduce(0, +)
        let denominator = xs.map { ($0 - xMean) * ($0 - xMean) }.reduce(0, +)
        guard denominator != 0 else { return nil }
        let slope = numerator / denominator
        let intercept = yMean - slope * xMean
        return (slope, intercept)
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
