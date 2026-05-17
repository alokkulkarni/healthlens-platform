import SwiftUI

// MARK: - Meal History Detail View

struct MealHistoryDetailView: View {
    let meal: ScannedMeal
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: DesignTokens.Spacing.lg) {
                        thumbnailSection
                        identitySection
                        nutritionSectionsView
                        Spacer(minLength: DesignTokens.Spacing.xxl)
                    }
                    .padding(.top, DesignTokens.Spacing.sm)
                }
            }
            .navigationTitle("Meal Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.foodName)
                        .font(DesignTokens.Typography.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primaryText)
                    if !meal.servingSize.isEmpty {
                        Text(meal.servingSize)
                            .font(DesignTokens.Typography.subheadline)
                            .foregroundStyle(.secondaryText)
                    }
                }
                Spacer()
                confidenceBadge
            }
            Text(meal.scannedAt, style: .date)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.tertiaryText)
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

    private var nutritionSectionsView: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            ForEach(sections, id: \.title) { section in
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    Text(section.title)
                        .font(DesignTokens.Typography.headline)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: DesignTokens.Spacing.sm
                    ) {
                        ForEach(section.fields, id: \.label) { field in
                            readOnlyNutrientCell(label: field.label, unit: field.unit, value: meal.nutrition[keyPath: field.keyPath])
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                }
            }
        }
    }

    private func readOnlyNutrientCell(label: String, unit: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondaryText)
            HStack(spacing: 2) {
                let formatted = value.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int(value))
                    : String(format: "%.1f", value)
                Text(formatted)
                    .font(DesignTokens.Typography.headline)
                    .foregroundStyle(.primaryText)
                Text(unit)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.tertiaryText)
            }
            Divider()
        }
    }

    // MARK: - Nutrition section definitions

    private struct SectionDef {
        let title: String
        let fields: [(label: String, unit: String, keyPath: KeyPath<NutritionPayload, Double>)]
    }

    private var sections: [SectionDef] {
        [
            SectionDef(title: "Energy & Macros", fields: [
                ("Calories",    "kcal", \.calories),
                ("Protein",     "g",    \.protein),
                ("Carbs",       "g",    \.carbohydrates),
                ("Fat",         "g",    \.fat),
                ("Fiber",       "g",    \.fiber),
                ("Sugar",       "g",    \.sugar),
            ]),
            SectionDef(title: "Fats", fields: [
                ("Saturated",       "g", \.saturatedFat),
                ("Monounsaturated", "g", \.monounsaturatedFat),
                ("Polyunsaturated", "g", \.polyunsaturatedFat),
            ]),
            SectionDef(title: "Minerals", fields: [
                ("Sodium",      "mg", \.sodium),
                ("Potassium",   "mg", \.potassium),
                ("Calcium",     "mg", \.calcium),
                ("Iron",        "mg", \.iron),
                ("Zinc",        "mg", \.zinc),
                ("Magnesium",   "mg", \.magnesium),
                ("Cholesterol", "mg", \.cholesterol),
            ]),
            SectionDef(title: "Vitamins", fields: [
                ("Vitamin A",   "mcg", \.vitaminA),
                ("Vitamin C",   "mg",  \.vitaminC),
                ("Vitamin D",   "mcg", \.vitaminD),
                ("Vitamin B6",  "mg",  \.vitaminB6),
                ("Vitamin B12", "mcg", \.vitaminB12),
                ("Folate",      "mcg", \.folate),
            ]),
            SectionDef(title: "Other", fields: [
                ("Water", "mL", \.water),
            ]),
        ]
    }
}

// MARK: - All Meals View

struct AllMealsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMeal: ScannedMeal? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryBackground.ignoresSafeArea()
                let meals = MealLogStore.shared.meals
                if meals.isEmpty {
                    VStack(spacing: DesignTokens.Spacing.sm) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiaryText)
                        Text("No meals logged yet")
                            .font(DesignTokens.Typography.headline)
                            .foregroundStyle(.secondaryText)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: DesignTokens.Spacing.sm) {
                            ForEach(meals.prefix(20)) { meal in
                                Button { selectedMeal = meal } label: {
                                    mealRow(meal)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, DesignTokens.Spacing.sm)
                        .padding(.bottom, DesignTokens.Spacing.xxl)
                    }
                }
            }
            .navigationTitle("All Meals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedMeal) { meal in
                MealHistoryDetailView(meal: meal)
            }
        }
    }

    private func mealRow(_ meal: ScannedMeal) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.foodName)
                    .font(DesignTokens.Typography.headline)
                    .foregroundStyle(.primaryText)
                Text(meal.servingSize.isEmpty ? "1 serving" : meal.servingSize)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(meal.nutrition.calories)) kcal")
                    .font(DesignTokens.Typography.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primaryText)
                Text(meal.scannedAt, style: .date)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondaryText)
            }
        }
        .card()
        .padding(.horizontal, DesignTokens.Spacing.md)
    }
}
