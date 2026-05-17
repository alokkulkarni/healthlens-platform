import SwiftUI
import SwiftData

struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @Environment(\.modelContext) private var modelContext
    @Query private var allSessions: [AnalysisSession]
    @Query private var prefsList: [UserPreferences]

    private var prefs: UserPreferences { prefsList.first ?? UserPreferences.fetch(in: modelContext) }

    var body: some View {
        List {
            // AI Providers section
            Section {
                ForEach(AIProviderType.allCases, id: \.self) { provider in
                    AIProviderRow(provider: provider)
                }
            } header: {
                Label("AI Providers", systemImage: "brain.head.profile")
            } footer: {
                Text("Configure API keys for each provider. On-Device requires no key but needs Apple Intelligence.")
            }

            // Active model section
            Section {
                HStack {
                    Text("Active Provider")
                    Spacer()
                    Text(prefs.activeProvider.displayName)
                        .foregroundStyle(.secondaryText)
                }

                HStack {
                    Text("Active Model")
                    Spacer()
                    Text(prefs.activeModelID)
                        .foregroundStyle(.secondaryText)
                        .font(DesignTokens.Typography.footnote)
                }
            } header: {
                Label("Current Selection", systemImage: "cpu")
            }

            // Siri & Shortcuts
            Section {
                NavigationLink(destination: SiriShortcutsView()) {
                    Label("Siri & Shortcuts", systemImage: "mic.fill")
                }
                Text("Log water, describe meals, and scan food with Siri — without opening the app.")
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(.secondaryText)
            } header: {
                Label("Siri", systemImage: "mic.fill")
            }

            // Health Permissions
            Section {
                NavigationLink(destination: HealthPermissionsView()) {
                    Label("Health Permissions", systemImage: "heart.text.clipboard")
                }
                HStack {
                    Text("Categories Granted")
                    Spacer()
                    Text("\(prefs.grantedHealthCategories.count) / \(HealthCategory.allCases.count)")
                        .foregroundStyle(.secondaryText)
                        .font(DesignTokens.Typography.footnote)
                }
            } header: {
                Label("Health Data", systemImage: "heart.fill")
            }

            // Appearance & Data
            Section {
                NavigationLink(destination: AppearanceView()) {
                    Label("Appearance & Data", systemImage: "paintbrush")
                }
                HStack {
                    Text("Unit System")
                    Spacer()
                    Text(prefs.preferredUnitSystem == "metric" ? "Metric" : "Imperial")
                        .foregroundStyle(.secondaryText)
                }
                HStack {
                    Text("Default Date Range")
                    Spacer()
                    Text("\(prefs.defaultDateRangeDays) days")
                        .foregroundStyle(.secondaryText)
                }
            } header: {
                Label("Preferences", systemImage: "slider.horizontal.3")
            }

            // Storage
            Section {
                HStack {
                    Text("Saved Analyses")
                    Spacer()
                    Text("\(viewModel.totalSessionCount)")
                        .foregroundStyle(.secondaryText)
                }
                HStack {
                    Text("Estimated Size")
                    Spacer()
                    Text(viewModel.totalDataSize)
                        .foregroundStyle(.secondaryText)
                }
                Button("Clear All Analysis History", role: .destructive) {
                    viewModel.showDeleteConfirmation = true
                }
            } header: {
                Label("Storage", systemImage: "internaldrive")
            }

            // About
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(viewModel.appVersion)
                        .foregroundStyle(.secondaryText)
                }
                HStack {
                    Text("Build")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                        .foregroundStyle(.secondaryText)
                }
                NavigationLink(destination: TermsView()) {
                    Label("Terms & Disclaimer", systemImage: "doc.text.fill")
                }
                if let privacyURL = URL(string: "https://healthlens.app/privacy") {
                    Link(destination: privacyURL) {
                        Label("Privacy Policy", systemImage: "lock.shield")
                    }
                }
            } header: {
                Label("About", systemImage: "info.circle")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            viewModel.loadStats(sessions: allSessions)
        }
        .onChange(of: allSessions.count) { _, _ in
            viewModel.loadStats(sessions: allSessions)
        }
        .confirmationDialog(
            "Delete All History?",
            isPresented: $viewModel.showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All \(viewModel.totalSessionCount) Sessions", role: .destructive) {
                allSessions.forEach { modelContext.delete($0) }
                try? modelContext.save()
                triggerHaptic(.warning)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(viewModel.totalSessionCount) saved analyses. This cannot be undone.")
        }
    }
}
