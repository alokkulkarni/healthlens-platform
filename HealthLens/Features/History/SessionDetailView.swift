import SwiftUI
import SwiftData

struct SessionDetailView: View {
    let sessionID: UUID

    @Query private var sessions: [AnalysisSession]
    @Environment(\.modelContext) private var modelContext

    private var session: AnalysisSession? {
        sessions.first { $0.id == sessionID }
    }

    var body: some View {
        Group {
            if let session {
                SessionDetailContent(session: session)
            } else {
                ContentUnavailableView(
                    "Session not found",
                    systemImage: "exclamationmark.magnifyingglass",
                    description: Text("This analysis session may have been deleted.")
                )
            }
        }
        .navigationTitle("Analysis Detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SessionDetailContent: View {
    let session: AnalysisSession
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var router

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                // Session metadata card
                metadataCard

                // Full analysis result
                AnalysisResultView(session: session, isStreaming: false)

                Spacer(minLength: DesignTokens.Spacing.xxl)
            }
            .padding(.top, DesignTokens.Spacing.sm)
        }
        .background(Color.primaryBackground)
        .safeAreaInset(edge: .bottom) {
            // "Continue Conversation" sticky bar
            Button {
                triggerHaptic(.medium)
                router.continueSession(session)
            } label: {
                Label("Continue Conversation", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(DesignTokens.Typography.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.bottom, DesignTokens.Spacing.sm)
            .background(Color.primaryBackground)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Continue Conversation", systemImage: "bubble.left.and.bubble.right") {
                        router.continueSession(session)
                    }
                    Button(session.isFavorited ? "Unfavorite" : "Favorite", systemImage: session.isFavorited ? "star.slash" : "star") {
                        session.isFavorited.toggle()
                        try? modelContext.save()
                    }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        modelContext.delete(session)
                        try? modelContext.save()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Analysis Session")
                .font(DesignTokens.Typography.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.secondaryText)

            HStack {
                metaItem(label: "Provider", value: session.provider?.displayName ?? "Unknown", icon: "brain.head.profile")
                Divider().frame(height: 30)
                metaItem(label: "Model", value: session.providerModel.components(separatedBy: "-").prefix(2).joined(separator: " "), icon: "cpu")
                Divider().frame(height: 30)
                metaItem(label: "Tokens", value: "\(session.inputTokens + session.outputTokens)", icon: "number")
            }

            if let snapshot = session.snapshot {
                HStack {
                    Image(systemName: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.secondaryText)
                    Text(snapshot.formattedDateRange)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondaryText)
                    Spacer()
                    Text(session.formattedDate)
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(.tertiaryText)
                }
            }
        }
        .card()
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    private func metaItem(label: String, value: String, icon: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondaryText)
            Text(value)
                .font(DesignTokens.Typography.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(.tertiaryText)
        }
        .frame(maxWidth: .infinity)
    }
}
