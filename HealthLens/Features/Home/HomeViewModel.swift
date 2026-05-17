import SwiftUI
import SwiftData
import HealthKit

@MainActor
@Observable
final class HomeViewModel {
    var todayStats: [QuickStat] = []
    var recentSessions: [AnalysisSession] = []
    var isLoadingStats: Bool = false
    var error: String?
    var showOnboarding: Bool = false

    private let healthKitService: HealthKitService

    init(healthKitService: HealthKitService = .shared) {
        self.healthKitService = healthKitService
    }

    struct QuickStat: Identifiable {
        let id = UUID()
        let category: HealthCategory
        let title: String
        let value: String
        let unit: String
        let trend: TrendDirection
        let systemImage: String
    }

    enum TrendDirection {
        case up, down, stable, unknown
        var icon: String {
            switch self {
            case .up:      return "arrow.up.right"
            case .down:    return "arrow.down.right"
            case .stable:  return "arrow.right"
            case .unknown: return "minus"
            }
        }
        var color: Color {
            switch self {
            case .up:      return .healthGood
            case .down:    return .healthCritical
            case .stable:  return .healthNeutral
            case .unknown: return .secondary
            }
        }
    }

    func loadTodayStats() async {
        guard healthKitService.isAvailable else {
            loadMockStats()
            return
        }
        isLoadingStats = true
        defer { isLoadingStats = false }

        var stats: [QuickStat] = []

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        // Steps — cumulative sum for today
        if let stepsStats = try? await healthKitService.fetchStatistics(
            type: .init(.stepCount),
            unit: .count(),
            interval: DateComponents(day: 1),
            start: startOfToday,
            end: now,
            options: .cumulativeSum
        ), let first = stepsStats.first, let sum = first.sumQuantity() {
            let steps = sum.doubleValue(for: .count())
            stats.append(QuickStat(
                category: .activity,
                title: "Steps Today",
                value: Int(steps.rounded()).formatted(.number.grouping(.automatic)),
                unit: "steps",
                trend: trendFor(steps, goal: 10_000),
                systemImage: "figure.walk"
            ))
        }

        // Resting HR — most recent reading
        if let hr = try? await healthKitService.fetchMostRecent(
            type: .init(.restingHeartRate),
            unit: HKUnit(from: "count/min")
        ) {
            stats.append(QuickStat(
                category: .heart,
                title: "Resting HR",
                value: String(Int(hr.value)),
                unit: "bpm",
                trend: trendFor(hr.value, goal: 65, lowerIsBetter: true),
                systemImage: "heart.fill"
            ))
        }

        // Weight — most recent reading
        if let weight = try? await healthKitService.fetchMostRecent(
            type: .init(.bodyMass),
            unit: .gramUnit(with: .kilo)
        ) {
            stats.append(QuickStat(
                category: .body,
                title: "Weight",
                value: String(format: "%.1f", weight.value),
                unit: "kg",
                trend: .stable,
                systemImage: "figure.arms.open"
            ))
        }

        // Sleep — total hours from last night (yesterday 6 PM → today noon window)
        let sleepEnd = calendar.date(byAdding: .hour, value: 12, to: startOfToday) ?? now
        let sleepStart = calendar.date(byAdding: .hour, value: -10, to: startOfToday) ?? startOfToday
        if let sleepSamples = try? await healthKitService.fetchCategorySamples(
            type: HKCategoryType(.sleepAnalysis),
            start: sleepStart,
            end: sleepEnd
        ) {
            let asleepSeconds = sleepSamples
                .filter { sample in
                    // Count asleep stages (inBed = 0, asleepUnspecified = 1, awake = 2,
                    // asleepCore = 3, asleepDeep = 4, asleepREM = 5)
                    let v = sample.value
                    return v == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                        || v == HKCategoryValueSleepAnalysis.asleepCore.rawValue
                        || v == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
                        || v == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                }
                .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            let hours = asleepSeconds / 3600
            let display = hours > 0 ? String(format: "%.1f", hours) : "–"
            stats.append(QuickStat(
                category: .sleep,
                title: "Last Sleep",
                value: display,
                unit: "hrs",
                trend: hours > 0 ? trendFor(hours, goal: 8) : .unknown,
                systemImage: "moon.zzz.fill"
            ))
        } else {
            stats.append(QuickStat(
                category: .sleep, title: "Last Sleep", value: "–",
                unit: "hrs", trend: .unknown, systemImage: "moon.zzz.fill"
            ))
        }

        todayStats = stats

        // Append water stat (direct HKStatisticsQuery, all sources).
        await loadWaterStat(&stats)

        // Heart rhythm & fitness metrics — fetched in parallel
        await loadHeartRhythmStats(&stats)

        todayStats = stats
    }

