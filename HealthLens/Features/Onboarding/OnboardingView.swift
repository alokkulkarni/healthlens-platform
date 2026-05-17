import SwiftUI
import CoreLocation

struct OnboardingView: View {
    let viewModel: OnboardingViewModel
    var onComplete: () -> Void

    var body: some View {
        OnboardingContent(viewModel: viewModel, onComplete: onComplete)
    }
}

// MARK: - Content Shell

private struct OnboardingContent: View {
    let viewModel: OnboardingViewModel
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            backgroundGradient
                .animation(DesignTokens.Animation.standard, value: viewModel.currentStep)

            VStack(spacing: 0) {
                stepDots
                    .padding(.top, DesignTokens.Spacing.xl)
                    .padding(.bottom, DesignTokens.Spacing.sm)

                // Use ZStack + transitions instead of TabView(.page) to prevent
                // accidental swipe navigation resetting the onboarding step.
                ZStack {
                    switch viewModel.currentStep {
                    case 0: FeatureSlide(slide: .dashboard)
                                .transition(slideTransition(forward: viewModel.stepForward))
                    case 1: FeatureSlide(slide: .askAI)
                                .transition(slideTransition(forward: viewModel.stepForward))
                    case 2: FeatureSlide(slide: .insights)
                                .transition(slideTransition(forward: viewModel.stepForward))
                    case 3: SiriShortcutsSlide()
                                .transition(slideTransition(forward: viewModel.stepForward))
                    case 4: HealthPermissionStep(viewModel: viewModel)
                                .transition(slideTransition(forward: viewModel.stepForward))
                    case 5: LocationPermissionStep(viewModel: viewModel)
                                .transition(slideTransition(forward: viewModel.stepForward))
                    case 6: DisclaimerStep { viewModel.nextStep() }
                                .transition(slideTransition(forward: viewModel.stepForward))
                    default: ProviderStep(onComplete: { viewModel.completeOnboarding() })
                                .transition(slideTransition(forward: viewModel.stepForward))
                    }
                }
                .animation(DesignTokens.Animation.standard, value: viewModel.currentStep)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                navButtons
                    .padding(.horizontal, DesignTokens.Spacing.xl)
                    .padding(.bottom, DesignTokens.Spacing.xl)
            }
        }
        .onChange(of: viewModel.isComplete) { _, complete in
            if complete { onComplete() }
        }
    }

    private func slideTransition(forward: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading),
            removal:   .move(edge: forward ? .leading  : .trailing)
        )
    }

    // MARK: Background
    @ViewBuilder private var backgroundGradient: some View {
        let colors: [Color] = {
            switch viewModel.currentStep {
            case 0: return [.teal.opacity(0.28), .blue.opacity(0.10), Color("PrimaryBackground")]
            case 1: return [.purple.opacity(0.28), .indigo.opacity(0.10), Color("PrimaryBackground")]
            case 2: return [.orange.opacity(0.22), .pink.opacity(0.10), Color("PrimaryBackground")]
            case 3: return [.indigo.opacity(0.28), .purple.opacity(0.12), Color("PrimaryBackground")]
            case 4: return [.pink.opacity(0.22), .red.opacity(0.06), Color("PrimaryBackground")]
            case 5: return [.green.opacity(0.22), .teal.opacity(0.06), Color("PrimaryBackground")]
            default: return [.blue.opacity(0.20), .purple.opacity(0.06), Color("PrimaryBackground")]
            }
        }()
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }

    // MARK: Step dots
    private var stepDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<viewModel.totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i <= viewModel.currentStep ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: i == viewModel.currentStep ? 22 : 7, height: 7)
                    .animation(DesignTokens.Animation.standard, value: viewModel.currentStep)
            }
        }
    }

    // MARK: Nav buttons (feature slides 0-3 + Siri slide)
    @ViewBuilder private var navButtons: some View {
        if viewModel.currentStep < 4 {
            HStack {
                Button("Skip intro") {
                    triggerHaptic(.light)
                    viewModel.jumpTo(4)
                }
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    triggerHaptic(.medium)
                    viewModel.nextStep()
                } label: {
                    HStack(spacing: 6) {
                        Text("Next")
                        Image(systemName: "arrow.right")
                    }
                    .font(DesignTokens.Typography.headline)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 8, y: 4)
                }
            }
        }
    }
}

// MARK: - Feature Slide Data

