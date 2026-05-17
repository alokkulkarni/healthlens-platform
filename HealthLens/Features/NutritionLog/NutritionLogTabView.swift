import SwiftUI

/// The main tab view for the Nutrition Log tab.
struct NutritionLogTabView: View {
    @State private var showFoodScan = false
    @State private var showDescribeMeal = false
    @State private var describeMealViewModel = FoodScanViewModel()
    @State private var showAllMeals = false
    @State private var selectedMeal: ScannedMeal? = nil
    @Environment(NavigationRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {
                sectionHeader
                entryCards
                waterSection
                recentMealsSection
                Spacer(minLength: DesignTokens.Spacing.xxl)
            }
            .padding(.top, DesignTokens.Spacing.sm)
        }
        .background(Color.primaryBackground)
        .navigationTitle("Nutrition Log")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    triggerHaptic(.medium)
                    showFoodScan = true
                } label: {
                    Label("Add Meal", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                        .font(DesignTokens.Typography.subheadline)
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showFoodScan) {
            FoodScanView()
        }
        .sheet(isPresented: $showDescribeMeal, onDismiss: {
            describeMealViewModel.reset()
        }) {
            DescribeMealSheet(viewModel: describeMealViewModel)
        }
        .sheet(item: $selectedMeal) { meal in
            MealHistoryDetailView(meal: meal)
        }
        .sheet(isPresented: $showAllMeals) {
            AllMealsView()
        }
        // Respond to ScanMealIntent deep link from Siri.
        .onChange(of: router.showFoodScanFromIntent) { _, triggered in
            if triggered {
                showFoodScan = true
                router.showFoodScanFromIntent = false
            }
        }
    }

    // MARK: - Subviews

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("Log Your Meal")
                .font(DesignTokens.Typography.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primaryText)
            Text("Choose how you want to log — take a photo or just describe what you ate.")
                .font(DesignTokens.Typography.footnote)
                .foregroundStyle(.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    private var entryCards: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            // --- Photo scan card ---
            Button {
                triggerHaptic(.medium)
                showFoodScan = true
            } label: {
                entryCard(
                    icon: "camera.viewfinder",
                    iconColors: [Color.orange, Color.orange.opacity(0.7)],
                    title: "Scan a Meal",
                    subtitle: "Take or choose a photo → AI identifies nutrition"
                )
            }
            .buttonStyle(.plain)

            // --- Text describe card ---
            Button {
                triggerHaptic(.medium)
                showDescribeMeal = true
            } label: {
                entryCard(
                    icon: "text.bubble.fill",
                    iconColors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                    title: "Describe a Meal",
                    subtitle: "Type what you ate → AI estimates nutrition"
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    private func entryCard(
        icon: String,
        iconColors: [Color],
        title: String,
        subtitle: String
    ) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: iconColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignTokens.Typography.headline)
                    .foregroundStyle(.primaryText)
                Text(subtitle)
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(.secondaryText)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiaryText)
        }
        .card()
    }

    // MARK: - Water Section

    private var waterSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("Hydration")
                .font(DesignTokens.Typography.headline)
                .padding(.horizontal, DesignTokens.Spacing.md)
            WaterIntakeCard()
                .padding(.horizontal, DesignTokens.Spacing.md)
        }
    }

    // MARK: - Recent Meals Section

    @ViewBuilder
    private var recentMealsSection: some View {
        let store = MealLogStore.shared
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text("Recent Meals")
                    .font(DesignTokens.Typography.headline)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                Spacer()
                if store.meals.count > 5 {
                    Button("See All") {
                        showAllMeals = true
                    }
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, DesignTokens.Spacing.md)
                }
            }

            if store.meals.isEmpty {
                VStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiaryText)
                    Text("No meals logged yet")
                        .font(DesignTokens.Typography.subheadline)
                        .foregroundStyle(.secondaryText)
                    Text("Scan or describe a meal to get started.")
                        .font(DesignTokens.Typography.footnote)
                        .foregroundStyle(.tertiaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.xl)
            } else {
                ForEach(store.meals.prefix(5)) { meal in
                    Button { selectedMeal = meal } label: {
                        mealRow(meal)
                    }
                    .buttonStyle(.plain)
                }
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
