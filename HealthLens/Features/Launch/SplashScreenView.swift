import SwiftUI

// MARK: - Splash Screen

/// Full-screen animated splash shown every time the app launches.
/// Fades in the logo + title, pulses once, then fades out to reveal the app.
struct SplashScreenView: View {
    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var taglineOpacity: Double = 0
    @State private var ringScale: CGFloat = 0.8
    @State private var ringOpacity: Double = 0.6

    var body: some View {
        ZStack {
            // Background — matches system launch screen color
            Color("LaunchScreenBackground")
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Logo + animated ring
                ZStack {
                    // Outer glow ring — expands and fades on appear
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.teal.opacity(0.5), Color.teal.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 140, height: 140)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)

                    // Subtle inner ring
                    Circle()
                        .stroke(Color.teal.opacity(0.15), lineWidth: 1)
                        .frame(width: 118, height: 118)
                        .opacity(logoOpacity)

                    // App logo from asset catalog
                    Image("LaunchLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 90, height: 90)
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

                // App title and tagline
                VStack(spacing: 8) {
                    Text("HealthLens")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .opacity(titleOpacity)

                    Text("Your personal health intelligence")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .opacity(taglineOpacity)
                }

                Spacer()

                // Powered-by footer
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 11))
                    Text("Powered by Apple Intelligence & Cloud AI")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Color.white.opacity(0.3))
                .opacity(taglineOpacity)
                .padding(.bottom, 36)
            }
        }
        .onAppear { startAnimations() }
    }

    private func startAnimations() {
        // Logo springs in from slightly below scale
        withAnimation(.spring(response: 0.7, dampingFraction: 0.65)) {
            logoScale = 1.0
            logoOpacity = 1.0
        }

        // Title fades in just after logo settles
        withAnimation(.easeOut(duration: 0.5).delay(0.45)) {
            titleOpacity = 1.0
        }

        // Tagline + footer
        withAnimation(.easeOut(duration: 0.5).delay(0.75)) {
            taglineOpacity = 1.0
        }

        // Glow ring radiates outward and fades
        withAnimation(.easeOut(duration: 1.2).delay(0.2)) {
            ringScale = 1.6
            ringOpacity = 0
        }
    }
}

// MARK: - App Content Wrapper

/// Wraps RootTabView with the splash overlay. @State lives here (not in App)
/// so SwiftUI animations work correctly on every launch.
struct AppContentView: View {
    @State private var showSplash = true
    @State private var splashFading = false

    var body: some View {
        ZStack {
            RootTabView()
                .opacity(showSplash ? 0 : 1)

            if showSplash {
                SplashScreenView()
                    .opacity(splashFading ? 0 : 1)
                    .animation(.easeOut(duration: 0.45), value: splashFading)
                    .zIndex(10)
            }
        }
        .task {
            // Show splash for 2.2 s total: 2.0 s hold + 0.45 s fade-out
            try? await Task.sleep(for: .seconds(2.0))
            splashFading = true
            try? await Task.sleep(for: .seconds(0.45))
            showSplash = false
        }
    }
}

// MARK: - Preview

#Preview("Splash") {
    SplashScreenView()
}
