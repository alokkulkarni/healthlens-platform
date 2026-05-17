import AppIntents
import SwiftUI

// MARK: - Scan Meal Intent

/// Launches the HealthLens camera meal-scanner directly from Siri.
///
/// Because camera access requires a foreground UI, this intent uses
/// `openAppWhenRun = true` to bring the app to the front and
/// a `UserDefaults` flag so the app knows to present `FoodScanView` immediately.
struct ScanMealIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan a Meal"
    static var description = IntentDescription(
        "Opens HealthLens camera to take a photo of your meal and log its nutrition to Apple Health.",
        categoryName: "Nutrition"
    )

    /// Always open the app — camera cannot be used from within Siri.
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some ProvidesDialog {
        // Signal to the app that it should immediately present the food-scan sheet.
        UserDefaults.standard.set(true, forKey: ScanMealIntent.pendingKey)
        return .result(
            dialog: "Opening HealthLens to scan your meal. Point the camera at your food and tap Analyse."
        )
    }

    // MARK: - Shared constant

    /// UserDefaults key used to communicate between the intent and the app.
    static let pendingKey = "com.healthlens.pendingFoodScan"
}

// MARK: - Scan Meal Tip View (used in Siri tips & Settings)

/// A compact description card shown in Siri tip surfaces.
struct ScanMealTipView: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.orange, .orange.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Scan a Meal")
                    .font(.system(size: 13, weight: .semibold))
                Text("Opens camera to log meal nutrition")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
