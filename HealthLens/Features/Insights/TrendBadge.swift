import SwiftUI

enum TrendDirection: String {
    case improving = "improving"
    case declining = "declining"
    case stable    = "stable"
    case unknown   = "unknown"

    var label: String {
        switch self {
        case .improving: return "Improving"
        case .declining: return "Declining"
        case .stable:    return "Stable"
        case .unknown:   return "No data"
        }
    }

    var icon: String {
        switch self {
        case .improving: return "arrow.up.right"
        case .declining: return "arrow.down.right"
        case .stable:    return "arrow.right"
        case .unknown:   return "minus"
        }
    }

    var color: Color {
        switch self {
        case .improving: return .healthGood
        case .declining: return .healthCritical
        case .stable:    return .healthNeutral
        case .unknown:   return .secondary
        }
    }
}

struct TrendBadge: View {
    let trend: TrendDirection
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: trend.icon)
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
            if !compact {
                Text(trend.label)
                    .font(DesignTokens.Typography.caption2)
                    .fontWeight(.medium)
            }
        }
        .foregroundStyle(trend.color)
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, compact ? 2 : 4)
        .background(trend.color.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Trend calculation helper

struct TrendCalculator {
    static func calculate(from dataPoints: [HealthDataPoint]) -> TrendDirection {
        guard dataPoints.count >= 7 else { return .unknown }
        let sorted = dataPoints.sorted { $0.timestamp < $1.timestamp }
        let half = sorted.count / 2
        let firstHalf = sorted.prefix(half).map(\.value)
        let secondHalf = sorted.suffix(half).map(\.value)
        let firstAvg = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let secondAvg = secondHalf.reduce(0, +) / Double(secondHalf.count)
        let changePct = firstAvg > 0 ? (secondAvg - firstAvg) / firstAvg : 0
        if changePct > 0.05  { return .improving }
        if changePct < -0.05 { return .declining }
        return .stable
    }
}
