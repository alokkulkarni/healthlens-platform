import Foundation
import HealthKit
import OSLog
import UIKit

// MARK: - Data bundle sent to AI

struct HealthDataBundle: Codable, Sendable {
    var dateRangeStart: Date
    var dateRangeEnd: Date
    var categories: [String: [SerializedHealthRecord]]
    var metadata: FetchMetadata
}

struct FetchMetadata: Codable, Sendable {
    var fetchedAt: String
    var totalRecordCount: Int
    var missingCategories: [String]
    var deviceModel: String    // device type only, never the user's personal name
    var appVersion: String
}

enum FetchGranularity: String {
    case hourly, daily, weekly

    var components: DateComponents {
        switch self {
        case .hourly:  return DateComponents(hour: 1)
        case .daily:   return DateComponents(day: 1)
        case .weekly:  return DateComponents(weekOfYear: 1)
        }
    }
}

// MARK: - HealthDataFetcher

actor HealthDataFetcher {
    private let service: HealthKitService
    private let serializer: HealthDataSerializer

    init(service: HealthKitService = .shared) {
        self.service = service
        self.serializer = HealthDataSerializer()
    }

    /// Primary entry point — fetches all requested categories in parallel.
    func fetch(
        for categories: [HealthCategory],
        dateRange: DateInterval,
        granularity: FetchGranularity = .daily
    ) async throws -> HealthDataBundle {
        // On simulator, use mock data
        if !service.isAvailable {
            return try MockHealthDataProvider.loadBundle(
                categories: categories,
                dateRange: dateRange
            )
        }

        var resultMap: [String: [SerializedHealthRecord]] = [:]
        var missingCategories: [String] = []
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]

        await withTaskGroup(of: (String, [SerializedHealthRecord]).self) { group in
            for category in categories {
                group.addTask { [self] in
                    do {
                        let records = try await self.fetchCategory(
                            category,
                            range: dateRange,
                            granularity: granularity
                        )
                        return (category.rawValue, records)
                    } catch {
                        Logger.healthKit.warning("Failed to fetch \(category.rawValue): \(error)")
                        return (category.rawValue, [])
                    }
                }
            }
            for await (key, records) in group {
                if records.isEmpty {
                    missingCategories.append(key)
                }
                resultMap[key] = records
            }
        }

        let totalCount = resultMap.values.flatMap { $0 }.count
        let meta = await MainActor.run {
            FetchMetadata(
                fetchedAt: isoFormatter.string(from: Date()),
                totalRecordCount: totalCount,
                missingCategories: missingCategories,
                deviceModel: UIDevice.current.model,   // model only — no personal name
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            )
        }

        return HealthDataBundle(
            dateRangeStart: dateRange.start,
            dateRangeEnd: dateRange.end,
            categories: resultMap,
            metadata: meta
        )
    }

    // MARK: - Per-category fetch

    private func fetchCategory(
        _ category: HealthCategory,
        range: DateInterval,
        granularity: FetchGranularity
    ) async throws -> [SerializedHealthRecord] {
        var records: [SerializedHealthRecord] = []
        let interval = granularity.components

        // Quantity types (aggregated stats)
        for quantityType in category.quantityTypes {
            do {
                if quantityType.isComputedDaily {
                    // "Computed daily" types — Apple Watch stores ONE sample per day
                    // (e.g. Resting HR, Walking HR, VO₂ Max, Wrist Temp).
                    // HKStatisticsCollectionQuery silently returns empty for these because
                    // the sample's startDate (time of Watch computation, e.g. 3 AM) can
                    // fall outside the expected calendar-day bucket. HKSampleQuery is
                    // reliable: it finds every sample whose startDate is within the range.
                    let samples = try await service.fetchSamples(
                        type: quantityType,
                        start: range.start,
                        end: range.end
                    )
                    records += serializer.serialize(samples: samples, type: quantityType)
                } else {
                    let stats = try await service.fetchStatistics(
                        type: quantityType,
                        unit: quantityType.preferredUnit,
                        interval: interval,
                        start: range.start,
                        end: range.end,
                        options: quantityType.defaultStatisticsOptions
                    )
                    let serialized = serializer.serialize(stats: stats, type: quantityType)
                    // Safety fallback: if statistics returned nothing, attempt a raw sample
                    // query so transient HealthKit aggregation issues don't silently omit data.
                    if serialized.isEmpty {
                        let samples = try await service.fetchSamples(
                            type: quantityType,
                            start: range.start,
                            end: range.end
                        )
                        records += serializer.serialize(samples: samples, type: quantityType)
                    } else {
                        records += serialized
                    }
                }
            } catch {
                Logger.healthKit.debug("Skipping \(quantityType.identifier): \(error)")
            }
        }

        // Category types (sleep, mindfulness)
        for categoryType in category.categoryTypes {
            do {
                var samples = try await service.fetchCategorySamples(
                    type: categoryType,
                    start: range.start,
                    end: range.end
                )
                // Sleep: deduplicate across multiple sources.
                // HealthKit stores records from ALL installed apps (Apple Watch, Oura,
                // AutoSleep, etc.) simultaneously. When several apps record the same night,
                // summing them inflates stage totals. Keep only the source with the highest
                // total stage-sleep duration per night — this matches what the Health app
                // shows when a priority source is configured.
                if categoryType == HKCategoryType(.sleepAnalysis) {
                    samples = deduplicateSleepSamples(samples)
                }
                records += serializer.serialize(categorySamples: samples, type: categoryType)
            } catch {
                Logger.healthKit.debug("Skipping category type \(categoryType.identifier): \(error)")
            }
        }

        // Workouts
        if category == .activity {
            do {
                let workouts = try await service.fetchWorkouts(
                    start: range.start,
                    end: range.end
                )
                records += serializer.serialize(workouts: workouts)
            } catch {
                Logger.healthKit.debug("Skipping workouts: \(error)")
            }
        }

        // ECG samples
        if category == .heart {
            do {
                let ecgs = try await service.fetchECGSamples(
                    start: range.start,
                    end: range.end
                )
                records += serializer.serialize(ecgSamples: ecgs)
            } catch {
                Logger.healthKit.debug("Skipping ECG samples: \(error)")
            }
        }

        // State of Mind (iOS 18+)
        if category == .mindfulness {
            if #available(iOS 18.0, *) {
                do {
                    let stateOfMindSamples = try await service.fetchStateOfMindSamples(
                        start: range.start,
                        end: range.end
                    )
                    records += serializer.serialize(stateOfMindSamples: stateOfMindSamples)
                } catch {
                    Logger.healthKit.debug("Skipping State of Mind samples: \(error)")
                }
            }
        }

        return records
    }

    // MARK: - Sleep Source Deduplication

    /// When multiple apps (Apple Watch, Oura, AutoSleep, etc.) all write sleep data to
    /// HealthKit for the same night, HealthKit stores every record from every source.
    /// Using all sources simultaneously inflates or contradicts stage totals.
    ///
    /// Strategy: per night, keep only the source whose stage-sleep segments add up to
    /// the longest total. In the common Apple Watch + third-party scenario this selects
    /// whichever app has the most comprehensive coverage — matching the Health app's
    /// default priority behaviour.
    private func deduplicateSleepSamples(_ samples: [HKCategorySample]) -> [HKCategorySample] {
        guard !samples.isEmpty else { return samples }
        let calendar = Calendar.current

        // Night-of convention (mirrors HealthDataSerializer.sleepNightDate):
        // a segment starting before 14:00 belongs to the *previous* calendar night.
        func nightDate(for date: Date) -> Date {
            let hour = calendar.component(.hour, from: date)
            let base = calendar.startOfDay(for: date)
            return hour < 14
                ? (calendar.date(byAdding: .day, value: -1, to: base) ?? base)
                : base
        }

        // Actual sleep stage values — inBed and awake are excluded from the tally
        // so we pick the source with the most meaningful sleep (not the most awake time).
        let stageSleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        ]

        // Group samples: nightDate → sourceID → [samples]
        var nightGroups: [Date: [String: [HKCategorySample]]] = [:]
        for sample in samples {
            let night    = nightDate(for: sample.startDate)
            let sourceID = sample.sourceRevision.source.bundleIdentifier
            nightGroups[night, default: [:]][sourceID, default: []].append(sample)
        }

        var kept: [HKCategorySample] = []
        for (_, sourceMap) in nightGroups {
            // Single source for this night — nothing to deduplicate.
            guard sourceMap.count > 1 else {
                kept += sourceMap.values.flatMap { $0 }
                continue
            }

            // Compute total stage-sleep seconds per source.
            let durationBySource = sourceMap.mapValues { sourceSamples in
                sourceSamples
                    .filter { stageSleepValues.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            }

            if let dominantID = durationBySource.max(by: { $0.value < $1.value })?.key,
               let dominantSamples = sourceMap[dominantID] {
                kept += dominantSamples
            } else {
                // Fallback: keep all sources (shouldn't reach here).
                kept += sourceMap.values.flatMap { $0 }
            }
        }

        return kept.sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Convenience: encode bundle to JSON

    func encodeBundle(_ bundle: HealthDataBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(bundle)
    }
}

