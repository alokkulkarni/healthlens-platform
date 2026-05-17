import HealthKit
import OSLog

enum HealthKitError: LocalizedError {
    case notAvailable
    case authorizationDenied
    case noData
    case queryFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAvailable:         return "HealthKit is not available on this device"
        case .authorizationDenied:  return "HealthKit access was denied"
        case .noData:               return "No health data available for the requested period"
        case .queryFailed(let e):   return "HealthKit query failed: \(e.localizedDescription)"
        }
    }
}

actor HealthKitService {
    static let shared = HealthKitService()

    nonisolated let store: HKHealthStore

    private init() {
        store = HKHealthStore()
    }

    nonisolated var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Authorization

    func requestAuthorization(for categories: [HealthCategory]) async throws {
        guard isAvailable else { throw HealthKitError.notAvailable }
        var readTypes: Set<HKObjectType> = []
        categories.forEach { readTypes.formUnion($0.allReadTypes) }
        guard !readTypes.isEmpty else { return }
        // Include write types for body and nutrition so Siri intents can write
        // without needing to present an authorization dialog in the background.
        var writeTypes: Set<HKSampleType> = []
        if categories.contains(.body) {
            writeTypes.insert(HKQuantityType(.bodyMass))
            writeTypes.insert(HKQuantityType(.bodyMassIndex))
        }
        if categories.contains(.nutrition) {
            writeTypes.formUnion(Self.nutritionWriteTypes)
        }
        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
    }

    /// All dietary/nutrition types the app can write (used for intent write auth).
    static let nutritionWriteTypes: Set<HKSampleType> = [
        HKQuantityType(.dietaryWater),
        HKQuantityType(.dietaryEnergyConsumed),
        HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryCarbohydrates),
        HKQuantityType(.dietaryFatTotal),
        HKQuantityType(.dietaryFiber),
        HKQuantityType(.dietarySugar),
        HKQuantityType(.dietaryFatSaturated),
        HKQuantityType(.dietaryFatMonounsaturated),
        HKQuantityType(.dietaryFatPolyunsaturated),
        HKQuantityType(.dietarySodium),
        HKQuantityType(.dietaryCholesterol),
        HKQuantityType(.dietaryPotassium),
        HKQuantityType(.dietaryCalcium),
        HKQuantityType(.dietaryIron),
        HKQuantityType(.dietaryZinc),
        HKQuantityType(.dietaryMagnesium),
        HKQuantityType(.dietaryVitaminA),
        HKQuantityType(.dietaryVitaminC),
        HKQuantityType(.dietaryVitaminD),
        HKQuantityType(.dietaryVitaminB6),
        HKQuantityType(.dietaryVitaminB12),
        HKQuantityType(.dietaryFolate),
    ]

    /// All write types needed by Siri intents: nutrition + body.
    static let siriWriteTypes: Set<HKSampleType> = nutritionWriteTypes.union([
        HKQuantityType(.bodyMass),
        HKQuantityType(.bodyMassIndex),
    ])

    /// Requests HealthKit write access for all Siri intent types.
    ///
    /// Safe to call on every launch — `requestAuthorization` is idempotent:
    /// HealthKit silently skips types the user already decided on and only
    /// shows the permission sheet for genuinely new types.
    ///
    /// IMPORTANT: Do NOT gate this on `.notDetermined`. HealthKit returns
    /// `.sharingDenied` for both explicitly-denied AND never-requested types
    /// (by design, for privacy) so the guard would always prevent the dialog
    /// from appearing for upgrading users.
    func ensureSiriWriteTypes() async {
        guard isAvailable else { return }
        try? await store.requestAuthorization(toShare: Self.siriWriteTypes, read: [])
    }

    /// Returns `true` when the minimum write types for Siri water/weight/meal intents are granted.
    nonisolated func hasSiriWriteAccess() -> Bool {
        guard isAvailable else { return false }
        let required: [HKSampleType] = [
            HKQuantityType(.dietaryWater),
            HKQuantityType(.bodyMass),
            HKQuantityType(.dietaryEnergyConsumed),
        ]
        return required.allSatisfy {
            store.authorizationStatus(for: $0) == .sharingAuthorized
        }
    }


    func requestWriteAuthorization(for sampleTypes: Set<HKSampleType>) async throws {
        guard isAvailable else { throw HealthKitError.notAvailable }
        guard !sampleTypes.isEmpty else { return }
        // Request read AND write together so the app can accurately read back data
        // from all sources (other apps, Apple Health entries, etc.), not just its own.
        let objectTypes = Set(sampleTypes.compactMap { $0 as? HKObjectType })
        try await store.requestAuthorization(toShare: sampleTypes, read: objectTypes)
    }

    func saveSamples(_ samples: [HKQuantitySample]) async throws {
        guard isAvailable else { throw HealthKitError.notAvailable }
        guard !samples.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.save(samples) { success, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                } else if !success {
                    continuation.resume(throwing: HealthKitError.authorizationDenied)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        guard isAvailable else { return .notDetermined }
        return store.authorizationStatus(for: type)
    }

    // MARK: - Statistics Collection (aggregated daily/weekly totals)

    func fetchStatistics(
        type: HKQuantityType,
        unit: HKUnit,
        interval: DateComponents,
        start: Date,
        end: Date,
        options: HKStatisticsOptions
    ) async throws -> [HKStatistics] {
        guard isAvailable else { throw HealthKitError.notAvailable }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: start,
                end: end,
                options: .strictStartDate
            )
            let anchorDate = Calendar.current.startOfDay(for: start)
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: anchorDate,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }
                guard let collection else {
                    continuation.resume(returning: [])
                    return
                }
                var results: [HKStatistics] = []
                collection.enumerateStatistics(from: start, to: end) { stats, _ in
                    results.append(stats)
                }
                continuation.resume(returning: results)
            }
            store.execute(query)
        }
    }

    // MARK: - Raw Quantity Samples (for scatter/trend charts)

    func fetchSamples(
        type: HKQuantityType,
        start: Date,
        end: Date,
        limit: Int = HKObjectQueryNoLimit
    ) async throws -> [HKQuantitySample] {
        guard isAvailable else { throw HealthKitError.notAvailable }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: start,
                end: end,
                options: .strictStartDate
            )
            let sort = NSSortDescriptor(
                key: HKSampleSortIdentifierStartDate,
                ascending: true
            )
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
    }

    // MARK: - Category Samples (sleep, mindfulness, events)

    func fetchCategorySamples(
        type: HKCategoryType,
        start: Date,
        end: Date
    ) async throws -> [HKCategorySample] {
        guard isAvailable else { throw HealthKitError.notAvailable }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: start,
                end: end,
                options: .strictStartDate
            )
            let sort = NSSortDescriptor(
                key: HKSampleSortIdentifierStartDate,
                ascending: true
            )
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
    }

    // MARK: - Workouts

    func fetchWorkouts(start: Date, end: Date) async throws -> [HKWorkout] {
        guard isAvailable else { throw HealthKitError.notAvailable }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: start,
                end: end,
                options: .strictStartDate
            )
            let sort = NSSortDescriptor(
                key: HKSampleSortIdentifierStartDate,
                ascending: true
            )
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
    }

    // MARK: - Most Recent Value

    func fetchMostRecent(
        type: HKQuantityType,
        unit: HKUnit
    ) async throws -> (value: Double, date: Date)? {
        guard isAvailable else { throw HealthKitError.notAvailable }

        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(
                key: HKSampleSortIdentifierEndDate,
                ascending: false
            )
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let value = sample.quantity.doubleValue(for: unit)
                continuation.resume(returning: (value: value, date: sample.endDate))
            }
            store.execute(query)
        }
    }

    /// Fetches the `limit` most-recent samples for a quantity type, newest first.
    func fetchRecentSamples(
        type: HKQuantityType,
        unit: HKUnit,
        limit: Int
    ) async throws -> [(value: Double, date: Date)] {
        guard isAvailable else { throw HealthKitError.notAvailable }
        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }
                let result = (samples as? [HKQuantitySample] ?? [])
                    .map { (value: $0.quantity.doubleValue(for: unit), date: $0.endDate) }
                continuation.resume(returning: result)
            }
            self.store.execute(query)
        }
    }

    // MARK: - Activity Summary (Rings)

    func fetchActivitySummary(for date: Date) async throws -> HKActivitySummary? {
        guard isAvailable else { throw HealthKitError.notAvailable }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.day, .month, .year], from: date)
        let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: components, end: components)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }
                continuation.resume(returning: summaries?.first)
            }
            store.execute(query)
        }
    }

    // MARK: - ECG Samples

    func fetchECGSamples(start: Date, end: Date) async throws -> [HKElectrocardiogram] {
        guard isAvailable else { throw HealthKitError.notAvailable }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: start,
                end: end,
                options: .strictStartDate
            )
            let sort = NSSortDescriptor(
                key: HKSampleSortIdentifierStartDate,
                ascending: true
            )
            let query = HKSampleQuery(
                sampleType: HKObjectType.electrocardiogramType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }
                continuation.resume(returning: (samples as? [HKElectrocardiogram]) ?? [])
            }
            store.execute(query)
        }
    }

    // MARK: - State of Mind Samples (iOS 18+)

    @available(iOS 18.0, *)
    func fetchStateOfMindSamples(start: Date, end: Date) async throws -> [HKStateOfMind] {
        guard isAvailable else { throw HealthKitError.notAvailable }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: start,
                end: end,
                options: .strictStartDate
            )
            let sort = NSSortDescriptor(
                key: HKSampleSortIdentifierStartDate,
                ascending: true
            )
            let query = HKSampleQuery(
                sampleType: HKObjectType.stateOfMindType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }
                continuation.resume(returning: (samples as? [HKStateOfMind]) ?? [])
            }
            store.execute(query)
        }
    }
}
