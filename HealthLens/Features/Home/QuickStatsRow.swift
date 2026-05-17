import SwiftUI

struct QuickStatsRow: View {
    let stats: [HomeViewModel.QuickStat]
    var isLoading: Bool = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                if isLoading {
                    ForEach(0..<4, id: \.self) { _ in
                        SkeletonStatCard()
                    }
                } else {
                    ForEach(stats) { stat in
                        StatCard(stat: stat)
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
        }
    }
}

private struct StatCard: View {
    let stat: HomeViewModel.QuickStat
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack {
                Image(systemName: stat.systemImage)
                    .font(.caption)
                    .foregroundStyle(stat.category.color)
                Spacer()
                Image(systemName: stat.trend.icon)
                    .font(.caption2)
                    .foregroundStyle(stat.trend.color)
            }

            Text(stat.value)
                .font(DesignTokens.Typography.title3)
                .foregroundStyle(.primaryText)
                .contentTransition(.numericText())

            Text(stat.title)
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(.secondaryText)
                .lineLimit(1)

            Text(stat.unit)
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(.tertiaryText)
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(width: 100)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(Color.cardBackground)
                .shadow(color: DesignTokens.Shadow.sm.color, radius: DesignTokens.Shadow.sm.radius, x: 0, y: DesignTokens.Shadow.sm.y)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .strokeBorder(stat.category.color.opacity(0.15), lineWidth: 1)
        )
        .scaleEffect(appeared ? 1 : 0.8)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(DesignTokens.Animation.standard.delay(Double.random(in: 0...0.2))) {
                appeared = true
            }
        }
    }
}

private struct SkeletonStatCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            SkeletonShape(width: 20, height: 12)
            SkeletonShape(width: 60, height: 22)
            SkeletonShape(width: 80, height: 10)
            SkeletonShape(width: 40, height: 10)
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(width: 100)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(Color.cardBackground)
        )
    }
}
