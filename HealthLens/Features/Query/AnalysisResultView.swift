import SwiftUI

struct AnalysisResultView: View {
    let session: AnalysisSession
    var liveRecords: [SerializedHealthRecord] = []
    var isStreaming: Bool = false
    /// When false (older message in a conversation), follow-up chips are hidden.
    var isLatestInConversation: Bool = true
    /// Called when the user taps a follow-up suggestion chip.
    var onFollowUp: (String) -> Void = { _ in }

    private let parser = ResponseParser()

    private var parsed: ParsedAIResponse {
        parser.parse(session.responseText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── User message ─────────────────────────────────────────────────
            userMessageRow

            // ── AI response ──────────────────────────────────────────────────
            aiResponseRow

            // ── Clinical warning ─────────────────────────────────────────────
            if parsed.hasClinicalWarning {
                clinicalWarningBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }

            // ── Follow-up chips (latest exchange only) ────────────────────────
            if isLatestInConversation && !isStreaming && !parsed.suggestedFollowUps.isEmpty {
                followUpSection
                    .padding(.top, 10)
            }

            // ── Metadata footer ───────────────────────────────────────────────
            if !isStreaming {
                metadataRow
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
            }

            // Thin divider between exchanges
            Divider()
                .padding(.top, 12)
                .padding(.horizontal, 16)
        }
    }

    // MARK: - User message row

    private var userMessageRow: some View {
        HStack(alignment: .top) {
            Spacer(minLength: 56)
            Text(session.queryText)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(.primaryText)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(Color.accentColor.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = session.queryText
                        triggerHaptic(.light)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: - AI response row

    private var aiResponseRow: some View {
        HStack(alignment: .top, spacing: 10) {
            // Small sparkle icon — acts as the AI avatar
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Circle())
                .padding(.top, 2)
                .flexibleFrame(alignment: .top)

            VStack(alignment: .leading, spacing: 6) {
                if session.responseText.isEmpty && isStreaming {
                    ThinkingDotsView()
                        .padding(.top, 2)
                } else {
                    MarkdownResponseView(
                        text: session.responseText,
                        isStreaming: isStreaming
                    )
                }

                if !session.responseText.isEmpty && !isStreaming {
                    Button {
                        UIPasteboard.general.string = session.responseText
                        triggerHaptic(.success)
                    } label: {
                        Label("Copy response", systemImage: "doc.on.doc")
                            .font(DesignTokens.Typography.caption2)
                            .foregroundStyle(.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Note: no .contextMenu here — it would intercept the long-press gesture
            // that iOS uses to activate text selection on the Text views inside.
            // The "Copy response" button above handles whole-response copying.
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    // MARK: - Clinical warning

    private var clinicalWarningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "stethoscope").foregroundStyle(.orange).font(.body)
            Text("Informational only — not medical advice. Consult a healthcare professional.")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondaryText)
        }
        .padding(10)
        .background(Color.healthWarning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
    }

    // MARK: - Follow-up chips

    private var followUpSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Follow-up")
                .font(DesignTokens.Typography.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiaryText)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(parsed.suggestedFollowUps, id: \.self) { followUp in
                        SuggestedQueryChip(text: followUp) { text in
                            onFollowUp(text)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Metadata

    private var metadataRow: some View {
        HStack(spacing: 6) {
            if let provider = session.provider {
                Image(systemName: provider.systemImage)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiaryText)
                Text(provider.displayName.components(separatedBy: " ").first ?? "")
                    .font(DesignTokens.Typography.caption2)
                    .foregroundStyle(.tertiaryText)
                Text("·").foregroundStyle(Color.tertiaryText)
            }
            Text("\(session.inputTokens + session.outputTokens) tok")
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(.tertiaryText)
            Text("·").foregroundStyle(Color.tertiaryText)
            Text(String(format: "%.1fs", session.latencyMS / 1000))
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(.tertiaryText)
            Spacer()
            Button {
                session.isFavorited.toggle()
                triggerHaptic(.light)
            } label: {
                Image(systemName: session.isFavorited ? "star.fill" : "star")
                    .font(.caption2)
                    .foregroundStyle(session.isFavorited ? Color.yellow : Color.tertiaryText)
            }
            .buttonStyle(.plain)
        }
    }
}

// Small helper so the AI icon doesn't stretch vertically inside HStack.
private extension View {
    func flexibleFrame(alignment: Alignment = .center) -> some View {
        self.fixedSize()
    }
}

