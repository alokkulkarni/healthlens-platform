import SwiftUI
import SwiftData

/// Root dependency container injected via SwiftUI environment.
@MainActor
@Observable
final class AppEnvironment {
    let healthKitService: HealthKitService
    let healthDataFetcher: HealthDataFetcher
    let apiKeyStore: APIKeyStore
    let aiRouter: AIServiceRouter
    let weatherService: WeatherContextService
    /// Single shared QueryViewModel so streaming persists across tab switches and
    /// navigation events (e.g., "Ask AI about my health" from the Insights screen).
    let queryViewModel: QueryViewModel

    init() {
        let hkService = HealthKitService.shared
        self.healthKitService = hkService
        self.healthDataFetcher = HealthDataFetcher(service: hkService)
        let sharedKeyStore = APIKeyStore()
        self.apiKeyStore = sharedKeyStore
        let router = AIServiceRouter(keyStore: sharedKeyStore)
        self.aiRouter = router
        self.weatherService = WeatherContextService.shared
        self.queryViewModel = QueryViewModel(
            aiRouter: router,
            fetcher: HealthDataFetcher(service: hkService)
        )
    }
}
