import SwiftUI
import AppIntents
import HealthKit

// MARK: - Siri Shortcuts Settings View

struct SiriShortcutsView: View {
    @State private var hasHealthKitWriteAccess: Bool = true
    @State private var isRequestingAccess: Bool = false

    var body: some View {
        List {
            // HealthKit permissions banner (shown when write access is missing)
            if !hasHealthKitWriteAccess {
                Section {
                    healthKitPermissionBanner
                }
            }

            // Overview banner
            Section {
                overviewCard
            }

            // Water
            Section {
                SiriTipView(intent: LogWaterIntent())
                commandRow(phrase: "\"Add 150ml of water to HealthLens\"", icon: "drop.fill", color: .blue)
                commandRow(phrase: "\"Log water in HealthLens\"",          icon: "drop.fill", color: .blue)
            } header: {
                Label("Hydration", systemImage: "drop.fill")
            } footer: {
                Text("Siri will ask how much you drank if you don't say an amount.")
            }

            // Describe Meal
            Section {
                SiriTipView(intent: DescribeMealIntent())
                commandRow(phrase: "\"Describe a meal in HealthLens\"", icon: "text.bubble.fill", color: .green)
                commandRow(phrase: "\"Log what I ate in HealthLens\"",  icon: "text.bubble.fill", color: .green)
                commandRow(phrase: "\"Tell HealthLens what I ate\"",    icon: "text.bubble.fill", color: .green)
            } header: {
                Label("Describe a Meal", systemImage: "text.bubble.fill")
            } footer: {
                Text("AI analyses your description and shows a nutrition summary. You confirm before it's logged.")
            }

            // Scan Meal
            Section {
                SiriTipView(intent: ScanMealIntent())
                commandRow(phrase: "\"Scan a meal in HealthLens\"",       icon: "camera.viewfinder", color: .orange)
                commandRow(phrase: "\"Take a food photo in HealthLens\"", icon: "camera.viewfinder", color: .orange)
            } header: {
                Label("Scan a Meal", systemImage: "camera.viewfinder")
            } footer: {
                Text("Opens the HealthLens camera directly so you can photograph and log your meal.")
            }

            // Weight
            Section {
                SiriTipView(intent: LogWeightIntent())
                commandRow(phrase: "\"Log my weight in HealthLens\"",  icon: "scalemass.fill", color: .purple)
                commandRow(phrase: "\"Record weight in HealthLens\"",  icon: "scalemass.fill", color: .purple)
            } header: {
                Label("Body Weight", systemImage: "scalemass.fill")
            } footer: {
                Text("Siri will ask for your weight in kilograms if not provided.")
            }

            // Shortcuts App tip
            Section {
                shortcutsAppRow
            } footer: {
                Text("You can also add these to the Shortcuts app to create automations, widgets, and custom phrases.")
            }
        }
        .navigationTitle("Siri & Shortcuts")
        .navigationBarTitleDisplayMode(.large)
        .task {
            refreshPermissionState()
        }
    }

    // MARK: - Permission Banner

    private var healthKitPermissionBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 18))
                Text("HealthKit Write Access Needed")
                    .font(.system(size: 15, weight: .semibold))
            }
            Text("Siri intents need permission to write water, weight, and nutrition data to Apple Health. Grant access to log hands-free.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button {
                Task { await requestAccess() }
            } label: {
                HStack {
                    if isRequestingAccess {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Text(isRequestingAccess ? "Requesting…" : "Grant HealthKit Access")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.orange)
            }
            .disabled(isRequestingAccess)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func refreshPermissionState() {
        hasHealthKitWriteAccess = HealthKitService.shared.hasSiriWriteAccess()
    }

    private func requestAccess() async {
        isRequestingAccess = true
        await HealthKitService.shared.ensureSiriWriteTypes()
        isRequestingAccess = false
        refreshPermissionState()
    }

    // MARK: - Shared Subviews

    private var overviewCard: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                Image(systemName: "mic.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Use Siri Hands-Free")
                    .font(.headline)
                Text("Log water, describe meals, and scan food with Siri — without ever opening the app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func commandRow(phrase: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 20)
            Text(phrase)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .italic()
        }
    }

    private var shortcutsAppRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 16))
                .foregroundStyle(.indigo)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Open Shortcuts App")
                    .font(.subheadline)
                Text("Create advanced automations with HealthLens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = URL(string: "shortcuts://") {
                UIApplication.shared.open(url)
            }
        }
    }
}
