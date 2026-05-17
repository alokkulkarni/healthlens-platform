import SwiftUI

struct InsightsView: View {
    @State private var viewModel = InsightsViewModel()
    @State private var refreshToken: Int = 0
    @Environment(NavigationRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            LazyVStack(spacing: DesignTokens.Spacing.sm) {
                // Category filter chips
                categoryFilterRow

                // Category cards
                ForEach(viewModel.filteredCategories, id: \.rawValue) { category in
                    CategoryInsightCard(
                        category: category,
                        isExpanded: viewModel.expandedCategory == category,
                        refreshToken: refreshToken
                    )
                    .padding(.horizontal, DesignTokens.Spacing.md)
                }

                Spacer(minLength: DesignTokens.Spacing.xxl)
            }
            .padding(.top, DesignTokens.Spacing.sm)
        }
        .refreshable {
            refreshToken += 1
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshToken += 1
            }
        }
        .background(Color.primaryBackground)
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $viewModel.searchText, prompt: "Search categories")
    }

    private var categoryFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                // All button
                filterChip(
                    label: "All",
                    icon: "square.grid.2x2",
                    isSelected: viewModel.selectedCategories.count == HealthCategory.allCases.count
                ) {
                    withAnimation(DesignTokens.Animation.fast) {
                        viewModel.selectedCategories = Set(HealthCategory.allCases)
                    }
                }

                ForEach(HealthCategory.allCases, id: \.rawValue) { category in
                    filterChip(
                        label: category.displayName,
                        icon: category.systemImage,
                        color: category.color,
                        isSelected: viewModel.selectedCategories.contains(category)
                    ) {
                        triggerHaptic(.selection)
                        withAnimation(DesignTokens.Animation.fast) {
                            viewModel.toggleCategory(category)
                        }
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
        }
    }

    private func filterChip(
        label: String,
        icon: String,
        color: Color = .accentColor,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(DesignTokens.Typography.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isSelected ? .white : color)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, 6)
            .background(isSelected ? color : color.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