private enum FeatureSlideData {
    case dashboard, askAI, insights

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .askAI:     return "brain.head.profile"
        case .insights:  return "chart.xyaxis.line"
        }
    }

    var iconColors: [Color] {
        switch self {
        case .dashboard: return [.teal, .blue]
        case .askAI:     return [.purple, .indigo]
        case .insights:  return [.orange, .pink]
        }
    }

    var headline: String {
        switch self {
        case .dashboard: return "Everything in one place"
        case .askAI:     return "Ask your AI health analyst"
        case .insights:  return "Beautiful, actionable insights"
        }
    }

    var tagline: String {
        switch self {
        case .dashboard:
            return "Your most important health metrics — steps, heart rate, sleep, weight, and more — live on one gorgeous home screen."
        case .askAI:
            return "Ask anything. Get expert analysis tailored to your level — from beginner-friendly explanations to clinical detail."
        case .insights:
            return "Explore trends across 20+ metrics: sleep quality, nutrition, activity, vitals, and how they all connect."
        }
    }
}

// MARK: - Feature Slide View

private struct FeatureSlide: View {
    let slide: FeatureSlideData
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            // Icon hero
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: slide.iconColors.map { $0.opacity(0.18) },
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 110, height: 110)
                Circle()
                    .fill(LinearGradient(colors: slide.iconColors,
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 78, height: 78)
                    .shadow(color: slide.iconColors[0].opacity(0.45), radius: 16, y: 6)
                Image(systemName: slide.icon)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white)
            }
            .scaleEffect(appeared ? 1 : 0.55)
            .opacity(appeared ? 1 : 0)
            .padding(.bottom, 28)

            // Text
            VStack(spacing: 12) {
                Text(slide.headline)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)

                Text(slide.tagline)
                    .font(DesignTokens.Typography.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 28)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 18)

            Spacer(minLength: 20)

            // Mock UI preview
            mockPreview
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 28)
                .scaleEffect(appeared ? 1 : 0.92)

            Spacer(minLength: 12)
        }
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.72)) { appeared = true }
        }
    }

    @ViewBuilder private var mockPreview: some View {
        switch slide {
        case .dashboard: MockDashboardPreview()
        case .askAI:     MockAskAIPreview()
        case .insights:  MockInsightsPreview()
        }
    }
}

// MARK: - Mock Dashboard Preview

private struct MockDashboardPreview: View {
    private let cards: [(icon: String, color: Color, label: String, value: String)] = [
        ("figure.walk",         .teal,   "Steps",    "8,342"),
        ("heart.fill",          .pink,   "Heart",    "62 bpm"),
        ("bed.double.fill",     .indigo, "Sleep",    "7.2 hrs"),
        ("drop.fill",           .blue,   "Water",    "1.4 L"),
    ]

