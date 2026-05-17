import SwiftUI

struct NutritionConfirmView: View {
    @State var meal: ScannedMeal
    let viewModel: FoodScanViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var baseNutrition: NutritionPayload
    @State private var servingsText: String = "1"

    init(meal: ScannedMeal, viewModel: FoodScanViewModel) {
        self._meal = State(initialValue: meal)
        self.viewModel = viewModel
        self._baseNutrition = State(initialValue: meal.nutrition)
    }

    private func applyServings() {
        let servings = Double(servingsText) ?? 1.0
        guard servings > 0 else { return }
        meal.nutrition = baseNutrition.scaled(by: servings)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: DesignTokens.Spacing.lg) {
                        thumbnailSection
                        identitySection
                        nutritionGrid
                        actionButtons
                        Spacer(minLength: DesignTokens.Spacing.xxl)
                    }
                    .padding(.top, DesignTokens.Spacing.sm)
                }
            }
            .navigationTitle("Confirm Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if viewModel.isLoading {
                    loggingOverlay
                }
            }
            .onChange(of: viewModel.state) { _, newState in
                if case .success = newState { dismiss() }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var thumbnailSection: some View {
        if let data = meal.imageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(height: 200)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
                .padding(.horizontal, DesignTokens.Spacing.md)
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Food name", text: $meal.foodName)
                        .font(DesignTokens.Typography.title3)
                        .foregroundStyle(.primaryText)
                    TextField("Serving size", text: $meal.servingSize)
                        .font(DesignTokens.Typography.subheadline)
                        .foregroundStyle(.secondaryText)
                }
                Spacer()
                confidenceBadge
            }

            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: "square.stack.3d.up")
                    .font(.caption2)
                    .foregroundStyle(.tertiaryText)
                Text("Servings")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondaryText)
                TextField("1", text: $servingsText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 52)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.fillQuaternary)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
                    .font(DesignTokens.Typography.subheadline.weight(.semibold))
                    .onChange(of: servingsText) { _, _ in applyServings() }
                Text("× per serving")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.tertiaryText)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    private var confidenceBadge: some View {
        let (label, color): (String, Color) = {
            switch meal.confidence.lowercased() {
            case "high":   return ("High", .green)
            case "medium": return ("Medium", .orange)
            default:       return ("Low", .red)
            }
        }()
        return Text(label)
            .font(DesignTokens.Typography.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Nutrition sections

    private struct NutritionSection {
        let title: String
        let fields: [(label: String, unit: String, keyPath: WritableKeyPath<NutritionPayload, Double>)]
    }

    private var nutritionSections: [NutritionSection] {
        [
            NutritionSection(title: "Energy & Macros", fields: [
                ("Calories",   "kcal", \.calories),
                ("Protein",    "g",    \.protein),
                ("Carbs",      "g",    \.carbohydrates),
                ("Fat",        "g",    \.fat),
                ("Fiber",      "g",    \.fiber),
                ("Sugar",      "g",    \.sugar),
            ]),
            NutritionSection(title: "Fats", fields: [
                ("Saturated",      "g", \.saturatedFat),
                ("Monounsaturated","g", \.monounsaturatedFat),
                ("Polyunsaturated","g", \.polyunsaturatedFat),
            ]),
            NutritionSection(title: "Minerals", fields: [
                ("Sodium",     "mg", \.sodium),
                ("Potassium",  "mg", \.potassium),
                ("Calcium",    "mg", \.calcium),
                ("Iron",       "mg", \.iron),
                ("Zinc",       "mg", \.zinc),
                ("Magnesium",  "mg", \.magnesium),
                ("Cholesterol","mg", \.cholesterol),
            ]),
            NutritionSection(title: "Vitamins", fields: [
                ("Vitamin A",  "mcg", \.vitaminA),
                ("Vitamin C",  "mg",  \.vitaminC),
                ("Vitamin D",  "mcg", \.vitaminD),
                ("Vitamin B6", "mg",  \.vitaminB6),
                ("Vitamin B12","mcg", \.vitaminB12),
                ("Folate",     "mcg", \.folate),
            ]),
            NutritionSection(title: "Other", fields: [
                ("Water", "mL", \.water),
            ]),
        ]
    }

    private var nutritionGrid: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            ForEach(nutritionSections, id: \.title) { section in
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    Text(section.title)
                        .font(DesignTokens.Typography.headline)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: DesignTokens.Spacing.sm
                    ) {
                        ForEach(section.fields, id: \.label) { field in
                            NutrientField(
                                label: field.label,
                                unit: field.unit,
                                value: Binding(
                                    get: { meal.nutrition[keyPath: field.keyPath] },
                                    set: { meal.nutrition[keyPath: field.keyPath] = $0 }
                                )
                            )
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                }
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Button {
                triggerHaptic(.medium)
                Task { await viewModel.confirmAndLog(meal) }
            } label: {
                Label("Log to Apple Health", systemImage: "heart.text.square.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
            .padding(.horizontal, DesignTokens.Spacing.md)

            Button("Cancel") {
                dismiss()
            }
            .font(DesignTokens.Typography.subheadline)
            .foregroundStyle(.secondaryText)
        }
    }

    private var loggingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: DesignTokens.Spacing.md) {
                ProgressView().scaleEffect(1.3).tint(.white)
                Text("Saving to Apple Health…")
                    .font(DesignTokens.Typography.headline)
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Nutrient Field

private struct NutrientField: View {
    let label: String
    let unit: String
    @Binding var value: Double

    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondaryText)
            HStack(spacing: 2) {
                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .font(DesignTokens.Typography.headline)
                    .foregroundStyle(.primaryText)
                    .onChange(of: text) { _, newValue in
                        if let d = Double(newValue) { value = d }
                    }
                Text(unit)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.tertiaryText)
            }
            Divider()
        }
        .onAppear { text = formatted(value) }
        .onChange(of: value) { _, newValue in
            // Sync display text when value is updated externally (e.g. serving recalculation),
            // but skip the update if the user is actively typing the same number.
            let current = Double(text) ?? 0
            if abs(current - newValue) > 0.001 {
                text = formatted(newValue)
            }
        }
    }

    private func formatted(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }
}
