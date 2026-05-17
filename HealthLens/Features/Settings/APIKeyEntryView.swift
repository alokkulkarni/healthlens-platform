import SwiftUI

struct APIKeyEntryView: View {
    let provider: AIProviderType
    @State private var apiKey: String = ""
    @State private var secretKey: String = ""
    @State private var sessionToken: String = ""
    @State private var isSaving: Bool = false
    @State private var saveError: String?
    @State private var saveSuccess: Bool = false
    @State private var showKey: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var appEnv

    private var keyStore: APIKeyStore { appEnv.apiKeyStore }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    switch provider {
                    case .claude:
                        claudeSection
                    case .gemini:
                        geminiSection
                    case .bedrock:
                        bedrockSection
                    case .onDevice:
                        onDeviceSection
                    }
                } header: {
                    Text("API Credentials")
                } footer: {
                    Text("Keys are stored securely in the iOS Keychain and never leave your device unencrypted.")
                        .font(DesignTokens.Typography.caption)
                }

                if let error = saveError {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(DesignTokens.Typography.footnote)
                                .foregroundStyle(.primaryText)
                        }
                    }
                }

                Section {
                    Button {
                        save()
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView().scaleEffect(0.9)
                            } else if saveSuccess {
                                Label("Saved", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Text("Save API Key")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSaving || (apiKey.trimmingCharacters(in: .whitespaces).isEmpty))
                }

                if keyStore.hasKey(for: provider) {
                    Section {
                        Button("Remove Saved Key", role: .destructive) {
                            removeKey()
                        }
                    }
                }
            }
            .navigationTitle("\(provider.displayName) Credentials")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { loadExisting() }
        }
    }

    private var claudeSection: some View {
        Group {
            HStack {
                Text("API Key")
                    .foregroundStyle(.secondaryText)
                Spacer()
                if showKey {
                    TextField("sk-ant-api03-...", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } else {
                    SecureField("sk-ant-api03-...", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Button { showKey.toggle() } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                        .font(.caption)
                        .foregroundStyle(.secondaryText)
                }
            }
            Text("Get your API key from console.anthropic.com")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.tertiaryText)
        }
    }

    private var geminiSection: some View {
        Group {
            HStack {
                Text("API Key")
                    .foregroundStyle(.secondaryText)
                Spacer()
                SecureField("AIzaSy...", text: $apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            Text("Get your API key from aistudio.google.com")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.tertiaryText)
        }
    }

    private var bedrockSection: some View {
        Group {
            HStack {
                Text("Access Key ID")
                Spacer()
                SecureField("AKIA...", text: $apiKey)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            HStack {
                Text("Secret Access Key")
                Spacer()
                SecureField("Secret...", text: $secretKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            HStack {
                Text("Session Token")
                Spacer()
                SecureField("Optional", text: $sessionToken)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            Text("Use an IAM user with AmazonBedrockFullAccess or least-privilege policy.")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.tertiaryText)
        }
    }

    private var onDeviceSection: some View {
        Text("On-device AI requires no API key. It uses Apple Intelligence (FoundationModels) available on iPhone 15 Pro and later running iOS 26+.")
            .font(DesignTokens.Typography.body)
            .foregroundStyle(.secondaryText)
    }

    private static let maskedPlaceholder = "••••••••••••••••"

    private func save() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
        // Don't overwrite an existing key with the masked placeholder
        guard trimmedKey != Self.maskedPlaceholder else {
            dismiss()
            return
        }
        isSaving = true
        saveError = nil
        saveSuccess = false
        do {
            switch provider {
            case .claude:
                try keyStore.saveClaudeKey(trimmedKey)
            case .gemini:
                try keyStore.saveGeminiKey(trimmedKey)
            case .bedrock:
                try keyStore.saveBedrockCredentials(
                    accessKey: trimmedKey,
                    secretKey: secretKey.trimmingCharacters(in: .whitespaces),
                    sessionToken: sessionToken.isEmpty ? nil : sessionToken
                )
            case .onDevice:
                break
            }
            triggerHaptic(.success)
            saveSuccess = true
            appEnv.aiRouter.invalidateCache(for: provider)
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                dismiss()
            }
        } catch {
            saveError = error.localizedDescription
            triggerHaptic(.error)
        }
        isSaving = false
    }

    private func removeKey() {
        try? {
            switch provider {
            case .claude:   try keyStore.deleteClaudeKey()
            case .gemini:   try keyStore.deleteGeminiKey()
            case .bedrock:  try keyStore.deleteBedrockCredentials()
            case .onDevice: break
            }
        }()
        triggerHaptic(.warning)
        dismiss()
    }

    private func loadExisting() {
        // Show masked placeholder to indicate a key is saved.
        // The placeholder is stripped in save() so it never overwrites the real key.
        if keyStore.hasKey(for: provider) {
            apiKey = Self.maskedPlaceholder
        }
    }
}