    var body: some View {
        VStack(spacing: 1) {
            // Fake nav bar
            HStack {
                Text("Good morning 👋")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "bell.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            // 2×2 metric cards
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(cards, id: \.label) { card in
                    HStack(spacing: 8) {
                        Image(systemName: card.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(card.color)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(card.value)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.primary)
                            Text(card.label)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(10)
            .background(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

// MARK: - Mock Ask AI Preview

private struct MockAskAIPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Fake header
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 13))
                    .foregroundStyle(.purple)
                Text("Ask AI")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Gemini 2.0")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            VStack(alignment: .leading, spacing: 10) {
                // User bubble
                HStack {
                    Spacer()
                    Text("How was my sleep this week?")
                        .font(.system(size: 12))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.purple)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                // AI response bubble
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(LinearGradient(colors: [.purple, .indigo],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Image(systemName: "brain")
                                .font(.system(size: 10))
                                .foregroundStyle(.white)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your average sleep was **7.2 hrs** — close to the 7.5 hr goal. You hit deep sleep on 3 nights. 🎯")
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                        HStack(spacing: 4) {
                            ForEach(["Mon","Tue","Wed","Thu","Fri","Sat","Sun"], id: \.self) { day in
                                VStack(spacing: 2) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill([0,1,5,6].contains(["Mon","Tue","Wed","Thu","Fri","Sat","Sun"].firstIndex(of: day)!) ? Color.purple.opacity(0.3) : Color.purple)
                                        .frame(width: 8, height: CGFloat([6,7,5,8,7,8,7].randomElement()!) * 2.5)
                                    Text(String(day.prefix(1)))
                                        .font(.system(size: 7))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(10)
            .background(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

// MARK: - Mock Insights Preview

private struct MockInsightsPreview: View {
    private let bars: [(CGFloat, Color)] = [
        (0.45, .orange), (0.55, .orange), (0.30, .orange), (0.80, .green),
        (0.75, .green), (0.50, .orange), (0.90, .green),
    ]
    private let days = ["M","T","W","T","F","S","S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sleep Quality")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Avg 7.4 hrs · Goal met 4/7 nights")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            // Bar chart
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(bars.enumerated()), id: \.offset) { i, bar in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(LinearGradient(colors: [bar.1.opacity(0.5), bar.1],
                                                startPoint: .bottom, endPoint: .top))
                            .frame(height: bar.0 * 60)
                        Text(days[i])
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 80)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

// MARK: - Step: Disclaimer

private struct DisclaimerStep: View {
    let onContinue: () -> Void

    var body: some View {
        TermsView(onAcknowledge: onContinue)
            .padding(.horizontal, 4)
    }
}

// MARK: - Step: Health Permission

private struct HealthPermissionStep: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.pink.opacity(0.2), .red.opacity(0.1)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 110, height: 110)
                Circle()
                    .fill(LinearGradient(colors: [.pink, .red],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 78, height: 78)
                    .shadow(color: .pink.opacity(0.4), radius: 16, y: 6)
                Image(systemName: "heart.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 10) {
                Text("Connect your Health data")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text("HealthLens reads your Apple Health data to provide personalized AI insights.\n\nYour data **never leaves your device** unless you choose a cloud AI provider.")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 28)

            // Permission categories
            VStack(spacing: 8) {
                ForEach(permissionCategories, id: \.label) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.icon)
                            .font(.system(size: 15))
                            .foregroundStyle(item.color)
                            .frame(width: 26)
                        Text(item.label)
                            .font(DesignTokens.Typography.callout)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.horizontal, 24)

            if let error = viewModel.permissionError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(DesignTokens.Typography.footnote).foregroundStyle(.secondary)
                }
                .padding(DesignTokens.Spacing.sm)
                .background(Color.healthWarning.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
                .padding(.horizontal, 24)
            }

            VStack(spacing: 12) {
                Button {
                    triggerHaptic(.medium)
                    Task { await viewModel.requestHealthPermissions() }
                } label: {
                    HStack {
                        if viewModel.isRequestingPermissions {
                            ProgressView().tint(.white).scaleEffect(0.85)
                        }
                        Text(viewModel.isRequestingPermissions ? "Requesting…" : "Grant Health Access")
                            .font(DesignTokens.Typography.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(Color.pink)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous))
                    .shadow(color: .pink.opacity(0.35), radius: 8, y: 4)
                }
                .disabled(viewModel.isRequestingPermissions)
                .padding(.horizontal, 24)

                Button("Skip for now") { viewModel.nextStep() }
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
        }
    }

    private let permissionCategories: [(icon: String, color: Color, label: String)] = [
        ("figure.walk",        .teal,    "Activity & Steps"),
        ("heart.fill",         .pink,    "Heart Rate & HRV"),
        ("bed.double.fill",    .indigo,  "Sleep Analysis"),
        ("fork.knife",         .orange,  "Nutrition"),
        ("waveform.path.ecg",  .blue,    "Vitals & Blood Oxygen"),
        ("scalemass.fill",     .purple,  "Body Measurements"),
    ]
}

// MARK: - Step: Location Permission

private struct LocationPermissionStep: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.green.opacity(0.2), .teal.opacity(0.1)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 110, height: 110)
                Circle()
                    .fill(LinearGradient(colors: [.green, .teal],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 78, height: 78)
                    .shadow(color: .green.opacity(0.4), radius: 16, y: 6)
                Image(systemName: "location.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 10) {
                Text("Enhance your insights")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text("Optional: Location helps correlate your health trends with environment — air quality, weather, and activity context.\n\nLocation is **never shared** with AI providers.")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 28)

            // Use cases
            VStack(spacing: 8) {
                ForEach(locationUseCases, id: \.label) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.icon)
                            .font(.system(size: 15))
                            .foregroundStyle(.green)
                            .frame(width: 26)
                        Text(item.label)
                            .font(DesignTokens.Typography.callout)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.horizontal, 24)

            VStack(spacing: 12) {
                Button {
                    triggerHaptic(.medium)
                    Task { await viewModel.requestLocationPermission() }
                } label: {
                    HStack {
                        if viewModel.isRequestingLocation {
                            ProgressView().tint(.white).scaleEffect(0.85)
                        }
                        Text(viewModel.isRequestingLocation ? "Requesting…" : "Allow Location Access")
                            .font(DesignTokens.Typography.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous))
                    .shadow(color: .green.opacity(0.35), radius: 8, y: 4)
                }
                .disabled(viewModel.isRequestingLocation)
                .padding(.horizontal, 24)

                Button("Skip, don't use location") { viewModel.nextStep() }
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
        }
    }

    private let locationUseCases: [(icon: String, label: String)] = [
        ("wind",             "Correlate symptoms with air quality"),
        ("cloud.sun.fill",   "Weather & activity context"),
        ("map.fill",         "Region-specific health benchmarks"),
    ]
}

// MARK: - Step: Provider Setup

private struct ProviderStep: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue.opacity(0.2), .purple.opacity(0.1)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 110, height: 110)
                Circle()
                    .fill(LinearGradient(colors: [.blue, .purple],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 78, height: 78)
                    .shadow(color: .blue.opacity(0.4), radius: 16, y: 6)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 10) {
                Text("Choose your AI analyst")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text("Use Apple on-device AI for full privacy, or connect Claude, Gemini, or AWS Bedrock for deeper analysis.")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 28)

            VStack(spacing: 8) {
                ForEach(AIProviderType.allCases, id: \.self) { provider in
                    HStack(spacing: 12) {
                        Image(systemName: provider.systemImage)
                            .font(.system(size: 15))
                            .foregroundStyle(providerColor(provider))
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.displayName)
                                .font(DesignTokens.Typography.callout)
                                .fontWeight(.medium)
                            Text(providerDesc(provider))
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.horizontal, 24)

            Button {
                triggerHaptic(.success)
                onComplete()
            } label: {
                Text("Let's go!")
                    .font(DesignTokens.Typography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(LinearGradient(colors: [.blue, .purple],
                                              startPoint: .leading, endPoint: .trailing))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous))
                    .shadow(color: .blue.opacity(0.4), radius: 8, y: 4)
            }
            .padding(.horizontal, 24)

            Text("Configure API keys in Settings → AI Providers")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.tertiary)

