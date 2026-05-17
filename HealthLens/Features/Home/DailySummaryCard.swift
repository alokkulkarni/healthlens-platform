import SwiftUI

struct DailySummaryCard: View {
    let stats: [HomeViewModel.QuickStat]
    var isLoading: Bool = false

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default:      return "Good night"
        }
    }

    private var dateString: String {
        Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting)
                        .font(DesignTokens.Typography.title2)
                        .foregroundStyle(.primaryText)
                    Text(dateString)
                        .font(DesignTokens.Typography.subheadline)
                        .foregroundStyle(.secondaryText)
                }
                Spacer()
                activityRing
            }

            Divider()

            // Key metrics grid
            if isLoading {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignTokens.Spacing.sm) {
                    ForEach(0..<4, id: \.self) { _ in
                        summaryMetricSkeleton
                    }
                }
            } else if !stats.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignTokens.Spacing.sm) {
                    ForEach(stats.prefix(4)) { stat in
                        summaryMetric(stat)
                    }
                }
            }
        }
        .card()
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    private var activityRing: some View {
        ZStack {
            Circle()
                .stroke(Color.healthGood.opacity(0.2), lineWidth: 6)
                .frame(width: 48, height: 48)

            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    LinearGradient(colors: [.green, .mint], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: 48, height: 48)
                .rotationEffect(.degrees(-90))
                .animation(DesignTokens.Animation.slow, value: ringProgress)

            Image(systemName: "bolt.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.healthGood)
        }
    }

    private var ringProgress: CGFloat {
        guard let stepsStat = stats.first(where: { $0.category == .activity }),
              let steps = Double(stepsStat.value.replacingOccurrences(of: ",", with: ""))
        else { return 0 }
        return min(CGFloat(steps / 10000), 1.0)
    }

    @ViewBuilder
    private func summaryMetric(_ stat: HomeViewModel.QuickStat) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: stat.systemImage)
                .font(.caption)
                .foregroundStyle(stat.category.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 2) {
                    Text(stat.value)
                        .font(DesignTokens.Typography.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primaryText)
                        .contentTransition(.numericText())
                    Text(stat.unit)
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(.tertiaryText)
                }
                Text(stat.title)
                    .font(DesignTokens.Typography.caption2)
                    .foregroundStyle(.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(DesignTokens.Spacing.xs)
        .background(stat.category.color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
    }

    private var summaryMetricSkeleton: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            SkeletonShape(width: 20, height: 20, cornerRadius: 4)
            VStack(alignment: .leading, spacing: 4) {
                SkeletonShape(width: 50, height: 14)
                SkeletonShape(width: 70, height: 10)
            }
            Spacer()
        }
        .padding(DesignTokens.Spacing.xs)
    }
}
