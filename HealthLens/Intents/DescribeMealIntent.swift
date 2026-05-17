import AppIntents
import HealthKit
import SwiftUI

// MARK: - Describe Meal Intent

/// Lets users describe a meal to Siri, receive an AI-generated nutrition breakdown,
/// confirm it, and log it to Apple Health — all without opening the app.
struct DescribeMealIntent: AppIntent {
    static var title: LocalizedStringResource = "Describe a Meal"
    static var description = IntentDescription(
        "Tell Siri what you ate and get an AI nutrition summary, then log it to Apple Health.",
        categoryName: "Nutrition"
    )

    @Parameter(
        title: "Meal Description",
        description: "Describe the dish and its main ingredients",
        inputOptions: String.IntentInputOptions(
            capitalizationType: .sentences,
            multiline: true,
            autocorrect: true
        ),
        requestValueDialog: IntentDialog(
            "What did you eat? Describe the dish and main ingredients — for example: grilled chicken with brown rice and broccoli."
        )
    )
    var mealDescription: String

    func perform() async throws -> some ProvidesDialog & ShowsSnippetView {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw DescribeMealIntentError(message: "Apple Health is not available on this device.")
        }
        // Verify HealthKit write access is already granted (can't request from Siri context).
        let caloriesType = HKQuantityType(.dietaryEnergyConsumed)
        guard HKHealthStore().authorizationStatus(for: caloriesType) == .sharingAuthorized else {
            throw DescribeMealIntentError(
                message: "HealthLens doesn't have permission to write nutrition data. Open the app, go to Settings → Health Permissions and grant access, then try again."
            )
        }
        let keyStore = APIKeyStore()
        let (provider, modelID) = Self.bestAvailableProvider(keyStore: keyStore)

        let meal: ScannedMeal
        do {
            meal = try await FoodVisionService.shared.describeFood(
                text: mealDescription,
                provider: provider,
                modelID: modelID
            )
        } catch let error as FoodVisionError {
            switch error {
            case .missingAPIKey(let name):
                throw $mealDescription.needsValueError(
                    "No API key configured for \(name). Open HealthLens → Settings → AI Providers to add one."
                )
            case .emptyDescription:
                throw $mealDescription.needsValueError("Please describe what you ate.")
            default:
                throw DescribeMealIntentError(message: "Could not analyse meal: \(error.localizedDescription)")
            }
        } catch {
            throw DescribeMealIntentError(message: "Could not analyse meal: \(error.localizedDescription)")
        }

        // Show nutrition preview and ask the user to confirm before logging.
        try await requestConfirmation(
            result: .result(
                dialog: "Nutrition analysed. Log this to Apple Health?",
                view: NutritionSummarySnippetView(meal: meal, phase: .preview)
            )
        )

        // User confirmed — write directly to HealthKit (bypassing HealthKitWriter which
        // calls requestAuthorization and fails from Siri's background context).
        let samples = meal.toHealthKitSamples(at: Date())
        if !samples.isEmpty {
            try await HealthKitService.shared.saveSamples(samples)
        }
        var logged = meal
        logged.loggedToHealthKit = true
        await MainActor.run {
            MealLogStore.shared.add(logged)
        }

        return .result(
            dialog: "Meal logged to Apple Health.",
            view: NutritionSummarySnippetView(meal: logged, phase: .confirmed)
        )
    }

    private static func bestAvailableProvider(keyStore: APIKeyStore) -> (AIProviderType, String) {
        if keyStore.hasKey(for: .gemini)  { return (.gemini,  "gemini-2.5-flash") }
        if keyStore.hasKey(for: .claude)  { return (.claude,  "claude-3-5-haiku-20241022") }
        if keyStore.hasKey(for: .bedrock) { return (.bedrock, "amazon.nova-lite-v1:0") }
        return (.onDevice, "apple-foundation-model")
    }
}

// MARK: - Error type

private struct DescribeMealIntentError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Nutrition Summary Snippet View

enum NutritionSnippetPhase { case preview, confirmed }

struct NutritionSummarySnippetView: View {
    let meal: ScannedMeal
    let phase: NutritionSnippetPhase

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            macroGrid
            if phase == .confirmed {
                confirmedBadge
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: phase == .confirmed ? [.green, .mint] : [.orange, .yellow],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 38, height: 38)
                Image(systemName: phase == .confirmed ? "checkmark" : "fork.knife")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.foodName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(phase == .confirmed ? "Logged to Apple Health" : "Review before logging")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var macroGrid: some View {
        HStack(spacing: 0) {
            MacroCell(label: "Calories", value: "\(Int(meal.nutrition.calories))", unit: "kcal", color: .orange)
            MacroCell(label: "Protein",  value: "\(Int(meal.nutrition.protein))",  unit: "g",    color: .blue)
            MacroCell(label: "Carbs",    value: "\(Int(meal.nutrition.carbohydrates))", unit: "g", color: .yellow)
            MacroCell(label: "Fat",      value: "\(Int(meal.nutrition.fat))",       unit: "g",    color: .red)
        }
        .padding(.vertical, 6)
        .background(Color(.systemBackground).opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var confirmedBadge: some View {
        Label("Logged successfully", systemImage: "checkmark.circle.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.green)
            .frame(maxWidth: .infinity)
    }
}

private struct MacroCell: View {
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(color)
            Text(unit)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
