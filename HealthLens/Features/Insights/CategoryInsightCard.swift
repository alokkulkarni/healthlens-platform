import SwiftUI
import Charts
import HealthKit

// MARK: - MetricSummary

struct MetricSummary: Identifiable {
    let id = UUID()
    let typeIdentifier: String
    let displayName: String
    let unit: String
    let latestValue: Double
    let averageValue: Double
    let minValue: Double
    let maxValue: Double
    let trend: TrendDirection
    let dataPoints: [HealthDataPoint]

    var latestFormatted: String { Self.format(latestValue, unit: unit) }
    var unitShort: String { Self.shortUnit(unit) }

    static func format(_ value: Double, unit: String) -> String {
        let u = shortUnit(unit)
        switch u {
        case "bpm", "":         return String(format: "%.0f", value)
        case "%":               return String(format: "%.1f", value)  // values now 0–100
        case "hrs":             return String(format: "%.1f", value)
        case "km":              return String(format: "%.1f", value)
        case "°C":              return String(format: "%.1f", value)
        case "m/s":             return String(format: "%.1f", value)
        case "L":               return String(format: "%.1f", value)
        case "mg/dL":           return String(format: "%.0f", value)
        default:
            if value >= 10_000 { return String(format: "%.0f", value) }
            if value >= 100   { return String(format: "%.0f", value) }
            if value >= 10    { return String(format: "%.1f", value) }
            return String(format: "%.2f", value)
        }
    }

    static func shortUnit(_ unit: String) -> String {
        switch unit {
        case "count/min":                        return "bpm"
        case "count":                            return ""
        case "kg":                               return "kg"
        case "kg/m²", "kg/m^2":                 return "BMI"
        case "m":                                return "m"
        case "km":                               return "km"
        case "cm":                               return "cm"
        case "%":                                return "%"
        case "degC", "°C":                       return "°C"
        case "ms":                               return "ms"
        case "mL/kg·min", "ml/kg·min", "ml/kg/min": return "ml/kg·min"
        case "mmHg":                             return "mmHg"
        case "kcal":                             return "kcal"
        case "min":                              return "min"
        case "hours":                            return "hrs"
        case "g":                                return "g"
        case "mg":                               return "mg"
        case "mcg":                              return "mcg"
        case "mL":                               return "mL"
        case "L":                                return "L"
        case "L/min":                            return "L/min"
        case "dBASPL":                           return "dB"
        case "m/s":                              return "m/s"
        case "W":                                return "W"
        case "mg/dL":                            return "mg/dL"
        case "mcS":                              return "μS"
        case "kcal/hr·kg":                       return "kcal/hr·kg"
        default:                                 return unit
        }
    }
}

// MARK: - ECG Reading model (used by heart card only)

private struct ECGReading: Identifiable {
    let id = UUID()
    let date: Date
    let avgHR: Double
    let classification: Int  // 0=NotSet 1=Sinus 2=AFib 3=HighHR 4=LowHR 5=Poor 6=Other 7=Unrecognized

    var classificationName: String {
        switch classification {
        case 1: return "Sinus Rhythm"
        case 2: return "AFib"
        case 3: return "High HR"
        case 4: return "Low HR"
        case 5: return "Poor Reading"
        case 6: return "Inconclusive"
        default: return "Unknown"
        }
    }

    var classificationColor: Color {
        switch classification {
        case 1: return Color(red: 0.15, green: 0.75, blue: 0.35)   // green  – Sinus (normal)
        case 2: return Color(red: 0.95, green: 0.15, blue: 0.15)   // red    – AFib (alert)
        case 3, 4: return Color(red: 1.0, green: 0.55, blue: 0.0)  // orange – HR out of range
        case 5, 6: return Color(red: 0.9, green: 0.75, blue: 0.0)  // yellow – inconclusive
        default: return Color.secondary
        }
    }
}

// MARK: - CategoryInsightCard

struct CategoryInsightCard: View {
    let category: HealthCategory
    var isExpanded: Bool = false
    /// Incremented by InsightsView when the user pull-to-refreshes.
    var refreshToken: Int = 0

    @State private var expanded: Bool
    @State private var metrics: [MetricSummary] = []
    @State private var ecgReadings: [ECGReading] = []
    @State private var isLoading = false
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(NavigationRouter.self) private var router

    init(category: HealthCategory, isExpanded: Bool = false, refreshToken: Int = 0) {
        self.category = category
        self.isExpanded = isExpanded
        self.refreshToken = refreshToken
        self._expanded = State(initialValue: isExpanded)
    }

    private var overallTrend: TrendDirection { headlineMetric?.trend ?? .unknown }

