import SwiftUI

struct RootTabView: View {
    @State private var router = NavigationRouter()
    @State private var appEnv = AppEnvironment()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $router.selectedTab) {
            // Home
            NavigationStack(path: $router.homePath) {
                HomeView()
                    .navigationDestination(for: AppDestination.self) { dest in
                        destinationView(dest)
                    }
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(AppTab.home)

            // Insights
            NavigationStack(path: $router.insightsPath) {
                InsightsView()
                    .navigationDestination(for: AppDestination.self) { dest in
                        destinationView(dest)
                    }
            }
            .tabItem {
                Label("Insights", systemImage: "chart.xyaxis.line")
            }
            .tag(AppTab.insights)

            // Nutrition Log (center tab)
            NavigationStack(path: $router.nutritionLogPath) {
                NutritionLogTabView()
                    .navigationDestination(for: AppDestination.self) { dest in
                        destinationView(dest)
                    }
            }
            .tabItem {
                Label("Log", systemImage: "fork.knife")
            }
            .tag(AppTab.nutritionLog)

            // Ask / Query
            NavigationStack(path: $router.queryPath) {
                QueryView()
                    .navigationDestination(for: AppDestination.self) { dest in
                        destinationView(dest)
                    }
            }
            .tabItem {
                Label("Ask", systemImage: "waveform.badge.mic")
            }
            .tag(AppTab.query)

            // Settings
            NavigationStack(path: $router.settingsPath) {
                SettingsView()
                    .navigationDestination(for: AppDestination.self) { dest in
                        destinationView(dest)
                    }
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(AppTab.settings)
        }
        .environment(router)
        .environment(appEnv)
        .tint(.accentColor)
        .task {
            // Ensure HealthKit write access for Siri intents is granted.
            // Runs silently — HealthKit only shows a permission sheet for
            // types that are still `.notDetermined` (i.e., never asked before).
            // Existing users upgrading from a read-only build are prompted here
            // on their first launch of the new version.
            await HealthKitService.shared.ensureSiriWriteTypes()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                handlePendingIntentActions()
            }
        }
    }

    // MARK: - Intent Deep-Link Handling

    /// Called every time the app becomes active.
    /// Checks for a pending `ScanMealIntent` request stored in UserDefaults
    /// and routes to the Nutrition Log tab with the scan sheet open.
    private func handlePendingIntentActions() {
        if UserDefaults.standard.bool(forKey: ScanMealIntent.pendingKey) {
            UserDefaults.standard.removeObject(forKey: ScanMealIntent.pendingKey)
            router.selectedTab = .nutritionLog
            // Small delay lets the tab switch animate before the sheet appears.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                router.showFoodScanFromIntent = true
            }
        }
    }

    // MARK: - Destination Views

    @ViewBuilder
    private func destinationView(_ destination: AppDestination) -> some View {
        switch destination {
        case .sessionDetail(let id):
            SessionDetailView(sessionID: id)
        case .categoryInsights(let category):
            CategoryInsightCard(category: category, isExpanded: true)
        case .providerSettings(let provider):
            AIProviderRow(provider: provider)
        case .queryWithSuggestion(let suggestion):
            QueryView(initialQuery: suggestion)
        case .foodScan:
            FoodScanView()
        case .nutritionLog:
            NutritionLogTabView()
        }
    }
}
