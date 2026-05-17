import SwiftUI
import SwiftData

struct QueryView: View {
    var initialQuery: String? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(NavigationRouter.self) private var router
    @FocusState private var inputFocused: Bool
    @State private var didSubmitInitial = false

    private var viewModel: QueryViewModel { appEnv.queryViewModel }

    var body: some View {
        QueryContent(viewModel: viewModel, inputFocused: _inputFocused)
            .onAppear {
                viewModel.setContext(modelContext)
                if let initial = initialQuery, !initial.isEmpty, !didSubmitInitial {
                    didSubmitInitial = true
                    viewModel.queryText = initial
                    Task { await viewModel.submitQuery() }
                }
                if let session = router.querySessionToLoad {
                    viewModel.loadExistingSession(session)
                    router.querySessionToLoad = nil
                }
            }
            .onChange(of: router.querySessionToLoad) { _, session in
                guard let session else { return }
                viewModel.loadExistingSession(session)
                router.querySessionToLoad = nil
            }
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct QueryContent: View {
    let viewModel: QueryViewModel
    @FocusState var inputFocused: Bool
    @Environment(\.modelContext) private var modelContext
    @State private var showProviderSheet = false

    var body: some View {
        VStack(spacing: 0) {
            providerToolbar
            Divider()

            ScrollViewReader { proxy in
                ScrollView {

                    // Regular VStack — all items always rendered so scrollTo is reliable.
                    VStack(spacing: 0) {
                        if viewModel.conversationSessions.isEmpty && !viewModel.isLoading {
                            emptyStateView
                        }

                        ForEach(Array(viewModel.conversationSessions.enumerated()), id: \.element.id) { index, session in
                            let isLatest = index == viewModel.conversationSessions.count - 1
                            AnalysisResultView(
                                session: session,
                                liveRecords: viewModel.liveRecords,
                                isStreaming: session.isStreaming,
                                isLatestInConversation: isLatest
                            ) { followUpText in
                                viewModel.queryText = followUpText
                                Task { await viewModel.submitQuery() }
                            }
                        }

                        // Thinking indicator shown while fetching, before streaming begins.
                        if viewModel.isLoading && (viewModel.currentSession == nil || !viewModel.currentSession!.isStreaming) {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 24, height: 24)
                                    .background(Color.accentColor.opacity(0.1))
                                    .clipShape(Circle())
                                ThinkingDotsView()
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }

                        if let error = viewModel.error {
                            errorBanner(error)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                        }

                        // Bottom anchor — always at the end, always rendered.
                        Color.clear.frame(height: 8).id("chat-bottom")
                    }
                    .padding(.bottom, DesignTokens.Spacing.xs)
                }
                .scrollDismissesKeyboard(.interactively)
                // When a new query is submitted, scroll to bottom so the user
                // message + loading dots are immediately visible.
                .onChange(of: viewModel.isLoading) { _, loading in
                    guard loading else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("chat-bottom", anchor: .bottom)
                        }
                    }
                }
                // Keep scrolled to bottom while the response streams in.
                .onChange(of: viewModel.currentSession?.responseText) { _, _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("chat-bottom", anchor: .bottom)
                    }
                }
            }

