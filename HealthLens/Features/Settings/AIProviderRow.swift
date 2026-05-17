import SwiftUI

struct AIProviderRow: View {
    let provider: AIProviderType
    @State private var showKeyEntry = false
    @State private var keyConfigured = false
    @Environment(AppEnvironment.self) private var appEnv

    private var keyStore: APIKeyStore { appEnv.apiKeyStore }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // Provider icon
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: provider.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(.primaryText)
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(.secondaryText)
                }
            }

            Spacer()

            if provider.requiresAPIKey {
                Button(keyConfigured ? "Update" : "Configure") {
                    showKeyEntry = true
                }
                .font(DesignTokens.Typography.footnote)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Capsule())
            } else {
                Text("Ready")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.healthGood)
            }
        }
        .onAppear { refreshKeyStatus() }
        .onChange(of: showKeyEntry) { _, isShowing in
            // Re-read Keychain when the entry sheet is dismissed
            if !isShowing { refreshKeyStatus() }
        }
        .sheet(isPresented: $showKeyEntry) {
            APIKeyEntryView(provider: provider)
        }
    }

    private func refreshKeyStatus() {
        keyConfigured = keyStore.hasKey(for: provider)
    }

    private var statusColor: Color {
        if !provider.requiresAPIKey { return .healthGood }
        return keyConfigured ? .healthGood : .healthWarning
    }

    private var statusText: String {
        if !provider.requiresAPIKey { return "Ready (on-device)" }
        return keyConfigured ? "API key configured" : "API key required"
    }
}
