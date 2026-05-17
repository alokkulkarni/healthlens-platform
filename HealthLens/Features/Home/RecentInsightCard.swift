import SwiftUI

struct RecentInsightCard: View {
    let session: AnalysisSession
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                // Header
                HStack {
                    Label("Recent Analysis", systemImage: "sparkles")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondaryText)
                    Spacer()
                    Text(session.createdAt.formatted(.relative(presentation: .named)))
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(.tertiaryText)
                }

                // Query
                Text(session.queryText)
                    .font(DesignTokens.Typography.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primaryText)
                    .lineLimit(2)

                // Response preview
                if !session.responseText.isEmpty {
                    Text(session.responseText.prefix(120) + "…")
                        .font(DesignTokens.Typography.footnote)
                        .foregroundStyle(.secondaryText)
                        .lineLimit(3)
                }

                // Category badges + provider
                HStack(spacing: DesignTokens.Spacing.xs) {
                    ForEach(session.categories.prefix(3), id: \.rawValue) { category in
                        CategoryBadge(category: category)
                    }
                    Spacer()
                    if let provider = session.provider {
                        Text(provider.displayName.components(separatedBy: " ").first ?? "")
                            .font(DesignTokens.Typography.caption2)
                            .foregroundStyle(.tertiaryText)
                    }
                }
            }
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DesignTokens.Spacing.md)
    }
}

struct CategoryBadge: View {
    let category: HealthCategory

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: category.systemImage)
                .font(.system(size: 9))
            Text(category.displayName)
                .font(DesignTokens.Typography.caption2)
        }
        .foregroundStyle(category.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(category.color.opacity(0.12))
        .clipShape(Capsule())
    }
}
