import AppIntents

struct HealthLensShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Phrase tokens only work with AppEntity/AppEnum parameters — not primitives
        // (Double, String, Int). Plain phrases are used; Siri asks for values
        // via requestValueDialog when not provided in the initial utterance.
        AppShortcut(
            intent: LogWaterIntent(),
            phrases: [
                "Log water in \(.applicationName)",
                "Add water to \(.applicationName)",
                "I drank water in \(.applicationName)",
                "Track water intake in \(.applicationName)",
            ],
            shortTitle: "Log Water",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: LogWeightIntent(),
            phrases: [
                "Log my weight in \(.applicationName)",
                "Record weight in \(.applicationName)",
                "Add weight to \(.applicationName)",
                "Track my weight in \(.applicationName)",
            ],
            shortTitle: "Log Weight",
            systemImageName: "scalemass.fill"
        )
        AppShortcut(
            intent: DescribeMealIntent(),
            phrases: [
                "Describe a meal in \(.applicationName)",
                "Log what I ate in \(.applicationName)",
                "Tell \(.applicationName) what I ate",
                "I just ate in \(.applicationName)",
                "Log my meal in \(.applicationName)",
            ],
            shortTitle: "Describe Meal",
            systemImageName: "text.bubble.fill"
        )
        AppShortcut(
            intent: ScanMealIntent(),
            phrases: [
                "Scan a meal in \(.applicationName)",
                "Take a food photo in \(.applicationName)",
                "Log a meal photo in \(.applicationName)",
                "Open food scanner in \(.applicationName)",
            ],
            shortTitle: "Scan Meal",
            systemImageName: "camera.viewfinder"
        )
    }
}
