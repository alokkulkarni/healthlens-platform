import SwiftUI

struct QueryInputBar: View {
    @Binding var text: String
    var isLoading: Bool = false
    var activeProvider: AIProviderType = .claude
    var activeModel: String = ""
    var onSubmit: () -> Void = {}
    var onProviderTap: () -> Void = {}

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(spacing: DesignTokens.Spacing.xs) {
                // Provider chip row (above the text field)
                HStack {
                    Button(action: onProviderTap) {
                        HStack(spacing: 4) {
                            Image(systemName: activeProvider.systemImage)
                                .font(.system(size: 10, weight: .medium))
                            Text(activeProvider.displayName.components(separatedBy: " ").first ?? "")
                                .font(DesignTokens.Typography.caption2)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if isFocused && !text.isEmpty {
                        Text("\(text.count)")
                            .font(DesignTokens.Typography.caption2)
                            .foregroundStyle(.tertiaryText)
                            .monospacedDigit()
                            .transition(.opacity)
                    }

                    if isFocused {
                        Button {
                            isFocused = false
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .scale))
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.top, DesignTokens.Spacing.xs)
                .animation(DesignTokens.Animation.fast, value: isFocused)

                // Input row: text field + send button
                HStack(alignment: .bottom, spacing: DesignTokens.Spacing.sm) {
                    // Expandable text field (grows up to ~6 lines, cursor always at start)
                    TextField("Ask about your health…", text: $text, axis: .vertical)
                        .font(DesignTokens.Typography.body)
                        .lineLimit(1...6)
                        .focused($isFocused)
                        .submitLabel(.send)
                        .onSubmit {
                            if canSend {
                                triggerHaptic(.medium)
                                isFocused = false
                                onSubmit()
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.fillSecondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .strokeBorder(
                                            isFocused ? Color.accentColor.opacity(0.5) : Color.clear,
                                            lineWidth: 1.5
                                        )
                                )
                        )
                        .animation(DesignTokens.Animation.fast, value: isFocused)

                    // Send button — aligned to bottom of the input area
                    Button(action: {
                        guard canSend else { return }
                        triggerHaptic(.medium)
                        isFocused = false
                        onSubmit()
                    }) {
                        Group {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 34, height: 34)
                        .background(
                            Circle().fill(canSend ? Color.accentColor : Color.fillTertiary)
                        )
                    }
                    .disabled(!canSend && !isLoading)
                    .animation(DesignTokens.Animation.fast, value: canSend)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.sm)
            }
            .background(Color.primaryBackground)
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }
}