            // Prominent medical disclaimer
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 16))
                Text("**Not medical advice.** HealthLens is an informational tool only and does **not** replace a doctor, physician, or licensed medical professional. Always consult a healthcare provider for medical decisions.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(Color.orange.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.orange.opacity(0.35), lineWidth: 1)
            )
            .padding(.horizontal, 24)

            Spacer(minLength: 8)
        }
    }

    private func providerColor(_ p: AIProviderType) -> Color {
        switch p {
        case .claude:   return .orange
        case .gemini:   return .blue
        case .bedrock:  return .teal
        case .onDevice: return .green
        }
    }

    private func providerDesc(_ p: AIProviderType) -> String {
        switch p {
        case .claude:   return "Best for nuanced health analysis"
        case .gemini:   return "Great for large data volumes"
        case .bedrock:  return "AWS cloud, enterprise-grade"
        case .onDevice: return "Full privacy — no API key needed"
        }
    }
}

// MARK: - Step: Siri Shortcuts

private struct SiriShortcutsSlide: View {
    @State private var appeared = false

    private let commands: [(icon: String, colors: [Color], title: String, example: String)] = [
        ("drop.fill",         [.blue, .cyan],           "Log Water",       "\"Add 250ml of water to HealthLens\""),
        ("text.bubble.fill",  [.green, .teal],           "Describe a Meal", "\"Describe a meal in HealthLens\""),
        ("camera.viewfinder", [.orange, .yellow],        "Scan a Meal",     "\"Scan a meal in HealthLens\""),
        ("scalemass.fill",    [.purple, .indigo],        "Log Weight",      "\"Log my weight in HealthLens\""),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            // Hero icon
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.indigo.opacity(0.2), .purple.opacity(0.1)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 110, height: 110)
                Circle()
                    .fill(LinearGradient(colors: [.indigo, .purple],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 78, height: 78)
                    .shadow(color: .indigo.opacity(0.45), radius: 16, y: 6)
                Image(systemName: "mic.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white)
            }
            .scaleEffect(appeared ? 1 : 0.55)
            .opacity(appeared ? 1 : 0)
            .padding(.bottom, 24)

            // Headline
            VStack(spacing: 10) {
                Text("Log with just your voice")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                Text("Use Siri to log water, describe meals, and scan food — without even opening the app.")
                    .font(DesignTokens.Typography.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 28)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)

            Spacer(minLength: 20)

            // Command cards
            VStack(spacing: 8) {
                ForEach(commands, id: \.title) { cmd in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: cmd.colors,
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing))
                                .frame(width: 34, height: 34)
                            Image(systemName: cmd.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cmd.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(cmd.example)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                        Spacer()
                        Image(systemName: "mic")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.horizontal, 20)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 24)
            .scaleEffect(appeared ? 1 : 0.94)

            Spacer(minLength: 12)

            Text("You can customise phrases in Settings → Siri & Shortcuts after setup.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .opacity(appeared ? 1 : 0)

            Spacer(minLength: 8)
        }
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.72)) { appeared = true }
        }
    }
}
