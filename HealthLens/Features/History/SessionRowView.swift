import SwiftUI

struct SessionRowView: View {
    let session: AnalysisSession
    var onTap: () -> Void = {}
    var onFavorite: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                HStack(alignment: .top) {
                    // Provider icon
                    if let provider = session.provider {
                        Image(systemName: provider.systemImage)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 20)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.queryText)
                            .font(DesignTokens.Typography.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primaryText)
                            .lineLimit(2)
                        Text(session.formattedDate)
                            .font(DesignTokens.Typography.caption2)
                            .foregroundStyle(.tertiaryText)
                    }

                    Spacer()

                    // Favorite toggle
                    Button(action: onFavorite) {
                        Image(systemName: session.isFavorited ? "star.fill" : "star")
                            .font(.caption)
                            .foregroundStyle(session.isFavorited ? .yellow : .fillTertiary)
                    }
                    .buttonStyle(.plain)
                }

                // Response preview
                if !session.responseText.isEmpty {
                    Text(session.responseText.prefix(100))
                        .font(DesignTokens.Typography.footnote)
                        .foregroundStyle(.secondaryText)
                        .lineLimit(2)
                }

                // Category badges
                if !session.categories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(session.categories.prefix(4), id: \.rawValue) { cat in
                                CategoryBadge(category: cat)
                            }
                            if session.inputTokens + session.outputTokens > 0 {
                                Spacer()
                                Text("\(session.inputTokens + session.outputTokens) tokens")
                                    .font(DesignTokens.Typography.caption2)
                                    .foregroundStyle(.tertiaryText)
                            }
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.md)
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
