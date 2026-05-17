import SwiftUI
import UIKit

@MainActor
@Observable
final class FoodScanViewModel {
    enum ScanState: Equatable {
        case idle
        case scanning
        case confirming(ScannedMeal)
        case logging
        case success(ScannedMeal)
        case error(String)
    }

    var state: ScanState = .idle
    var userContext: String = ""
    var editableMeal: ScannedMeal?
    var mealDate: Date = Date()

    // Provider selection
    var selectedProvider: AIProviderType = .gemini
    var selectedModelID: String = "gemini-2.5-flash"
    var showProviderPicker = false

    var isLoading: Bool {
        if case .scanning = state { return true }
        if case .logging = state { return true }
        return false
    }

    private let keyStore = APIKeyStore()

    // All provider/model options for the nutrition picker
    var allProviderModels: [(AIProviderType, [AIModelDescriptor])] {
        [
            (.gemini, GeminiProvider(keyStore: keyStore).availableModels),
            (.claude, ClaudeProvider(keyStore: keyStore).availableModels),
            (.onDevice, OnDeviceProvider().availableModels),
            (.bedrock, BedrockProvider(keyStore: keyStore).availableModels),
        ]
    }

    func hasKey(for provider: AIProviderType) -> Bool {
        keyStore.hasKey(for: provider)
    }

    func setProvider(_ provider: AIProviderType, modelID: String) {
        selectedProvider = provider
        selectedModelID = modelID
        showProviderPicker = false
    }

    var selectedProviderLabel: String {
        let models = allProviderModels.first { $0.0 == selectedProvider }?.1 ?? []
        let modelName = models.first { $0.id == selectedModelID }?.shortName ?? selectedModelID
        return "\(selectedProvider.displayName.components(separatedBy: " ").first ?? "") · \(modelName)"
    }

    func scanImage(_ image: UIImage) async {
        state = .scanning
        do {
            let meal = try await FoodVisionService.shared.analyzeFood(
                image: image,
                userContext: userContext,
                provider: selectedProvider,
                modelID: selectedModelID
            )
            editableMeal = meal
            state = .confirming(meal)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func describeFood(_ description: String) async {
        state = .scanning
        do {
            let meal = try await FoodVisionService.shared.describeFood(
                text: description,
                provider: selectedProvider,
                modelID: selectedModelID
            )
            editableMeal = meal
            state = .confirming(meal)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func confirmAndLog(_ meal: ScannedMeal) async {
        state = .logging
        do {
            let logDate = mealDate
            try await HealthKitWriter.shared.logMeal(meal, at: logDate)
            var logged = meal
            logged.loggedToHealthKit = true
            editableMeal = logged
            state = .success(logged)
            MealLogStore.shared.add(logged)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func reset() {
        state = .idle
        userContext = ""
        editableMeal = nil
        mealDate = Date()
    }
}
