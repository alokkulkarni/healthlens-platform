import SwiftUI
import HealthKit

// MARK: - WaterIntakeCard

/// Prominent water-logging widget shown on the Nutrition Log tab.
/// Reads today's cumulative intake from HealthKit (including from other apps),
/// lets the user log quick amounts or a custom amount, and writes every entry
/// back to HealthKit so it appears in the Health app and in the Insights tab.
struct WaterIntakeCard: View {
    @State private var todayML: Double = 0
    @State private var isLoading = false
    @State private var showCustomSheet = false
    @State private var justLoggedML: Double? = nil   // drives brief "✓ +Xml" toast
    /// Increment from a parent view (HomeView, NutritionLogTabView) to force a re-fetch.
    var refreshToken: Int = 0

    private let dailyGoalML: Double = 2500

    private let quickAmounts: [(label: String, ml: Double)] = [
        ("150ml", 150),
        ("250ml", 250),
        ("350ml", 350),
        ("500ml", 500),
        ("1 L",  1000),
    ]

    private var progress: Double { min(todayML / dailyGoalML, 1.0) }

    private var displayTotal: String {
        todayML >= 1000
            ? String(format: "%.1f L", todayML / 1000.0)
            : "\(Int(todayML)) ml"
    }

    private var goalDisplay: String {
        let remaining = dailyGoalML - todayML
        if remaining <= 0 { return "Goal reached 🎉" }
        let r = remaining >= 1000
            ? String(format: "%.1f L to go", remaining / 1000.0)
            : "\(Int(remaining)) ml to go"
        return r
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            headerRow
            progressRow
            quickAddRow
        }
        .padding(DesignTokens.Spacing.md)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous))
        .shadow(color: DesignTokens.Shadow.sm.color,
                radius: DesignTokens.Shadow.sm.radius,
                x: 0, y: DesignTokens.Shadow.sm.y)
        .task { await fetchTodayWater() }
        .onChange(of: refreshToken) { _, _ in
            Task { await fetchTodayWater() }
        }
        .sheet(isPresented: $showCustomSheet) {
            CustomWaterSheet { ml in
                Task { await logWater(ml: ml) }
            }
        }
    }

    // MARK: - Sub-views

    private var headerRow: some View {
        HStack {
            Label("Water", systemImage: "drop.fill")
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(Color.blue)
            Spacer()
            if let logged = justLoggedML {
                Text("+\(logged >= 1000 ? String(format: "%.1fL", logged / 1000) : "\(Int(logged))ml") ✓")
                    .font(DesignTokens.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                Text("Goal: 2.5 L / day")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.tertiaryText)
            }
        }
    }

    private var progressRow: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // Circular ring
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        progress >= 1.0 ? Color.green : Color.blue,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.5), value: progress)
                VStack(spacing: 1) {
                    if isLoading {
                        ProgressView().scaleEffect(0.6)
                    } else {
                        Text(displayTotal)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.primaryText)
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiaryText)
                    }
                }
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 6) {
                // Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.blue.opacity(0.12))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(progress >= 1.0 ? Color.green : Color.blue)
                            .frame(width: max(0, geo.size.width * progress), height: 8)
                            .animation(.spring(response: 0.5), value: progress)
                    }
                }
                .frame(height: 8)

                // Axis labels
                HStack {
                    Text("0")
                    Spacer()
                    Text("1 L")
                    Spacer()
                    Text("2.5 L")
                }
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(.tertiaryText)

                Text(goalDisplay)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(progress >= 1.0 ? Color.green : Color.secondary)
                    .animation(.default, value: todayML)
            }
        }
    }

    private var quickAddRow: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(quickAmounts, id: \.ml) { amount in
                Button {
                    Task { await logWater(ml: amount.ml) }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.blue)
                        Text(amount.label)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.blue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // Custom amount
            Button {
                showCustomSheet = true
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.blue)
                    Text("Custom")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.blue)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Data

    func fetchTodayWater() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        isLoading = true
        defer { isLoading = false }
        let mL = await queryTodayWaterML()
        withAnimation { todayML = mL }
    }

    /// Queries HealthKit for today's cumulative water total (mL) without touching UI state.
    /// Uses `HKStatisticsQuery` (single-shot, all sources) rather than the collection
    /// variant so there is no bucket-alignment edge case around partial days.
    private func queryTodayWaterML() async -> Double {
        guard HKHealthStore.isHealthDataAvailable() else { return todayML }
        let waterType = HKQuantityType(.dietaryWater)
        // Do NOT call requestAuthorization here — that triggers a system dialog.
        // Authorization is handled once during onboarding; HealthKit silently
        // returns empty data if not yet authorized.
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: Date(), options: .strictStartDate
        )
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: waterType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                let mL = result?.sumQuantity()?.doubleValue(for: .literUnit(with: .milli)) ?? 0
                continuation.resume(returning: mL)
            }
            HealthKitService.shared.store.execute(query)
        }
    }

    private func logWater(ml: Double) async {
        guard ml > 0 else { return }
        // Optimistic update for immediate feedback while the write + re-fetch happen.
        withAnimation(.spring(response: 0.4)) { todayML += ml }
        triggerHaptic(.success)
        withAnimation { justLoggedML = ml }
        do {
            try await HealthKitWriter.shared.logWater(milliliters: ml, at: Date())
            // Silent re-fetch to sync with real HealthKit total (all sources, all apps).
            let real = await queryTodayWaterML()
            withAnimation { todayML = real }
        } catch {
            // Revert optimistic update on failure.
            withAnimation { todayML = max(0, todayML - ml) }
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        withAnimation { justLoggedML = nil }
    }
}

// MARK: - CustomWaterSheet

struct CustomWaterSheet: View {
    var onLog: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String = ""
    @State private var unit: WaterUnit = .ml
    @FocusState private var focused: Bool

    enum WaterUnit: String, CaseIterable {
        case ml = "ml"
        case litres = "L"

        var factor: Double { self == .litres ? 1000 : 1 }
    }

    private var parsed: Double? {
        guard let v = Double(amountText.replacingOccurrences(of: ",", with: ".")),
              v > 0 else { return nil }
        return v * unit.factor
    }

    private var isValid: Bool { (parsed ?? 0) > 0 && (parsed ?? 0) <= 10_000 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                            .focused($focused)
                        Picker("", selection: $unit) {
                            ForEach(WaterUnit.allCases, id: \.self) { u in
                                Text(u.rawValue).tag(u)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 100)
                    }
                } header: {
                    Text("How much did you drink?")
                } footer: {
                    if let ml = parsed {
                        Text(ml >= 1000
                             ? String(format: "= %.2f litres", ml / 1000.0)
                             : "= \(Int(ml)) ml")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    // Quick preset chips so the user can tap instead of type
                    let presets: [(String, Double)] = [("150 ml", 150), ("250 ml", 250),
                                                       ("350 ml", 350), ("500 ml", 500),
                                                       ("750 ml", 750), ("1 L", 1000)]
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                        GridItem(.flexible())], spacing: 10) {
                        ForEach(presets, id: \.1) { label, ml in
                            Button(label) {
                                amountText = ml >= 1000
                                    ? String(format: "%.0f", ml)
                                    : "\(Int(ml))"
                                unit = ml >= 1000 ? .ml : .ml
                            }
                            .font(DesignTokens.Typography.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                } header: {
                    Text("Quick presets")
                }
            }
            .navigationTitle("Log Water")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        if let ml = parsed {
                            onLog(ml)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
