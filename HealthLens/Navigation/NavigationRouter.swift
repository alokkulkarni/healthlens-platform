import SwiftUI

enum AppTab: Int, Hashable {
    case home = 0
    case insights = 1
    case nutritionLog = 2
    case query = 3
    case settings = 4
}

enum AppDestination: Hashable {
    case sessionDetail(sessionID: UUID)
    case categoryInsights(category: HealthCategory)
    case providerSettings(provider: AIProviderType)
    case queryWithSuggestion(String)
    case foodScan
    case nutritionLog
}

@MainActor
@Observable
final class NavigationRouter {
    var selectedTab: AppTab = .home
    var homePath = NavigationPath()
    var insightsPath = NavigationPath()
    var nutritionLogPath = NavigationPath()
    var queryPath = NavigationPath()
    var settingsPath = NavigationPath()

    /// When set, QueryView will load this session and clear the field.
    var querySessionToLoad: AnalysisSession? = nil

    /// Set by `ScanMealIntent` (via `RootTabView`) to trigger the food-scan sheet.
    var showFoodScanFromIntent: Bool = false

    func navigate(to destination: AppDestination, in tab: AppTab) {
        selectedTab = tab
        switch tab {
        case .home:         homePath.append(destination)
        case .insights:     insightsPath.append(destination)
        case .nutritionLog: nutritionLogPath.append(destination)
        case .query:        queryPath.append(destination)
        case .settings:     settingsPath.append(destination)
        }
    }

    func openQuery(with suggestion: String) {
        selectedTab = .query
        queryPath.append(AppDestination.queryWithSuggestion(suggestion))
    }

    func continueSession(_ session: AnalysisSession) {
        querySessionToLoad = session
        selectedTab = .query
    }

    func openSession(_ id: UUID) {
        selectedTab = .query
        queryPath.append(AppDestination.sessionDetail(sessionID: id))
    }

    func popToRoot(tab: AppTab) {
        switch tab {
        case .home:         homePath = NavigationPath()
        case .insights:     insightsPath = NavigationPath()
        case .nutritionLog: nutritionLogPath = NavigationPath()
        case .query:        queryPath = NavigationPath()
        case .settings:     settingsPath = NavigationPath()
        }
    }
}