    private var headlineMetric: MetricSummary? {
        metrics.first { $0.typeIdentifier == headlineTypeIdentifier } ?? metrics.first
    }

    private var headlineTypeIdentifier: String {
        switch category {
        case .activity:     return "HKQuantityTypeIdentifierStepCount"
        case .heart:        return "HKQuantityTypeIdentifierRestingHeartRate"
        case .body:         return "HKQuantityTypeIdentifierBodyMass"
        case .sleep:        return "HKCategoryTypeIdentifierSleepAnalysis"
        case .nutrition:    return "HKQuantityTypeIdentifierDietaryEnergyConsumed"
        case .vitals:       return "HKQuantityTypeIdentifierBloodPressureSystolic"
        case .mindfulness:  return "HKCategoryTypeIdentifierMindfulSession"
        case .environment:  return "HKQuantityTypeIdentifierEnvironmentalAudioExposure"
        case .labs:         return "HKQuantityTypeIdentifierBloodGlucose"
        case .reproductive: return "HKQuantityTypeIdentifierBasalBodyTemperature"
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow

            if expanded {
                Divider()
                    .padding(.horizontal, DesignTokens.Spacing.md)

                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous))
        .shadow(color: DesignTokens.Shadow.sm.color,
                radius: DesignTokens.Shadow.sm.radius,
                x: 0, y: DesignTokens.Shadow.sm.y)
        .task(id: expanded) {
            if expanded && metrics.isEmpty && !isLoading {
                await loadData()
            }
        }
        .onChange(of: refreshToken) { _, _ in
            // Always clear stale cache so next expansion fetches fresh HealthKit data.
            metrics = []
            // If currently visible, reload immediately rather than waiting for re-expand.
            guard expanded && !isLoading else { return }
            Task { await loadData() }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        Button {
            withAnimation(DesignTokens.Animation.standard) { expanded.toggle() }
            triggerHaptic(.selection)
        } label: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                        .fill(category.gradient)
                        .frame(width: 36, height: 36)
                    Image(systemName: category.systemImage)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.displayName)
                        .font(DesignTokens.Typography.headline)
                        .foregroundStyle(.primaryText)
                    Text(subtitleText)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.tertiaryText)
                }

                Spacer()

                if !metrics.isEmpty {
                    TrendBadge(trend: overallTrend, compact: true)
                }

                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiaryText)
                    .animation(DesignTokens.Animation.fast, value: expanded)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(DesignTokens.Spacing.md)
    }

    private var subtitleText: String {
        if isLoading { return "Loading…" }
        if expanded && metrics.isEmpty { return "No data in 30 days" }
        let count = metrics.filter { !$0.dataPoints.isEmpty }.count
        if count == 0 { return "Tap to view · 30 days" }
        return "\(count) metric\(count == 1 ? "" : "s") · 30 days"
    }

    // MARK: - Expanded content

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            if isLoading {
                SkeletonShape(height: 140)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.top, DesignTokens.Spacing.sm)
            } else if metrics.isEmpty {
                emptyDataView
            } else {
                // Activity rings (special section)
                if category == .activity {
                    let rings = buildActivityRings()
                    if !rings.isEmpty {
                        activityRingsSection(rings: rings)
                            .padding(.horizontal, DesignTokens.Spacing.md)
                            .padding(.top, DesignTokens.Spacing.sm)
                    }
                }

                // Heart rate — show Active HR, Resting HR and HRV as 3 separate 30-day charts
                if category == .heart {
                    heartRateChartsSection
                        .padding(.top, DesignTokens.Spacing.sm)
                } else if category == .vitals {
                    vitalsChartsSection
                        .padding(.top, DesignTokens.Spacing.sm)
                } else if let primary = headlineMetric, !primary.dataPoints.isEmpty {
                    // Primary headline chart for all other categories
                    VStack(alignment: .leading, spacing: 4) {
                        Text(primary.displayName)
                            .font(DesignTokens.Typography.footnote)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondaryText)
                            .padding(.horizontal, DesignTokens.Spacing.md)
                        primaryChart(for: primary)
                            .frame(height: category == .sleep ? 195 : 130)
                            .clipped()
                            .padding(.horizontal, DesignTokens.Spacing.md)
                    }
                    .padding(.top, (category == .activity && !buildActivityRings().isEmpty) ? 0 : DesignTokens.Spacing.sm)
                }

                // All metrics grid
                let grid = gridMetrics
                if !grid.isEmpty {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                        Text("All Metrics")
                            .font(DesignTokens.Typography.footnote)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondaryText)
                            .padding(.horizontal, DesignTokens.Spacing.md)

                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: DesignTokens.Spacing.xs
                        ) {
                            ForEach(grid) { metric in
                                MetricTileView(metric: metric, color: category.color)
                            }
                        }
                        .padding(.horizontal, DesignTokens.Spacing.md)
                    }
                }
            }

            // Ask AI button (always shown when expanded)
            Button {
                triggerHaptic(.medium)
                router.openQuery(with: "Analyse all my health data holistically over the last 30 days, with a focus on \(category.displayName.lowercased()) and how it relates to my other health metrics. Identify patterns, correlations and suggest specific improvements.")
            } label: {
                Label("Ask AI about my health", systemImage: "sparkles")
                    .font(DesignTokens.Typography.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(DesignTokens.Spacing.sm)
                    .background(category.color.opacity(0.1))
                    .foregroundStyle(category.color)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.bottom, DesignTokens.Spacing.md)
        }
    }

    // MARK: - Activity rings section

    private func activityRingsSection(rings: [ActivityRingData]) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("Activity Rings")
                .font(DesignTokens.Typography.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.secondaryText)

            HStack(spacing: DesignTokens.Spacing.xl) {
                ForEach(rings, id: \.name) { ring in
                    ActivityRingCell(ring: ring)
                }
                Spacer()
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .background(Color.fillQuaternary)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
    }

    private func buildActivityRings() -> [ActivityRingData] {
        var rings: [ActivityRingData] = []
        if let m = metrics.first(where: { $0.typeIdentifier == "HKQuantityTypeIdentifierActiveEnergyBurned" }),
           !m.dataPoints.isEmpty {
            rings.append(ActivityRingData(name: "Move", value: m.latestValue, goal: 600, color: .red))
        }
        if let m = metrics.first(where: { $0.typeIdentifier == "HKQuantityTypeIdentifierAppleExerciseTime" }),
           !m.dataPoints.isEmpty {
            rings.append(ActivityRingData(name: "Exercise", value: m.latestValue, goal: 30,
                                          color: Color(red: 0.2, green: 0.9, blue: 0.35)))
        }
        if let m = metrics.first(where: { $0.typeIdentifier == "HKQuantityTypeIdentifierAppleStandTime" }),
           !m.dataPoints.isEmpty {
            // Stand time stored in minutes; display and goal in hours
            rings.append(ActivityRingData(name: "Stand", value: m.latestValue / 60, goal: 12,
                                          color: Color(red: 0.0, green: 0.85, blue: 0.9)))
        }
        return rings
    }

    // MARK: - Heart rate multi-chart section

    @ViewBuilder
    private var heartRateChartsSection: some View {
        let heartColor = category.color

        // Core heart rate metrics
        let coreSpecs: [(id: String, label: String, color: Color)] = [
            ("HKQuantityTypeIdentifierRestingHeartRate",         "Resting Heart Rate (bpm)",      Color(red: 1.0, green: 0.35, blue: 0.35)),
            ("HKQuantityTypeIdentifierHeartRateVariabilitySDNN", "HRV – Variance (ms)",           Color(red: 0.4, green: 0.5, blue: 1.0)),
            ("HKQuantityTypeIdentifierHeartRate",                "Active Heart Rate (bpm)",        heartColor),
        ]

        // Cardio fitness metrics
        let cardioSpecs: [(id: String, label: String, color: Color)] = [
            ("HKQuantityTypeIdentifierWalkingHeartRateAverage",      "Walking HR Average (bpm)",      Color(red: 1.0, green: 0.55, blue: 0.0)),
            ("HKQuantityTypeIdentifierVo2Max",                        "VO₂ Max — Cardio Fitness",      Color(red: 0.2, green: 0.75, blue: 0.35)),
            ("HKQuantityTypeIdentifierHeartRateRecoveryOneMinute",    "Cardio Recovery — 1 min (bpm)", Color(red: 0.55, green: 0.2, blue: 0.85)),
        ]

        // Rhythm & ECG metrics
        let rhythmSpecs: [(id: String, label: String, color: Color)] = [
            ("HKQuantityTypeIdentifierAtrialFibrillationBurden", "AFib Burden (%)", Color(red: 1.0, green: 0.2, blue: 0.2)),
        ]

        let availableCore = coreSpecs.compactMap { spec -> (label: String, color: Color, metric: MetricSummary)? in
            guard let m = metrics.first(where: { $0.typeIdentifier == spec.id }),
                  !m.dataPoints.isEmpty else { return nil }
            return (spec.label, spec.color, m)
        }
        let availableCardio = cardioSpecs.compactMap { spec -> (label: String, color: Color, metric: MetricSummary)? in
            guard let m = metrics.first(where: { $0.typeIdentifier == spec.id }),
                  !m.dataPoints.isEmpty else { return nil }
            return (spec.label, spec.color, m)
        }
        let availableRhythm = rhythmSpecs.compactMap { spec -> (label: String, color: Color, metric: MetricSummary)? in
            guard let m = metrics.first(where: { $0.typeIdentifier == spec.id }),
                  !m.dataPoints.isEmpty else { return nil }
            return (spec.label, spec.color, m)
        }
        let exerciseMetric = metrics.first(where: {
            $0.typeIdentifier == "HKQuantityTypeIdentifierAppleExerciseTime" && !$0.dataPoints.isEmpty
        })
        let ecgMetric = metrics.first(where: {
            $0.typeIdentifier == "HKDataTypeIdentifierElectrocardiogram" && !$0.dataPoints.isEmpty
        })

        if availableCore.isEmpty && availableCardio.isEmpty && exerciseMetric == nil
            && availableRhythm.isEmpty && ecgMetric == nil {
            emptyDataView
        } else {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                if !availableCore.isEmpty {
                    Text("30-Day Trends")
                        .font(DesignTokens.Typography.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondaryText)
                        .padding(.horizontal, DesignTokens.Spacing.md)

                    ForEach(availableCore, id: \.label) { item in
                        heartChartCard(label: item.label, color: item.color, metric: item.metric, isBar: false)
                    }
                }

                if !availableCardio.isEmpty || exerciseMetric != nil {
                    Text("Cardio Fitness")
                        .font(DesignTokens.Typography.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondaryText)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, availableCore.isEmpty ? 0 : DesignTokens.Spacing.xs)

                    ForEach(availableCardio, id: \.label) { item in
                        heartChartCard(label: item.label, color: item.color, metric: item.metric, isBar: false)
                    }

                    if let ex = exerciseMetric {
                        heartChartCard(label: "Exercise Minutes / Day", color: Color(red: 0.0, green: 0.7, blue: 0.4), metric: ex, isBar: true)
                    }
                }

                // Rhythm & ECG — only shown when Apple Watch ECG or AFib Burden data exists
                if !availableRhythm.isEmpty || !ecgReadings.isEmpty || ecgMetric != nil {
                    Text("Rhythm & ECG")
                        .font(DesignTokens.Typography.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondaryText)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, (availableCore.isEmpty && availableCardio.isEmpty && exerciseMetric == nil) ? 0 : DesignTokens.Spacing.xs)

                    ForEach(availableRhythm, id: \.label) { item in
                        heartChartCard(label: item.label, color: item.color, metric: item.metric, isBar: true)
                    }

                    if !ecgReadings.isEmpty {
                        ecgClassificationCard(readings: ecgReadings, hrMetric: ecgMetric)
                    } else if let ecg = ecgMetric {
                        // Fallback: classification metadata not available, show HR-only chart
                        heartChartCard(label: "ECG – Avg HR per Reading (bpm)",
                                       color: Color(red: 0.85, green: 0.15, blue: 0.35),
                                       metric: ecg, isBar: true)
                    }
                }
            }
        }
    }

    /// ECG classification timeline — shows rhythm type per reading as coloured dots,
    /// a summary count of each classification, and an avg-HR trend chart.
    @ViewBuilder
    private func ecgClassificationCard(readings: [ECGReading], hrMetric: MetricSummary?) -> some View {
        let counts = Dictionary(grouping: readings, by: \.classification)
            .mapValues(\.count)
            .sorted { a, b in
                // Sort: Sinus first, then others by count descending
                if a.key == 1 { return true }
                if b.key == 1 { return false }
                return a.value > b.value
            }

        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 0.85, green: 0.15, blue: 0.35))
                Text("ECG Readings")
                    .font(DesignTokens.Typography.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primaryText)
                Spacer()
                Text("\(readings.count) reading\(readings.count == 1 ? "" : "s")")
                    .font(DesignTokens.Typography.caption2)
                    .foregroundStyle(.tertiaryText)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)

            // Classification summary pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(counts, id: \.key) { cls, count in
                        let reading = ECGReading(date: .now, avgHR: 0, classification: cls)
                        HStack(spacing: 4) {
                            Circle()
                                .fill(reading.classificationColor)
                                .frame(width: 8, height: 8)
                            Text("\(count) \(reading.classificationName)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.primaryText)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(reading.classificationColor.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
            }

            // Horizontal dot timeline — one coloured dot per reading, oldest → newest
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(readings) { reading in
                        VStack(spacing: 3) {
                            Circle()
                                .fill(reading.classificationColor)
                                .frame(width: 14, height: 14)
                                .overlay(
                                    Circle().strokeBorder(reading.classificationColor.opacity(0.4), lineWidth: 1)
                                )
                            Text(Self.ecgShortDate(reading.date))
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiaryText)
                                .lineLimit(1)
                        }
                        .frame(width: 34)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, 4)
            }
            .frame(height: 56)

            // HR scatter chart — one coloured point per reading, colour = classification
            if readings.filter({ $0.avgHR > 0 }).isEmpty == false {
                Text("Avg HR per reading (bpm)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiaryText)
                    .padding(.horizontal, DesignTokens.Spacing.md)

                Chart(readings.filter { $0.avgHR > 0 }) { reading in
                    PointMark(
                        x: .value("Date", reading.date, unit: .day),
                        y: .value("HR", reading.avgHR)
                    )
                    .foregroundStyle(reading.classificationColor)
                    .symbolSize(120)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.divider)
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .font(.system(size: 9))
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.divider)
                        AxisValueLabel().font(.system(size: 9))
                    }
                }
                .frame(height: 90)
                .padding(.horizontal, DesignTokens.Spacing.md)
            }

            Text("Apple Watch Lead I ECG · Not a diagnostic tool · Ask AI for detailed analysis")
                .font(.system(size: 9))
                .foregroundStyle(.tertiaryText)
                .padding(.horizontal, DesignTokens.Spacing.md)
        }
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(Color.fillQuaternary)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    private static func ecgShortDate(_ date: Date) -> String {
        let cal = Calendar.current
        let thisYear = cal.component(.year, from: Date())
        let dateYear = cal.component(.year, from: date)
        let fmt = DateFormatter()
        fmt.dateFormat = (dateYear == thisYear) ? "d MMM" : "d/M/yy"
        return fmt.string(from: date)
    }

    @ViewBuilder
    private func heartChartCard(label: String, color: Color, metric: MetricSummary, isBar: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(DesignTokens.Typography.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondaryText)
                .padding(.horizontal, DesignTokens.Spacing.md)

            if isBar {
                BarChartView(dataPoints: metric.dataPoints, title: "", color: color)
                    .frame(height: 110)
                    .clipped()
                    .padding(.horizontal, DesignTokens.Spacing.md)
            } else {
                LineChartView(dataPoints: metric.dataPoints, title: "", color: color)
                    .frame(height: 120)
                    .clipped()
                    .padding(.horizontal, DesignTokens.Spacing.md)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(Color.fillQuaternary)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    // MARK: - Vitals multi-chart section

    @ViewBuilder
    private var vitalsChartsSection: some View {
        let vitalsColor = category.color
        // Blood pressure (range chart) — only if both systolic and diastolic have data
        let systolicPts  = metrics.first(where: { $0.typeIdentifier == "HKQuantityTypeIdentifierBloodPressureSystolic" })?.dataPoints ?? []
        let diastolicPts = metrics.first(where: { $0.typeIdentifier == "HKQuantityTypeIdentifierBloodPressureDiastolic" })?.dataPoints ?? []
        let hasBP = !systolicPts.isEmpty && !diastolicPts.isEmpty

        // Individual vitals metrics (line charts)
        let lineSpecs: [(id: String, label: String, color: Color)] = [
            ("HKQuantityTypeIdentifierOxygenSaturation",  "Blood Oxygen (%)",       Color.teal),
            ("HKQuantityTypeIdentifierRespiratoryRate",   "Respiratory Rate (brpm)", Color(red: 0.0, green: 0.7, blue: 0.85)),
            ("HKQuantityTypeIdentifierBodyTemperature",   "Body Temperature (°C)",  Color.orange),
            ("HKQuantityTypeIdentifierWalkingHeartRateAverage", "Walking HR Avg (bpm)", Color(red: 1.0, green: 0.55, blue: 0.0)),
        ]
        let availableLines = lineSpecs.compactMap { spec -> (label: String, color: Color, metric: MetricSummary)? in
            guard let m = metrics.first(where: { $0.typeIdentifier == spec.id }),
                  !m.dataPoints.isEmpty else { return nil }
            return (spec.label, spec.color, m)
        }

        if !hasBP && availableLines.isEmpty {
            emptyDataView
        } else {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text("30-Day Trends")
                    .font(DesignTokens.Typography.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondaryText)
                    .padding(.horizontal, DesignTokens.Spacing.md)

                // Blood pressure range chart (if available)
                if hasBP {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Blood Pressure (mmHg)")
                            .font(DesignTokens.Typography.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondaryText)
                            .padding(.horizontal, DesignTokens.Spacing.md)

                        RangeChartView(dataPoints: systolicPts + diastolicPts, title: "", color: vitalsColor)
                            .frame(height: 120)
                            .clipped()
                            .padding(.horizontal, DesignTokens.Spacing.md)
                    }
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background(Color.fillQuaternary)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
                    .padding(.horizontal, DesignTokens.Spacing.md)
                }

                // Line charts for each available vital sign
                ForEach(availableLines, id: \.label) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.label)
                            .font(DesignTokens.Typography.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondaryText)
                            .padding(.horizontal, DesignTokens.Spacing.md)

                        LineChartView(
                            dataPoints: item.metric.dataPoints,
                            title: "",
                            color: item.color
                        )
                        .frame(height: 110)
                        .clipped()
                        .padding(.horizontal, DesignTokens.Spacing.md)
                    }
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background(Color.fillQuaternary)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
                    .padding(.horizontal, DesignTokens.Spacing.md)
                }
            }
        }
    }

    // MARK: - Primary chart

    @ViewBuilder
    private func primaryChart(for metric: MetricSummary) -> some View {
        switch primaryChartType {
        case "sleep":
            SleepNightlyChartView(dataPoints: metric.dataPoints)
        case "range":
            let systolic  = metrics.first(where: { $0.typeIdentifier == "HKQuantityTypeIdentifierBloodPressureSystolic" })?.dataPoints ?? []
            let diastolic = metrics.first(where: { $0.typeIdentifier == "HKQuantityTypeIdentifierBloodPressureDiastolic" })?.dataPoints ?? []
            RangeChartView(dataPoints: systolic + diastolic, title: "")
        case "bar":
            BarChartView(dataPoints: metric.dataPoints, title: "", color: category.color)
        default:
            LineChartView(dataPoints: metric.dataPoints, title: "", color: category.color)
        }
    }

    private var primaryChartType: String {
        switch category {
        case .sleep:        return "sleep"
        case .activity, .nutrition, .mindfulness: return "bar"
        case .vitals:       return "range"
        default:            return "line"
        }
    }

    // MARK: - Grid metrics

    private var gridMetrics: [MetricSummary] {
        let ringIDs: Set<String> = category == .activity ? [
            "HKQuantityTypeIdentifierActiveEnergyBurned",
            "HKQuantityTypeIdentifierAppleExerciseTime",
            "HKQuantityTypeIdentifierAppleStandTime"
        ] : []
        // For heart, exclude all metrics shown in the multi-chart section from the grid
        let heartChartIDs: Set<String> = category == .heart ? [
            "HKQuantityTypeIdentifierHeartRate",
            "HKQuantityTypeIdentifierRestingHeartRate",
            "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
            "HKQuantityTypeIdentifierWalkingHeartRateAverage",
            "HKQuantityTypeIdentifierVo2Max",
            "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute",
            "HKQuantityTypeIdentifierAppleExerciseTime",
            "HKQuantityTypeIdentifierAtrialFibrillationBurden",
            "HKDataTypeIdentifierElectrocardiogram",
        ] : []
        // For vitals, exclude metrics already shown in vitalsChartsSection
        let vitalsChartIDs: Set<String> = category == .vitals ? [
            "HKQuantityTypeIdentifierBloodPressureSystolic",
            "HKQuantityTypeIdentifierBloodPressureDiastolic",
            "HKQuantityTypeIdentifierOxygenSaturation",
            "HKQuantityTypeIdentifierRespiratoryRate",
            "HKQuantityTypeIdentifierBodyTemperature",
            "HKQuantityTypeIdentifierWalkingHeartRateAverage",
        ] : []
        let excludedIDs = ringIDs.union(heartChartIDs).union(vitalsChartIDs)
        return metrics.filter { !$0.dataPoints.isEmpty && !excludedIDs.contains($0.typeIdentifier) }
    }

    // MARK: - Empty state

    private var emptyDataView: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "tray.fill")
                .font(.title2)
                .foregroundStyle(.tertiaryText)
            Text("No \(category.displayName) data in the last 30 days")
                .font(DesignTokens.Typography.footnote)
                .foregroundStyle(.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.Spacing.xl)
    }

    // MARK: - Data loading

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: end) ?? end
        let range = DateInterval(start: start, end: end)
        do {
            // For the heart card also fetch activity to surface exercise trends alongside
            // cardio fitness metrics (VO₂ Max, Cardio Recovery, Walking HR).
            let categoriesToFetch: [HealthCategory] = (category == .heart) ? [.heart, .activity] : [category]
            let bundle = try await appEnv.healthDataFetcher.fetch(
                for: categoriesToFetch,
                dateRange: range,
                granularity: .daily
            )
            let serializer = HealthDataSerializer()
            var allPoints: [HealthDataPoint] = []

            // For the heart card, extract raw ECG records (with classification metadata) BEFORE
            // makeDataPoint() drops the metadata.  These drive the classification timeline view.
            // ECG dates are stored as date-only ISO8601 ("yyyy-MM-dd") by HealthDataSerializer,
            // so we must parse them with the matching .withFullDate formatter.
            if category == .heart {
                let isoFmt: ISO8601DateFormatter = {
                    let f = ISO8601DateFormatter()
                    f.formatOptions = [.withFullDate]
                    f.timeZone = TimeZone.current
                    return f
                }()
                let heartRecords = bundle.categories[HealthCategory.heart.rawValue] ?? []
                ecgReadings = heartRecords
                    .filter { $0.typeIdentifier == "HKDataTypeIdentifierElectrocardiogram" }
                    .compactMap { r -> ECGReading? in
                        guard let date = isoFmt.date(from: r.date) else { return nil }
                        return ECGReading(
                            date: date,
                            avgHR: r.value,
                            classification: Int(r.metadata?["classification"] ?? 0)
                        )
                    }
                    .sorted { $0.date < $1.date }
            } else {
                ecgReadings = []
            }

            if category == .sleep {
                // Sleep records from HealthDataSerializer use .withFullDate (date-only) ISO8601.
                // Must use the matching formatter here; the default ISO8601DateFormatter uses
                // .withInternetDateTime which cannot parse date-only strings → returns nil → all
                // timestamps fall back to Date() (now) → all 30 nights collapse onto today.
                let dateFmt: ISO8601DateFormatter = {
                    let f = ISO8601DateFormatter()
                    f.formatOptions = [.withFullDate]
                    f.timeZone = TimeZone.current
                    return f
                }()

                // Actual sleep stages only (not "In Bed" or "Awake")
                let granularStages: Set<String> = ["Core Sleep", "Deep Sleep", "REM Sleep"]
                let fallbackStage:  Set<String> = ["Asleep"]   // older/simpler data sources

                // nightStageTotals[nightKey][stageName] → total hours
                var nightStageTotals: [String: [String: Double]] = [:]
                var nightDates:  [String: Date] = [:]
                var nightSource: [String: String] = [:]

                for records in bundle.categories.values {
                    for r in records where r.typeIdentifier == "HKCategoryTypeIdentifierSleepAnalysis" {
                        guard let ts = dateFmt.date(from: r.date) else { continue }
                        let nightKey = r.date   // already "night of" date string from serializer

                        if granularStages.contains(r.displayName) || fallbackStage.contains(r.displayName) {
                            nightStageTotals[nightKey, default: [:]][r.displayName, default: 0] += r.value
                        }
                        if nightDates[nightKey] == nil {
                            nightDates[nightKey] = Calendar.current.startOfDay(for: ts)
                            nightSource[nightKey] = r.source
                        }
                    }
                }

                // If a night has granular stages (Core/Deep/REM), ignore "Asleep" to avoid
                // double-counting (some sources emit both an overall "Asleep" AND stage records).
                for (nightKey, stageMap) in nightStageTotals {
                    guard let nightDate = nightDates[nightKey] else { continue }
                    let hasGranular = granularStages.contains(where: { stageMap[$0] != nil })
                    var totalHours = 0.0
                    for (stageName, hours) in stageMap {
                        if hasGranular && stageName == "Asleep" { continue }
                        totalHours += hours
                    }
                    guard totalHours > 0 else { continue }
                    allPoints.append(HealthDataPoint(
                        typeIdentifier: "HKCategoryTypeIdentifierSleepAnalysis",
                        category: .sleep,
                        timestamp: nightDate,
                        value: totalHours,
                        unit: "hours",
                        source: nightSource[nightKey] ?? "HealthKit",
                        aggregation: .sum
                    ))
                }
            } else {
                for records in bundle.categories.values {
                    allPoints += records.map { serializer.makeDataPoint(from: $0) }
                }
            }

            // Group by typeIdentifier
            var grouped: [String: [HealthDataPoint]] = [:]
            for pt in allPoints {
                grouped[pt.typeIdentifier, default: []].append(pt)
            }

            // Build MetricSummary per group
            var summaries: [MetricSummary] = []
            for (typeID, pts) in grouped {
                let sorted = pts.sorted { $0.timestamp < $1.timestamp }
                let values = sorted.map(\.value)
                let latest = values.last ?? 0
                let avg    = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
                let minV   = values.min() ?? 0
                let maxV   = values.max() ?? 0
                let unit   = sorted.first?.unit ?? ""
                let name   = Self.displayName(for: typeID)
                let trend  = TrendCalculator.calculate(from: sorted)
                summaries.append(MetricSummary(
                    typeIdentifier: typeID,
                    displayName: name,
                    unit: unit,
                    latestValue: latest,
                    averageValue: avg,
                    minValue: minV,
                    maxValue: maxV,
                    trend: trend,
                    dataPoints: sorted
                ))
            }

            // Headline metric first, then sort by data richness
            metrics = summaries.sorted { a, b in
                if a.typeIdentifier == headlineTypeIdentifier { return true }
                if b.typeIdentifier == headlineTypeIdentifier { return false }
                return a.dataPoints.count > b.dataPoints.count
            }
        } catch {
            metrics = []
        }
    }

    // MARK: - Display name helpers

    static func displayName(for typeIdentifier: String) -> String {
        // Special non-quantity/non-category types
        if typeIdentifier == "HKDataTypeIdentifierElectrocardiogram" { return "ECG" }
        if typeIdentifier == "HKDataTypeIdentifierStateOfMind" { return "State of Mind" }

        guard HKHealthStore.isHealthDataAvailable() else { return fallbackName(typeIdentifier) }
        let qID = HKQuantityTypeIdentifier(rawValue: typeIdentifier)
        if let qType = HKObjectType.quantityType(forIdentifier: qID) {
            return qType.displayName
        }
        let cID = HKCategoryTypeIdentifier(rawValue: typeIdentifier)
        if HKObjectType.categoryType(forIdentifier: cID) != nil {
            return categoryTypeName(cID)
        }
        return fallbackName(typeIdentifier)
    }

    private static func fallbackName(_ id: String) -> String {
        (id.components(separatedBy: "Identifier").last ?? id)
            .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func categoryTypeName(_ id: HKCategoryTypeIdentifier) -> String {
        switch id {
        case .sleepAnalysis:                return "Sleep"
        case .mindfulSession:               return "Mindfulness"
        case .handwashingEvent:             return "Handwashing"
        case .toothbrushingEvent:           return "Toothbrushing"
        case .appleStandHour:               return "Stand Hour"
        case .highHeartRateEvent:           return "High HR Event"
        case .lowHeartRateEvent:            return "Low HR Event"
        case .irregularHeartRhythmEvent:    return "Irregular Rhythm"
        case .lowCardioFitnessEvent:        return "Low Cardio Fitness"
        default:
            return (id.rawValue.components(separatedBy: "Identifier").last ?? id.rawValue)
                .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
    }
}

// MARK: - MetricTileView

private struct MetricTileView: View {
    let metric: MetricSummary
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Name + trend
            HStack(spacing: 4) {
                Text(metric.displayName)
                    .font(DesignTokens.Typography.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: metric.trend.icon)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(metric.trend.color)
            }

            // Latest value
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(MetricSummary.format(metric.latestValue, unit: metric.unit))
                    .font(DesignTokens.Typography.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primaryText)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                let short = MetricSummary.shortUnit(metric.unit)
                if !short.isEmpty {
                    Text(short)
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(.tertiaryText)
                }
            }

            // Mini sparkline (when enough data)
            if metric.dataPoints.count >= 3 {
                MiniSparklineView(dataPoints: metric.dataPoints, color: color)
                    .frame(height: 22)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fillQuaternary)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
    }
}

