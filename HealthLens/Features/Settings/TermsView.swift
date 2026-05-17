import SwiftUI

/// Displays the app disclaimer and terms of use.
/// Shown during onboarding (with an acknowledgement button) and accessible
/// any time from Settings → About.
struct TermsView: View {
    /// When non-nil the view shows an "I Understand" button and calls this on tap.
    var onAcknowledge: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Label("Important Notice", systemImage: "cross.case.fill")
                        .font(.title2).fontWeight(.bold)
                        .foregroundStyle(.primaryText)
                    Text("Please read before using HealthLens")
                        .font(.subheadline)
                        .foregroundStyle(.secondaryText)
                }

                Divider()

                // ── Section 1 ─────────────────────────────────────────────
                termsSection(
                    icon: "stethoscope",
                    iconColor: .red,
                    title: "Not Medical Advice",
                    body: """
                    HealthLens is an informational wellness tool only. \
                    The insights, trend analyses, and AI-generated responses provided by this app are \
                    for general information purposes and do not constitute medical advice, diagnosis, or treatment.

                    If you experience symptoms, pain, or any change in your health, please consult a \
                    qualified healthcare professional promptly. Do not delay seeking medical attention \
                    based on anything you read in this app.
                    """
                )

                // ── Section 2 ─────────────────────────────────────────────
                termsSection(
                    icon: "brain.head.profile",
                    iconColor: .blue,
                    title: "AI Limitations",
                    body: """
                    The artificial intelligence models used in HealthLens — whether on-device or \
                    cloud-based — analyse patterns in your health data but can make errors, miss \
                    context, or misinterpret data. AI responses should never replace a conversation \
                    with your doctor, nurse, or other licensed clinician.

                    AI models do not have access to your full medical history, medication list, \
                    allergies, or clinical context. Always involve a healthcare professional in any \
                    clinical decision.
                    """
                )

                // ── Section 3 ─────────────────────────────────────────────
                termsSection(
                    icon: "lock.shield.fill",
                    iconColor: .green,
                    title: "Your Data & Privacy",
                    body: """
                    HealthLens reads health data you explicitly grant access to via Apple HealthKit. \
                    This data is processed locally on your device. If you choose to use a cloud AI \
                    provider (Claude, Gemini, or AWS Bedrock), anonymised health metrics are sent \
                    to that provider's servers to generate a response. No data is sold or shared \
                    with third parties for advertising.

                    You can revoke health data access at any time via Settings → Health Permissions \
                    or through iOS Settings → Privacy & Security → Health.
                    """
                )

                // ── Section 4 ─────────────────────────────────────────────
                termsSection(
                    icon: "heart.text.clipboard",
                    iconColor: .orange,
                    title: "Emergency Situations",
                    body: """
                    HealthLens is not designed for emergency use. If you or someone else is \
                    experiencing a medical emergency — such as chest pain, difficulty breathing, \
                    loss of consciousness, or severe injury — call your local emergency services \
                    immediately (e.g. 999 in the UK, 911 in the US, 112 in the EU).
                    """
                )

                // ── Section 5 ─────────────────────────────────────────────
                termsSection(
                    icon: "chart.xyaxis.line",
                    iconColor: .purple,
                    title: "Data Accuracy",
                    body: """
                    The accuracy of insights depends entirely on the quality and completeness of \
                    the data recorded in Apple Health. Sensor readings from Apple Watch or third-party \
                    devices may contain measurement errors. HealthLens does not validate, verify, or \
                    correct raw health data.
                    """
                )

                // ── Section 6 ─────────────────────────────────────────────
                termsSection(
                    icon: "checkmark.seal.fill",
                    iconColor: .teal,
                    title: "Acceptance of Terms",
                    body: """
                    By using HealthLens you acknowledge that:
                    • This app is a personal wellness companion, not a regulated medical device.
                    • All AI-generated content is informational only.
                    • You will seek professional medical advice for any health concerns.
                    • The developers of HealthLens accept no liability for decisions made based on \
                      information provided by this app.
                    """
                )

                // Version stamp
                Text("HealthLens · Terms last updated April 2025")
                    .font(.caption2)
                    .foregroundStyle(.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)

                // Acknowledge button (onboarding only)
                if let acknowledge = onAcknowledge {
                    Button {
                        triggerHaptic(.medium)
                        acknowledge()
                    } label: {
                        Text("I Understand — Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.top, 8)
                }
            }
            .padding(20)
        }
        .background(Color.primaryBackground)
        .navigationTitle("Terms & Disclaimer")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Section builder

    private func termsSection(icon: String, iconColor: Color, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 28, height: 28)
                    .background(iconColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primaryText)
            }

            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondaryText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        TermsView()
    }
}