            QueryInputBar(
                text: Binding(get: { viewModel.queryText }, set: { viewModel.queryText = $0 }),
                isLoading: viewModel.isLoading,
                activeProvider: viewModel.activeProvider,
                activeModel: viewModel.activeModelID,
                onSubmit: { Task { await viewModel.submitQuery() } },
                onProviderTap: { showProviderSheet = true }
            )
        }
        .background(Color.primaryBackground)
        .sheet(isPresented: $showProviderSheet) {
            ProviderPickerSheet(viewModel: viewModel)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Provider toolbar

    private var providerToolbar: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            // Expertise level picker
            Menu {
                ForEach(HealthExpertiseLevel.allCases, id: \.self) { level in
                    Button {
                        viewModel.expertiseLevel = level
                    } label: {
                        Label(level.displayName, systemImage: level.systemImage)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.expertiseLevel.systemImage).font(.caption)
                    Text(viewModel.expertiseLevel.displayName)
                        .font(DesignTokens.Typography.footnote).fontWeight(.medium)
                }
                .foregroundStyle(.secondaryText)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.fillTertiary).clipShape(Capsule())
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: viewModel.activeProvider.systemImage).font(.system(size: 11))
                Text(viewModel.activeModelID.components(separatedBy: "-").prefix(2).joined(separator: " "))
                    .font(DesignTokens.Typography.caption)
            }
            .foregroundStyle(.secondaryText)

            if viewModel.hasActiveConversation {
                Button {
                    triggerHaptic(.warning)
                    viewModel.startNewConversation()
                } label: {
                    Label("New", systemImage: "plus.bubble")
                        .font(DesignTokens.Typography.caption)
                        .labelStyle(.titleAndIcon)
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Capsule())
            }

            if viewModel.isLoading {
                Button("Stop") {
                    triggerHaptic(.warning)
                    viewModel.cancelStream()
                }
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.red)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.red.opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(Color.primaryBackground)
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            VStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(colors: [.accentColor, .purple],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Text("Ask about your health")
                    .font(DesignTokens.Typography.title3).foregroundStyle(.primaryText)
                Text("Type a question below or tap a suggestion")
                    .font(DesignTokens.Typography.subheadline).foregroundStyle(.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, DesignTokens.Spacing.xl)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text("Suggested Questions")
                    .font(DesignTokens.Typography.footnote).fontWeight(.semibold)
                    .foregroundStyle(.secondaryText)
                    .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        ForEach(QuerySuggestions.general, id: \.self) { suggestion in
                            SuggestedQueryChip(text: suggestion) { text in
                                viewModel.queryText = text
                                Task { await viewModel.submitQuery() }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        ForEach(HealthCategory.allCases.prefix(4), id: \.rawValue) { category in
                            ForEach(QuerySuggestions.byCategory[category]?.prefix(1) ?? [], id: \.self) { suggestion in
                                SuggestedQueryChip(text: suggestion) { text in
                                    viewModel.queryText = text
                                    Task { await viewModel.submitQuery() }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text(message).font(DesignTokens.Typography.footnote).foregroundStyle(.primaryText)
            Spacer()
            Button { viewModel.error = nil } label: {
                Image(systemName: "xmark").font(.caption).foregroundStyle(.secondaryText)
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .background(Color.healthCritical.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
    }
}

// MARK: - Model row label (extracted to help type-checker)

private struct ModelRowLabel: View {
    let model: AIModelDescriptor
    let isActive: Bool
    let needsKey: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(Color.primaryText)
                Text(contextLabel)
                    .font(DesignTokens.Typography.caption2)
                    .foregroundStyle(Color.tertiaryText)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
            if needsKey {
                Image(systemName: "key.slash")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
            }
        }
    }

    private var contextLabel: String {
        let k = model.contextWindow / 1000
        return "\(k)K context"
    }
}

// MARK: - Provider Picker Sheet

private struct ProviderPickerSheet: View {
    let viewModel: QueryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(AIProviderType.allCases, id: \.self) { provider in
                    Section(provider.displayName) {
                        ForEach(viewModel.availableModelsFor(provider)) { model in
                            Button {
                                triggerHaptic(.selection)
                                viewModel.setProvider(provider, modelID: model.id)
                                dismiss()
                            } label: {
                                ModelRowLabel(
                                    model: model,
                                    isActive: model.id == viewModel.activeModelID,
                                    needsKey: !model.isOnDevice && !viewModel.hasKey(for: provider)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Choose Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private extension QueryViewModel {
    func availableModelsFor(_ provider: AIProviderType) -> [AIModelDescriptor] {
        aiRouter.allProviderModels.first { $0.0 == provider }?.1 ?? []
    }

    func hasKey(for provider: AIProviderType) -> Bool {
        aiRouter.hasKeyConfigured(for: provider)
    }
}