// MARK: - MiniSparklineView

private struct MiniSparklineView: View {
    let dataPoints: [HealthDataPoint]
    let color: Color

    private var chartData: [ChartDataPoint] { dataPoints.toChartData() }

    var body: some View {
        Chart {
            ForEach(chartData) { pt in
                LineMark(
                    x: .value("t", pt.date),
                    y: .value("v", pt.value)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

// MARK: - ActivityRingData

private struct ActivityRingData {
    let name: String
    let value: Double
    let goal: Double
    let color: Color
    var fraction: Double { min(value / max(goal, 1.0), 1.0) }
}

// MARK: - ActivityRingCell

private struct ActivityRingCell: View {
    let ring: ActivityRingData

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(ring.color.opacity(0.2), lineWidth: 8)
                    .frame(width: 56, height: 56)
                Circle()
                    .trim(from: 0, to: ring.fraction)
                    .stroke(ring.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 56, height: 56)
                    .animation(DesignTokens.Animation.standard, value: ring.fraction)
                Text(String(format: "%.0f%%", ring.fraction * 100))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.primaryText)
            }
            Text(ring.name)
                .font(DesignTokens.Typography.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(ring.color)
            Text(ringLabel)
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(.secondaryText)
        }
    }

    private var ringLabel: String {
        switch ring.name {
        case "Move":     return "\(Int(ring.value)) kcal"
        case "Exercise": return "\(Int(ring.value)) min"
        case "Stand":    return String(format: "%.1f hr", ring.value)
        default:         return "\(Int(ring.value))"
        }
    }
}
