import SwiftUI
import SwiftData
import CoreLocation

@MainActor
@Observable
final class OnboardingViewModel: NSObject {
    var currentStep: Int = 0
    var stepForward: Bool = true    // used to drive slide-direction transitions
    var isRequestingPermissions: Bool = false
    var permissionError: String?
    var isRequestingLocation: Bool = false
    var isComplete: Bool = false

    /// Steps: 0=Dashboard, 1=AskAI, 2=Insights, 3=SiriShortcuts, 4=Health, 5=Location, 6=Disclaimer, 7=Provider
    let totalSteps = 8

    private let healthKitService: HealthKitService
    private let modelContext: ModelContext
    private var locationManager: CLLocationManager?
    private var locationContinuation: CheckedContinuation<Void, Never>?

    init(healthKitService: HealthKitService = .shared, modelContext: ModelContext) {
        self.healthKitService = healthKitService
        self.modelContext = modelContext
        super.init()
    }

    func nextStep() {
        guard currentStep < totalSteps - 1 else { return }
        stepForward = true
        currentStep += 1
    }

    func jumpTo(_ step: Int) {
        guard step >= 0, step < totalSteps else { return }
        stepForward = step > currentStep
        currentStep = step
    }

    func requestHealthPermissions() async {
        isRequestingPermissions = true
        permissionError = nil
        do {
            let allNonSensitive = HealthKitPermissions.categories(upToTier: 0)
            try await healthKitService.requestAuthorization(for: allNonSensitive)
            let prefs = UserPreferences.fetch(in: modelContext)
            for category in allNonSensitive {
                prefs.markCategoryGranted(category)
            }
            try? modelContext.save()
            nextStep()
        } catch {
            permissionError = "Could not access Health data. You can grant permission later in Settings."
            nextStep()
        }
        isRequestingPermissions = false
    }

    func requestLocationPermission() async {
        isRequestingLocation = true
        let manager = CLLocationManager()
        locationManager = manager

        let status = manager.authorizationStatus
        if status == .notDetermined {
            // Set delegate AFTER checking current status to avoid the delegate
            // firing synchronously with .notDetermined and prematurely resuming.
            await withCheckedContinuation { continuation in
                locationContinuation = continuation
                manager.delegate = self          // delegate set INSIDE the continuation closure
                manager.requestWhenInUseAuthorization()
            }
        }
        isRequestingLocation = false
        nextStep()
    }

    func completeOnboarding() {
        let prefs = UserPreferences.fetch(in: modelContext)
        prefs.hasCompletedOnboarding = true
        try? modelContext.save()
        isComplete = true
    }
}

// MARK: - CLLocationManagerDelegate
extension OnboardingViewModel: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Guard against the immediate .notDetermined callback that iOS fires when
        // the delegate is first assigned — only resume when the user has actually decided.
        guard manager.authorizationStatus != .notDetermined else { return }
        Task { @MainActor in
            locationContinuation?.resume()
            locationContinuation = nil
        }
    }
}
