import HealthKit
import Foundation

// MARK: - HKCategoryType convenience

private extension HKCategoryType {
    /// Typed identifier for use in switch/contains comparisons.
    var categoryTypeIdentifier: HKCategoryTypeIdentifier {
        HKCategoryTypeIdentifier(rawValue: identifier)
    }
}

// MARK: - Serialized record DTO (sent to AI and stored for charts)

struct SerializedHealthRecord: Codable, Sendable {
    let typeIdentifier: String
    let displayName: String
    let category: String
    let date: String       // ISO8601 date string
    let value: Double
    let unit: String
    let aggregation: String
    let source: String
    var metadata: [String: Double]?
}

struct HealthDataSerializer {
    // Use local timezone so that dates shown to the AI match the user's calendar dates.
    // ISO8601DateFormatter defaults to UTC when timeZone is unset, which shifts dates
    // backward by one day for users in UTC+ timezones (e.g. midnight BST = 23:00 UTC prev day).
    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = TimeZone.current
        return f
    }()

    // Mirror formatter for parsing — must use same timezone used when formatting.
    private static let dateParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = TimeZone.current
        return f
    }()

    // MARK: - Statistics Collection → Records

    func serialize(
        stats: [HKStatistics],
        type: HKQuantityType
    ) -> [SerializedHealthRecord] {
        let unit = type.preferredUnit
        let isSum = type.defaultStatisticsOptions.contains(.cumulativeSum)
        let category = category(for: type)

        return stats.compactMap { stat in
            let quantity: HKQuantity?
            if isSum {
                quantity = stat.sumQuantity()
            } else {
                quantity = stat.averageQuantity()
            }
            guard let quantity else { return nil }
            let raw = quantity.doubleValue(for: unit)
            // HKUnit.percent() returns 0–1 fractions; scale to 0–100 for display/LLM
            let value = (unit == HKUnit.percent()) ? raw * 100.0 : raw
            return SerializedHealthRecord(
                typeIdentifier: type.identifier,
                displayName: type.displayName,
                category: category,
                date: dateFormatter.string(from: stat.startDate),
                value: value,
                unit: unitString(unit),
                aggregation: isSum ? "sum" : "average",
                source: "HealthKit"
            )
        }
    }

    // MARK: - Quantity Samples → Records

    func serialize(
        samples: [HKQuantitySample],
        type: HKQuantityType
    ) -> [SerializedHealthRecord] {
        let unit = type.preferredUnit
        let category = category(for: type)

        return samples.map { sample in
            let raw = sample.quantity.doubleValue(for: unit)
            let value = (unit == HKUnit.percent()) ? raw * 100.0 : raw
            return SerializedHealthRecord(
                typeIdentifier: type.identifier,
                displayName: type.displayName,
                category: category,
                date: dateFormatter.string(from: sample.startDate),
                value: value,
                unit: unitString(unit),
                aggregation: "raw",
                source: sample.sourceRevision.source.bundleIdentifier
            )
        }
    }

    // MARK: - Category Samples → Records (sleep, mindfulness, events)

    func serialize(
        categorySamples: [HKCategorySample],
        type: HKCategoryType
    ) -> [SerializedHealthRecord] {
        categorySamples.compactMap { sample in
            // For sleep: record all stages (inBed, core, deep, REM, awake) —
            // the full breakdown is essential for the LLM to assess sleep quality.
            if type == HKCategoryType(.sleepAnalysis) {
                let stage = HKCategoryValueSleepAnalysis(rawValue: sample.value)
                let durationHours = sample.endDate.timeIntervalSince(sample.startDate) / 3600.0
                // Normalize to "night of" date: segments starting before 14:00 (2 PM)
                // belong to the *previous* calendar night (sleep crossing midnight).
                // e.g. REM at 02:00 April 15 → night of April 14.
                let nightDate = sleepNightDate(for: sample.startDate)
                return SerializedHealthRecord(
                    typeIdentifier: type.identifier,
                    displayName: sleepDisplayName(for: stage),
                    category: HealthCategory.sleep.rawValue,
                    date: dateFormatter.string(from: nightDate),
                    value: durationHours,
                    unit: "hours",
                    aggregation: "duration",
                    source: sample.sourceRevision.source.bundleIdentifier
                )
            }

            // For mindfulness / handwashing / toothbrushing — record duration
            let mindfulTypes: [HKCategoryTypeIdentifier] = [
                .mindfulSession, .handwashingEvent, .toothbrushingEvent,
            ]
            if mindfulTypes.contains(type.categoryTypeIdentifier) {
                let durationMinutes = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                return SerializedHealthRecord(
                    typeIdentifier: type.identifier,
                    displayName: categoryEventDisplayName(for: type),
                    category: HealthCategory.mindfulness.rawValue,
                    date: dateFormatter.string(from: sample.startDate),
                    value: durationMinutes,
                    unit: "minutes",
                    aggregation: "duration",
                    source: sample.sourceRevision.source.bundleIdentifier
                )
            }

            // For stand hours — record occurrence (1 = stood this hour)
            if type == HKCategoryType(.appleStandHour) {
                let stood = sample.value == HKCategoryValueAppleStandHour.stood.rawValue ? 1.0 : 0.0
                return SerializedHealthRecord(
                    typeIdentifier: type.identifier,
                    displayName: "Stand Hour",
                    category: HealthCategory.activity.rawValue,
                    date: dateFormatter.string(from: sample.startDate),
                    value: stood,
                    unit: "stood",
                    aggregation: "raw",
                    source: sample.sourceRevision.source.bundleIdentifier
                )
            }

            // Cardiac events (high HR, low HR, irregular rhythm, low cardio fitness) — record occurrence
            let cardiacEvents: [HKCategoryTypeIdentifier] = [
                .highHeartRateEvent, .lowHeartRateEvent,
                .irregularHeartRhythmEvent, .lowCardioFitnessEvent,
            ]
            if cardiacEvents.contains(type.categoryTypeIdentifier) {
                let durationMinutes = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                return SerializedHealthRecord(
                    typeIdentifier: type.identifier,
                    displayName: categoryEventDisplayName(for: type),
                    category: HealthCategory.heart.rawValue,
                    date: dateFormatter.string(from: sample.startDate),
                    value: durationMinutes > 0 ? durationMinutes : 1.0,
                    unit: "event",
                    aggregation: "duration",
                    source: sample.sourceRevision.source.bundleIdentifier
                )
            }

            // Reproductive category events
            let reproductiveEvents: [HKCategoryTypeIdentifier] = [
                .menstrualFlow, .ovulationTestResult, .intermenstrualBleeding,
                .sexualActivity, .contraceptive, .lactation,
                .pregnancyTestResult, .progesteroneTestResult,
            ]
            if reproductiveEvents.contains(type.categoryTypeIdentifier) {
                return SerializedHealthRecord(
                    typeIdentifier: type.identifier,
                    displayName: categoryEventDisplayName(for: type),
                    category: HealthCategory.reproductive.rawValue,
                    date: dateFormatter.string(from: sample.startDate),
                    value: Double(sample.value),
                    unit: "value",
                    aggregation: "raw",
                    source: sample.sourceRevision.source.bundleIdentifier
                )
            }

            return nil
        }
    }

    // MARK: - ECG Samples → Records

    func serialize(ecgSamples: [HKElectrocardiogram]) -> [SerializedHealthRecord] {
        ecgSamples.map { ecg in
            let classificationValue: Double
            switch ecg.classification {
            case .notSet:                       classificationValue = 0
            case .sinusRhythm:                  classificationValue = 1
            case .atrialFibrillation:           classificationValue = 2
            case .inconclusiveHighHeartRate:    classificationValue = 3
            case .inconclusiveLowHeartRate:     classificationValue = 4
            case .inconclusivePoorReading:      classificationValue = 5
            case .inconclusiveOther:            classificationValue = 6
            case .unrecognized:                 classificationValue = 7
            @unknown default:                   classificationValue = 0
            }
            let avgHRBPM = ecg.averageHeartRate?.doubleValue(for: HKUnit(from: "count/min")) ?? 0
            return SerializedHealthRecord(
                typeIdentifier: "HKDataTypeIdentifierElectrocardiogram",
                displayName: "ECG",
                category: HealthCategory.heart.rawValue,
                date: dateFormatter.string(from: ecg.startDate),
                value: avgHRBPM,
                unit: "bpm",
                aggregation: "raw",
                source: ecg.sourceRevision.source.bundleIdentifier,
                metadata: ["classification": classificationValue]
            )
        }
    }

    // MARK: - State of Mind Samples → Records (iOS 18+)

    @available(iOS 18.0, *)
    func serialize(stateOfMindSamples: [HKStateOfMind]) -> [SerializedHealthRecord] {
        stateOfMindSamples.map { sample in
            // Scale valence from [-1, +1] to [0, 100] for chart display
            let scaledValue = (sample.valence + 1.0) * 50.0
            return SerializedHealthRecord(
                typeIdentifier: "HKDataTypeIdentifierStateOfMind",
                displayName: "State of Mind",
                category: HealthCategory.mindfulness.rawValue,
                date: dateFormatter.string(from: sample.startDate),
                value: scaledValue,
                unit: "valence",
                aggregation: "raw",
                source: sample.sourceRevision.source.bundleIdentifier,
                metadata: ["kind": Double(sample.kind.rawValue)]
            )
        }
    }

    // MARK: - Workouts → Records

    func serialize(workouts: [HKWorkout]) -> [SerializedHealthRecord] {
        workouts.map { workout in
            let energyUnit = HKUnit.kilocalorie()
            let calories = workout.totalEnergyBurned?.doubleValue(for: energyUnit) ?? 0
            return SerializedHealthRecord(
                typeIdentifier: "HKWorkoutTypeIdentifier",
                displayName: workoutDisplayName(workout.workoutActivityType),
                category: HealthCategory.activity.rawValue,
                date: dateFormatter.string(from: workout.startDate),
                value: workout.duration / 60.0,
                unit: "minutes",
                aggregation: "duration",
                source: workout.sourceRevision.source.bundleIdentifier,
                metadata: ["calories": calories, "activityType": Double(workout.workoutActivityType.rawValue)]
            )
        }
    }

    // MARK: - SwiftData HealthDataPoint creation

    func makeDataPoint(from record: SerializedHealthRecord) -> HealthDataPoint {
        let category = HealthCategory(rawValue: record.category) ?? .activity
        let timestamp = HealthDataSerializer.dateParser.date(from: record.date) ?? Date()
        let aggregation = AggregationType(rawValue: record.aggregation) ?? .raw
        return HealthDataPoint(
            typeIdentifier: record.typeIdentifier,
            category: category,
            timestamp: timestamp,
            value: record.value,
            unit: record.unit,
            source: record.source,
            aggregation: aggregation
        )
    }

    // MARK: - Helpers

    private func category(for type: HKQuantityType) -> String {
        HealthCategory.allCases
            .first { $0.quantityTypes.contains(type) }?
            .rawValue ?? "unknown"
    }

    private func unitString(_ unit: HKUnit) -> String {
        unit.unitString
    }

    private func sleepDisplayName(for stage: HKCategoryValueSleepAnalysis?) -> String {
        switch stage {
        case .inBed:        return "In Bed"
        case .asleepUnspecified: return "Asleep"
        case .awake:        return "Awake"
        case .asleepCore:   return "Core Sleep"
        case .asleepDeep:   return "Deep Sleep"
        case .asleepREM:    return "REM Sleep"
        default:            return "Sleep"
        }
    }

    /// Returns the "night of" date for a sleep segment.
    /// Segments starting before 14:00 (2 PM) are attributed to the previous
    /// calendar day — the night they actually belong to.
    private func sleepNightDate(for startDate: Date) -> Date {
        let hour = Calendar.current.component(.hour, from: startDate)
        if hour < 14 {
            return Calendar.current.date(byAdding: .day, value: -1, to: startDate) ?? startDate
        }
        return startDate
    }

    private func categoryEventDisplayName(for type: HKCategoryType) -> String {
        switch type.categoryTypeIdentifier {
        case .mindfulSession:           return "Mindful Session"
        case .handwashingEvent:         return "Handwashing"
        case .toothbrushingEvent:       return "Toothbrushing"
        case .highHeartRateEvent:       return "High Heart Rate Event"
        case .lowHeartRateEvent:        return "Low Heart Rate Event"
        case .irregularHeartRhythmEvent: return "Irregular Rhythm"
        case .lowCardioFitnessEvent:    return "Low Cardio Fitness"
        case .menstrualFlow:            return "Menstrual Flow"
        case .ovulationTestResult:      return "Ovulation Test"
        case .intermenstrualBleeding:   return "Intermenstrual Bleeding"
        case .sexualActivity:           return "Sexual Activity"
        case .contraceptive:            return "Contraceptive"
        case .lactation:                return "Lactation"
        case .pregnancyTestResult:      return "Pregnancy Test"
        case .progesteroneTestResult:   return "Progesterone Test"
        default:                        return type.identifier
        }
    }

    private func workoutDisplayName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running:                          return "Run"
        case .cycling:                          return "Cycle"
        case .swimming:                         return "Swim"
        case .walking:                          return "Walk"
        case .yoga:                             return "Yoga"
        case .functionalStrengthTraining:       return "Strength Training"
        case .traditionalStrengthTraining:      return "Strength Training"
        case .highIntensityIntervalTraining:    return "HIIT"
        case .rowing:                           return "Rowing"
        case .elliptical:                       return "Elliptical"
        case .stairClimbing:                    return "Stair Climbing"
        case .hiking:                           return "Hiking"
        case .pilates:                          return "Pilates"
        case .dance:                            return "Dance"
        case .tennis:                           return "Tennis"
        case .basketball:                       return "Basketball"
        case .soccer:                           return "Soccer"
        case .americanFootball:                 return "American Football"
        case .crossTraining:                    return "Cross Training"
        case .mixedCardio:                      return "Mixed Cardio"
        case .mindAndBody:                      return "Mind & Body"
        case .flexibility:                      return "Flexibility"
        case .jumpRope:                         return "Jump Rope"
        case .kickboxing:                       return "Kickboxing"
        case .martialArts:                      return "Martial Arts"
        case .golf:                             return "Golf"
        case .downhillSkiing:                   return "Skiing"
        case .snowboarding:                     return "Snowboarding"
        case .surfingSports:                    return "Surfing"
        case .baseball:                         return "Baseball"
        case .softball:                         return "Softball"
        case .volleyball:                       return "Volleyball"
        case .badminton:                        return "Badminton"
        case .squash:                           return "Squash"
        case .racquetball:                      return "Racquetball"
        case .cricket:                          return "Cricket"
        case .rugby:                            return "Rugby"
        case .waterPolo:                        return "Water Polo"
        default:                                return "Workout"
        }
    }
}
