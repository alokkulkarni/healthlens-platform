import SwiftUI
import SwiftData

struct HealthPermissionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var prefsList: [UserPreferences]
    @State private var isRequesting: HealthCategory? = nil
    @State private var requestError: String?

    private var prefs: UserPreferences { prefsList.first ?? UserPreferences.fetch(in: modelContext) }

    var body: some View {
        List {
            Section {
                Text("HealthLens requests permissions category by category. Granting more categories allows richer AI analysis.")
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(.secondaryText)
            }

            ForEach(HealthKitPermissions.allGroups, id: \.tier) { group in
                Section(header: Text("Tier \(group.tier + 1): \(group.title)")) {
                    ForEach(group.categories, id: \.rawValue) { category in
                        categoryRow(category, group: group)
                    }
                }
            }
        }
        .navigationTitle("Health Permissions")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func categoryRow(_ category: HealthCategory, group: PermissionGroup) -> some View {
        let isGranted = prefs.isHealthCategoryGranted(category)

        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: category.systemImage)
                .font(.body)
                .foregroundStyle(category.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.displayName)
                    .font(DesignTokens.Typography.body)
                HStack(spacing: 4) {
                    Circle()
                        .fill(isGranted ? Color.healthGood : Color.fillTertiary)
                        .frame(width: 6, height: 6)
                    Text(isGranted ? "Granted" : "Not granted")
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(.secondaryText)
                }
            }

            Spacer()

            if isRequesting == category {
                ProgressView().scaleEffect(0.8)
            } else if !isGranted && HealthKitService.shared.isAvailable {
                Button("Grant") {
                    Task { await requestPermission(for: category) }
                }
                .font(DesignTokens.Typography.footnote)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Capsule())
            } else if !HealthKitService.shared.isAvailable {
                Text("Simulator")
                    .font(DesignTokens.Typography.caption2)
                    .foregroundStyle(.tertiaryText)
            }
        }
    }

    private func requestPermission(for category: HealthCategory) async {
        isRequesting = category
        requestError = nil
        do {
            try await HealthKitService.shared.requestAuthorization(for: [category])
            prefs.markCategoryGranted(category)
            try? modelContext.save()
            triggerHaptic(.success)
        } catch {
            requestError = error.localizedDescription
        }
        isRequesting = nil
    }
}
