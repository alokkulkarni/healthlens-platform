import AppIntents
import HealthKit
import SwiftUI

struct LogWeightIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Body Weight"
    static var description = IntentDescription("Log your body weight to Apple Health")

    @Parameter(
        title: "Weight (kg)",
        description: "Your body weight in kilograms",
        requestValueDialog: "What is your weight in kilograms?"
    )
    var weightKG: Double

    func perform() async throws -> some ProvidesDialog & ShowsSnippetView {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw LogWeightIntentError(message: "Apple Health is not available on this device.")
        }
        guard weightKG > 0 else {
            throw $weightKG.needsValueError("Please enter a positive weight value.")
        }
        let weightType = HKQuantityType(.bodyMass)
        guard HKHealthStore().authorizationStatus(for: weightType) == .sharingAuthorized else {
            throw LogWeightIntentError(
                message: "HealthLens doesn't have permission to write weight data. Open the app, go to Settings → Siri & Shortcuts and tap 'Grant HealthKit Access', then try again."
            )
        }
        let loggedAt = Date()
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: weightKG)
        let sample = HKQuantitySample(type: weightType, quantity: quantity, start: loggedAt, end: loggedAt)
        try await HealthKitService.shared.saveSamples([sample])
        return .result(
            dialog: "Logged \(String(format: "%.1f", weightKG)) kg to Apple Health.",
            view: WeightLoggedView(weightKG: weightKG)
        )
    }
}

private struct LogWeightIntentError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct WeightLoggedView: View {
    let weightKG: Double
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "scalemass.fill").foregroundStyle(.purple)
            Text("\(String(format: "%.1f", weightKG)) kg logged")
                .font(.system(size: 15, weight: .medium))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
}
