import Foundation
import BackgroundTasks
import SwiftData
import OSLog

actor BackgroundObserver {
    static let shared = BackgroundObserver()

    private let fetcher = HealthDataFetcher()
    private var modelContainer: ModelContainer?
    private var fetchTask: Task<Void, Error>?

    private init() {}

    /// Call once from `HealthLensApp.init` to inject the shared model container.
    func configure(with container: ModelContainer) {
        self.modelContainer = container
    }

    func handleBackgroundRefresh(task: BGAppRefreshTask) async {
        Logger.healthKit.info("Background refresh started")

        // Cancel in-flight task when system needs the time slot back.
        task.expirationHandler = { [weak self] in
            Logger.healthKit.warning("Background refresh expired — cancelling in-flight fetch")
            Task { await self?.cancelFetch() }
        }

        fetchTask = Task {
            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end
            let range = DateInterval(start: start, end: end)

            // Fetch ALL non-sensitive categories so the stored snapshot covers everything.
            let categories: [HealthCategory] = [
                .activity, .heart, .sleep, .body, .vitals, .mindfulness,
            ]

            let bundle = try await fetcher.fetch(
                for: categories,
                dateRange: range,
                granularity: .hourly
            )

            // Persist the snapshot so the main app can show fresh data on next launch.
            if let container = modelContainer {
                let context = ModelContext(container)
                let payloadData = (try? JSONEncoder().encode(bundle)) ?? Data()
                let snapshot = HealthSnapshot(start: start, end: end, payloadJSON: payloadData)
                context.insert(snapshot)
                try context.save()
                Logger.healthKit.info("Background snapshot saved (\(payloadData.count) bytes)")
            }
        }

        do {
            try await fetchTask?.value
            Logger.healthKit.info("Background refresh completed successfully")
            task.setTaskCompleted(success: true)
        } catch is CancellationError {
            Logger.healthKit.info("Background refresh cancelled by expiration handler")
            task.setTaskCompleted(success: false)
        } catch {
            Logger.healthKit.error("Background refresh failed: \(error)")
            task.setTaskCompleted(success: false)
        }

        scheduleNextBackgroundRefresh()
    }

    private func cancelFetch() {
        fetchTask?.cancel()
        fetchTask = nil
    }

    func scheduleNextBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(
            identifier: Constants.backgroundRefreshTaskID
        )
        request.earliestBeginDate = Date(
            timeIntervalSinceNow: Double(Constants.Health.backgroundRefreshIntervalHours) * 3600
        )
        do {
            try BGTaskScheduler.shared.submit(request)
            Logger.healthKit.debug("Scheduled next background refresh")
        } catch {
            Logger.healthKit.warning("Failed to schedule background refresh: \(error)")
        }
    }
}