// MARK: - Mock data provider for simulator

struct MockHealthDataProvider {
    static func loadBundle(
        categories: [HealthCategory],
        dateRange: DateInterval
    ) throws -> HealthDataBundle {
        guard let url = Bundle.main.url(forResource: "MockHealthData", withExtension: "json") else {
            return emptyBundle(categories: categories, dateRange: dateRange)
        }
        let data = try Data(contentsOf: url)
        let bundle = try JSONDecoder().decode(HealthDataBundle.self, from: data)
        let filtered = bundle.categories.filter { key, _ in
            categories.map(\.rawValue).contains(key)
        }
        return HealthDataBundle(
            dateRangeStart: dateRange.start,
            dateRangeEnd: dateRange.end,
            categories: filtered,
            metadata: bundle.metadata
        )
    }

    private static func emptyBundle(categories: [HealthCategory], dateRange: DateInterval) -> HealthDataBundle {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        return HealthDataBundle(
            dateRangeStart: dateRange.start,
            dateRangeEnd: dateRange.end,
            categories: [:],
            metadata: FetchMetadata(
                fetchedAt: isoFormatter.string(from: Date()),
                totalRecordCount: 0,
                missingCategories: categories.map(\.rawValue),
                deviceModel: "Simulator",
                appVersion: "1.0"
            )
        )
    }
}