    private func loadWaterStat(_ stats: inout [QuickStat]) async {
        let waterType = HKQuantityType(.dietaryWater)
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let mL: Double = await withCheckedContinuation { continuation in
            let q = HKStatisticsQuery(quantityType: waterType,
                                     quantitySamplePredicate: predicate,
                                     options: .cumulativeSum) { _, result, _ in
                continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: .literUnit(with: .milli)) ?? 0)
            }
            healthKitService.store.execute(q)
        }
        let display = mL >= 1000 ? String(format: "%.1fL", mL / 1000) : "\(Int(mL))ml"
        stats.append(QuickStat(
            category: .nutrition,
            title: "Water",
            value: display,
            unit: "/ 2.5 L",
            trend: trendFor(mL, goal: 2500),
            systemImage: "drop.fill"
        ))
    }

    // MARK: - Heart Rhythm & Fitness Stats

    private func loadHeartRhythmStats(_ stats: inout [QuickStat]) async {
        let now = Date()
        let ecgStart = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now

        // Run all four fetches concurrently
        async let hrvFetch      = healthKitService.fetchRecentSamples(type: .init(.heartRateVariabilitySDNN),
                                                                       unit: HKUnit(from: "ms"), limit: 14)
        async let vo2Fetch      = healthKitService.fetchRecentSamples(type: .init(.vo2Max),
                                                                       unit: HKUnit(from: "ml/(kg*min)"), limit: 2)
        async let cardioFetch   = healthKitService.fetchMostRecent(type: .init(.heartRateRecoveryOneMinute),
                                                                    unit: HKUnit(from: "count/min"))
        async let ecgFetch      = healthKitService.fetchECGSamples(start: ecgStart, end: now)

        // HRV — higher is better; compare latest to rolling average of prior readings
        if let hrv = try? await hrvFetch, let latest = hrv.first {
            let priorValues = hrv.dropFirst().prefix(6).map(\.value)
            let avg = priorValues.isEmpty ? 0 : priorValues.reduce(0, +) / Double(priorValues.count)
            let trend: TrendDirection = avg > 0
                ? (latest.value > avg * 1.05 ? .up : latest.value < avg * 0.95 ? .down : .stable)
                : .unknown
            stats.append(QuickStat(
                category: .heart,
                title: "HRV",
                value: String(Int(latest.value.rounded())),
                unit: "ms",
                trend: trend,
                systemImage: "waveform.path.ecg.rectangle"
            ))
        }

        // VO₂ Max — higher is better; compare latest to previous reading
        if let vo2 = try? await vo2Fetch, let latest = vo2.first {
            let trend: TrendDirection = vo2.count > 1
                ? (latest.value > vo2[1].value * 1.01 ? .up : latest.value < vo2[1].value * 0.99 ? .down : .stable)
                : .unknown
            stats.append(QuickStat(
                category: .heart,
                title: "VO₂ Max",
                value: String(format: "%.1f", latest.value),
                unit: "mL/kg/min",
                trend: trend,
                systemImage: "lungs.fill"
            ))
        }

        // Cardio Recovery — 1-min HR drop after exercise; ≥20 bpm drop is good
        if let cr = try? await cardioFetch {
            stats.append(QuickStat(
                category: .heart,
                title: "Cardio Recovery",
                value: String(Int(cr.value.rounded())),
                unit: "bpm drop",
                trend: trendFor(cr.value, goal: 20),
                systemImage: "heart.circle.fill"
            ))
        }

        // Most recent ECG classification
        if let ecgs = try? await ecgFetch,
           let latest = ecgs.sorted(by: { $0.startDate > $1.startDate }).first {
            let (label, trend) = ecgClassLabel(latest.classification)
            let avgHR = latest.averageHeartRate?.doubleValue(for: HKUnit(from: "count/min")) ?? 0
            let unitStr = avgHR > 0 ? "at \(Int(avgHR)) bpm" : "Lead I"
            stats.append(QuickStat(
                category: .heart,
                title: "Last ECG",
                value: label,
                unit: unitStr,
                trend: trend,
                systemImage: "waveform.path.ecg"
            ))
        }
    }

    private func ecgClassLabel(_ cls: HKElectrocardiogram.Classification) -> (String, TrendDirection) {
        switch cls {
        case .sinusRhythm:               return ("Sinus", .up)
        case .atrialFibrillation:        return ("AFib ⚠︎", .down)
        case .inconclusiveHighHeartRate: return ("High HR", .stable)
        case .inconclusiveLowHeartRate:  return ("Low HR", .stable)
        case .inconclusivePoorReading:   return ("Poor Signal", .unknown)
        case .inconclusiveOther:         return ("Unclear", .unknown)
        default:                         return ("–", .unknown)
        }
    }

    private func loadMockStats() {
        todayStats = [
            QuickStat(category: .activity, title: "Steps Today", value: "8,432", unit: "steps", trend: .up, systemImage: "figure.walk"),
            QuickStat(category: .heart, title: "Resting HR", value: "62", unit: "bpm", trend: .stable, systemImage: "heart.fill"),
            QuickStat(category: .body, title: "Weight", value: "74.2", unit: "kg", trend: .down, systemImage: "figure.arms.open"),
            QuickStat(category: .sleep, title: "Last Sleep", value: "7.2", unit: "hrs", trend: .up, systemImage: "moon.zzz.fill"),
            QuickStat(category: .nutrition, title: "Water", value: "1.2L", unit: "/ 2.5 L", trend: .stable, systemImage: "drop.fill"),
            QuickStat(category: .heart, title: "HRV", value: "42", unit: "ms", trend: .stable, systemImage: "waveform.path.ecg.rectangle"),
            QuickStat(category: .heart, title: "VO₂ Max", value: "38.5", unit: "mL/kg/min", trend: .up, systemImage: "lungs.fill"),
            QuickStat(category: .heart, title: "Last ECG", value: "Sinus", unit: "at 68 bpm", trend: .up, systemImage: "waveform.path.ecg"),
        ]
    }

    private func trendFor(_ value: Double, goal: Double, lowerIsBetter: Bool = false) -> TrendDirection {
        let ratio = value / goal
        if lowerIsBetter {
            if ratio < 0.9 { return .up }    // Better
            if ratio > 1.1 { return .down }  // Worse
            return .stable
        } else {
            if ratio >= 1.0 { return .up }
            if ratio < 0.5 { return .down }
            return .stable
        }
    }

    func checkOnboardingStatus(prefs: UserPreferences?) {
        showOnboarding = !(prefs?.hasCompletedOnboarding ?? false)
    }
}
