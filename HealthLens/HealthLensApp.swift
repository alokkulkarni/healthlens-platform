import SwiftUI
import SwiftData
import OSLog

@main
struct HealthLensApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let container: ModelContainer

    init() {
        // Ensure Application Support directory exists before SwiftData tries to create
        // the store file — avoids the noisy CoreData "Failed to stat path" log on first launch.
        let appSupportURL: URL
        if let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            appSupportURL = url
        } else {
            appSupportURL = FileManager.default.temporaryDirectory
        }
        try? FileManager.default.createDirectory(
            at: appSupportURL,
            withIntermediateDirectories: true
        )

        let schema = Schema([
            AnalysisSession.self,
            HealthSnapshot.self,
            UserPreferences.self,
        ])
        let storeURL = appSupportURL.appendingPathComponent("HealthLens.store")
        let config = ModelConfiguration(
            "HealthLens",
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            // Migration failure or corrupted store — delete and recreate to avoid
            // an unrecoverable crash on launch. User data is lost in this rare case,
            // but the app remains functional. Log so we can diagnose in future.
            Logger.persistence.error("ModelContainer creation failed, rebuilding store: \(error)")
            try? FileManager.default.removeItem(at: storeURL)
            do {
                container = try ModelContainer(for: schema, configurations: config)
            } catch {
                // If even an empty store fails (e.g., disk full), surface the error
                // via a graceful crash log rather than a silent bad state.
                Logger.persistence.critical("Cannot create ModelContainer even after reset: \(error)")
                // Intentional: app cannot function without persistent storage.
                // This only occurs when the device has no available disk space.
                preconditionFailure("Cannot initialise SwiftData store: \(error)")
            }
        }

        // Provide BackgroundObserver with the container so it can persist snapshots.
        let c = container
        Task { await BackgroundObserver.shared.configure(with: c) }

        // Register Siri App Shortcuts so phrases appear in Shortcuts.app
        HealthLensShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            AppContentView()
                .modelContainer(container)
        }
    }
}
