import AppIntents
import HealthKit
import SwiftUI

struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Water Intake"
    static var description = IntentDescription(
        "Log how much water you drank to Apple Health.",
        categoryName: "Hydration"
    )

    // No default — Siri must always ask and receive the amount from the user's
    // spoken reply. App Intents phrase tokens only accept AppEntity/AppEnum;
    // primitive types (Double, String) cannot appear in shortcut phrases.
    @Parameter(
        title: "Amount (ml)",
        description: "Amount of water in millilitres",
        requestValueDialog: IntentDialog("How many millilitres of water did you drink?")
    )
    var amountML: Double

    func perform() async throws -> some ProvidesDialog & ShowsSnippetView {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw LogWaterIntentError(message: "Apple Health is not available on this device.")
        }
        guard amountML > 0 else {
            throw $amountML.needsValueError("Please enter a positive amount of water.")
        }
        let waterType = HKQuantityType(.dietaryWater)
        guard HKHealthStore().authorizationStatus(for: waterType) == .sharingAuthorized else {
            throw LogWaterIntentError(
                message: "HealthLens doesn't have permission to write water data. Open the app, go to Settings → Siri & Shortcuts and tap 'Grant HealthKit Access', then try again."
            )
        }
        let loggedAt = Date()
        let quantity = HKQuantity(unit: .liter(), doubleValue: amountML / 1000.0)
        let sample = HKQuantitySample(type: waterType, quantity: quantity, start: loggedAt, end: loggedAt)
        try await HealthKitService.shared.saveSamples([sample])
        return .result(
            dialog: "\(Int(amountML)) ml of water logged to Apple Health.",
            view: WaterLoggedView(amountML: amountML, loggedAt: loggedAt)
        )
    }
}

private struct LogWaterIntentError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct WaterLoggedView: View {
    let amountML: Double
    let loggedAt: Date

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 40, height: 40)
                Image(systemName: "drop.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(amountML)) ml logged")
                    .font(.system(size: 15, weight: .semibold))
                Label(loggedAt.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.green)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
