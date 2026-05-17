import SwiftUI

@MainActor
@Observable
final class InsightsViewModel {
    var expandedCategory: HealthCategory?
    var selectedCategories: Set<HealthCategory> = Set(HealthCategory.allCases)
    var searchText: String = ""

    var filteredCategories: [HealthCategory] {
        let filtered = HealthCategory.allCases.filter { selectedCategories.contains($0) }
        if searchText.isEmpty { return filtered }
        return filtered.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    func toggleCategory(_ category: HealthCategory) {
        if selectedCategories.contains(category) {
            if selectedCategories.count > 1 {  // Keep at least one selected
                selectedCategories.remove(category)
            }
        } else {
            selectedCategories.insert(category)
        }
    }

    func toggleExpanded(_ category: HealthCategory) {
        withAnimation(DesignTokens.Animation.standard) {
            expandedCategory = expandedCategory == category ? nil : category
        }
    }
}
