import SwiftUI

/// Displays a calendar-style heatmap for weekly health data (e.g. sleep stages, activity).
struct HeatmapView: View {
    let dataPoints: [HealthDataPoint]
    var title: String = ""
    var color: Color = .indigo

    private let calendar = Calendar.current
    private let daysOfWeek = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    // Group data by (week, weekday) → average value
    private var heatmapData: [[HeatCell]] {
        guard !dataPoints.isEmpty else { return [] }
        let sorted = dataPoints.sorted { $0.timestamp < $1.timestamp }
        let startDate = calendar.startOfDay(for: sorted.first!.timestamp)
        let endDate = calendar.startOfDay(for: sorted.last!.timestamp)

        var byDate: [Date: [Double]] = [:]
        for point in sorted {
            let day = calendar.startOfDay(for: point.timestamp)
            byDate[day, default: []].append(point.value)
        }

        // Build weeks
        var weeks: [[HeatCell]] = []
        var weekStart = startDate
        let maxValue = dataPoints.map(\.value).max() ?? 1

        while weekStart <= endDate {
            var week: [HeatCell] = []
            for dayOffset in 0...6 {
                let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) ?? weekStart
                let values = byDate[day] ?? []
                let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
                let intensity = maxValue > 0 ? avg / maxValue : 0
                week.append(HeatCell(date: day, value: avg, intensity: intensity))
            }
            weeks.append(week)
            weekStart = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart
        }
        return weeks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            if !title.isEmpty {
                Text(title)
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(.secondaryText)
            }

            if dataPoints.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    // Day-of-week header
                    HStack(spacing: 2) {
                        ForEach(daysOfWeek, id: \.self) { day in
                            Text(day)
                                .font(DesignTokens.Typography.caption2)
                                .foregroundStyle(.tertiaryText)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    // Weeks grid
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(heatmapData.indices, id: \.self) { weekIdx in
                                VStack(spacing: 2) {
                                    ForEach(heatmapData[weekIdx]) { cell in
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .fill(cellColor(intensity: cell.intensity))
                                            .frame(width: 16, height: 16)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 2)
                                                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                                            )
                                            .help("\(cell.date.formatted(.dateTime.month().day())): \(String(format: "%.1f", cell.value))")
                                    }
                                }
                            }
                        }
                    }

                    // Legend
                    HStack(spacing: 4) {
                        Text("Less")
                            .font(DesignTokens.Typography.caption2)
                            .foregroundStyle(.tertiaryText)
                        ForEach([0.1, 0.3, 0.5, 0.7, 1.0], id: \.self) { intensity in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(cellColor(intensity: intensity))
                                .frame(width: 12, height: 12)
                        }
                        Text("More")
                            .font(DesignTokens.Typography.caption2)
                            .foregroundStyle(.tertiaryText)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func cellColor(intensity: Double) -> Color {
        if intensity <= 0 {
            return Color.fillTertiary
        }
        return color.opacity(0.15 + intensity * 0.85)
    }

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
            .fill(Color.fillTertiary)
            .frame(height: 80)
            .overlay {
                Text("No data available")
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(.tertiaryText)
            }
    }
}

private struct HeatCell: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let intensity: Double
}
