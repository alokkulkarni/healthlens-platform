import SwiftUI
import SwiftData

struct AppearanceView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var prefsList: [UserPreferences]

    private var prefs: UserPreferences { prefsList.first ?? UserPreferences.fetch(in: modelContext) }

    var body: some View {
        Form {
            Section("Unit System") {
                Picker("Units", selection: Binding(
                    get: { prefs.preferredUnitSystem },
                    set: { prefs.preferredUnitSystem = $0; try? modelContext.save() }
                )) {
                    Text("Metric (kg, km)").tag("metric")
                    Text("Imperial (lbs, miles)").tag("imperial")
                }
                .pickerStyle(.segmented)
            }

            Section("Default Date Range") {
                Picker("Date Range", selection: Binding(
                    get: { prefs.defaultDateRangeDays },
                    set: { prefs.defaultDateRangeDays = $0; try? modelContext.save() }
                )) {
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                    Text("60 days").tag(60)
                    Text("90 days").tag(90)
                }
            }

            Section("Background Refresh") {
                Toggle("Refresh Health Data in Background", isOn: Binding(
                    get: { prefs.enableBackgroundRefresh },
                    set: {
                        prefs.enableBackgroundRefresh = $0
                        try? modelContext.save()
                        if $0 {
                            Task { await BackgroundObserver.shared.scheduleNextBackgroundRefresh() }
                        }
                    }
                ))
                Text("Keeps health data up to date for faster analysis.")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.tertiaryText)
            }
        }
        .navigationTitle("Appearance & Data")
        .navigationBarTitleDisplayMode(.inline)
    }
}
