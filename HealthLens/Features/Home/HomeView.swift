import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(NavigationRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    @State private var viewModel = HomeViewModel()
    @State private var waterRefreshToken: Int = 0
    // Owned here so the view model (and its currentStep) survive iOS dismissing
    // the sheet when a system dialog (location/health) appears over it.
    @State private var onboardingVM: OnboardingViewModel?
    @Query(
        sort: \AnalysisSession.createdAt,
        order: .reverse
    ) private var recentSessions: [AnalysisSession]
    @Query private var prefsList: [UserPreferences]

    private var prefs: UserPreferences? { prefsList.first }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: DesignTokens.Spacing.md) {
                // Invisible anchor — used to snap back after pull-to-refresh
                Color.clear.frame(height: 0).id("homeTop")

                // Daily summary card
                DailySummaryCard(
                    stats: viewModel.todayStats,
                    isLoading: viewModel.isLoadingStats
                )

                // Quick stats horizontal scroll
                if !viewModel.todayStats.isEmpty || viewModel.isLoadingStats {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                        Text("Today")
                            .font(DesignTokens.Typography.headline)
                            .padding(.horizontal, DesignTokens.Spacing.md)
                        QuickStatsRow(
                            stats: viewModel.todayStats,
                            isLoading: viewModel.isLoadingStats
                        )
                    }
                }

                // Water intake circular card
                waterSection

                // Ask health question CTA
                queryPromptCard

                // Recent sessions
                if !recentSessions.isEmpty {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        HStack {
                            Text("Recent Insights")
                                .font(DesignTokens.Typography.headline)
                            Spacer()
                            Button("See All") {
                                router.selectedTab = .query
                            }
                            .font(DesignTokens.Typography.subheadline)
                        }
                        .padding(.horizontal, DesignTokens.Spacing.md)

                        ForEach(recentSessions.prefix(3)) { session in
                            RecentInsightCard(session: session) {
                                router.continueSession(session)
                            }
                        }
                    }
                }

                Spacer(minLength: DesignTokens.Spacing.xxl)
            }
            .padding(.top, DesignTokens.Spacing.sm)
        }
        .refreshable {
            await viewModel.loadTodayStats()
            waterRefreshToken += 1
            // Explicitly snap back to top — prevents scroll view sticking after
            // content-height changes caused by the loading-state toggle.
            withAnimation { proxy.scrollTo("homeTop", anchor: .top) }
        }
        .background(Color.primaryBackground)
        .navigationTitle("HealthLens")
        .navigationBarTitleDisplayMode(.large)
        .task {
            // Only load health data after onboarding is done; loading it before
            // triggers HealthKit/WaterIntakeCard which shows permission dialogs
            // that conflict with the onboarding flow.
            guard prefs?.hasCompletedOnboarding == true else { return }
            await viewModel.loadTodayStats()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, prefs?.hasCompletedOnboarding == true else { return }
            Task { await viewModel.loadTodayStats() }
            waterRefreshToken += 1
        }
        .sheet(isPresented: $viewModel.showOnboarding) {
            if let vm = onboardingVM {
                OnboardingView(viewModel: vm) {
                    viewModel.showOnboarding = false
                }
                .interactiveDismissDisabled()
            }
        }
        .onAppear {
            viewModel.checkOnboardingStatus(prefs: prefs)
            // Lazily create the view model — only once per onboarding session.
            if viewModel.showOnboarding && onboardingVM == nil {
                onboardingVM = OnboardingViewModel(modelContext: modelContext)
            }
        }
        } // ScrollViewReader
    }

    // MARK: - Water Section

    private var waterSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack {
                Text("Hydration")
                    .font(DesignTokens.Typography.headline)
                Spacer()
                Button {
                    router.selectedTab = .nutritionLog
                } label: {
                    Text("Log Water")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(Color.blue)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)

            WaterIntakeCard(refreshToken: waterRefreshToken)
                .padding(.horizontal, DesignTokens.Spacing.md)
        }
    }

    private var queryPromptCard: some View {
        Button {
            triggerHaptic(.medium)
            router.selectedTab = .query
        } label: {
            HStack(spacing: DesignTokens.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 44, height: 44)
                    Image(systemName: "waveform.badge.mic")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask about your health")
                        .font(DesignTokens.Typography.headline)
                        .foregroundStyle(.primaryText)
                    Text("e.g. 'How has my sleep improved this month?'")
                        .font(DesignTokens.Typography.footnote)
                        .foregroundStyle(.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiaryText)
            }
            .card()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DesignTokens.Spacing.md)
    }
}
