# HealthLens — Xcode Project Setup

All Swift source files are complete. Follow these steps to create the Xcode project and run the app.

---

## Prerequisites

- **Xcode 15.4+** (Xcode 16 recommended for iOS 18 features)
- **iOS 17.0+ deployment target**
- A physical iPhone for HealthKit testing (HealthKit is unavailable on simulators)
- Optional: [XcodeGen](https://github.com/yonaskolb/XcodeGen) for auto-generating the `.xcodeproj`

---

## Option A: XcodeGen (Recommended — 1 command)

```bash
# Install XcodeGen if not already installed
brew install xcodegen

# From the analyze/ directory
cd /Users/alokkulkarni/Documents/Development/analyze
xcodegen generate
open HealthLens.xcodeproj
```

This reads `project.yml` and creates a fully configured Xcode project.

---

## Option B: Manual Xcode Setup

1. **Open Xcode** → File → New → Project → iOS App
2. Set:
   - Product Name: `HealthLens`
   - Bundle ID: `com.healthlens.app`
   - Interface: `SwiftUI`
   - Language: `Swift`
   - Storage: `SwiftData`
   - Minimum Deployment: `iOS 17.0`
3. **Delete the generated files** (`ContentView.swift`, `Item.swift`)
4. **Add all files** from `HealthLens/` folder: File → Add Files to "HealthLens"
   - Make sure "Copy items if needed" is **unchecked** (files are already in place)
   - Add Groups (not folder references)
5. **Add HealthKit framework**: Target → General → Frameworks → `+` → `HealthKit.framework`
6. **Set Info.plist entries**: Copy from `HealthLens/Resources/Info.plist`:
   - `NSHealthShareUsageDescription`
   - `NSHealthUpdateUsageDescription`
   - `BGTaskSchedulerPermittedIdentifiers`
7. **Replace entitlements**: Set target entitlements file to `HealthLens/Resources/HealthLens.entitlements`
8. **Add `MockHealthData.json`** to the target's Copy Bundle Resources build phase

---

## Setting Up API Keys (at Runtime)

Keys are stored in Keychain — **never in code or config files**.

1. Launch the app → Settings tab → AI Providers
2. Tap **Configure** next to each provider:
   - **Claude**: Get key from [console.anthropic.com](https://console.anthropic.com)
   - **Gemini**: Get key from [aistudio.google.com](https://aistudio.google.com)
   - **Bedrock**: IAM user credentials with `AmazonBedrockFullAccess` policy
   - **On-Device**: No key needed (requires iPhone 16+ with iOS 18.1+)

---

## File Structure Overview

```
analyze/
├── project.yml                 ← XcodeGen config
├── SETUP.md                    ← This file
└── HealthLens/
    ├── HealthLensApp.swift     ← @main entry point
    ├── AppDelegate.swift       ← Background task registration
    ├── Core/                   ← Constants, environment, logging
    ├── DesignSystem/           ← Tokens, colors, view modifiers
    ├── Models/                 ← SwiftData @Model classes
    ├── Keychain/               ← Secure API key storage
    ├── HealthKit/              ← HealthKit service actor + data fetcher
    ├── AI/                     ← Protocol + Claude/Gemini/Bedrock/OnDevice providers
    ├── Charts/                 ← SwiftUI Charts wrappers
    ├── Features/               ← All feature screens (MVVM)
    │   ├── Onboarding/
    │   ├── Home/
    │   ├── Insights/
    │   ├── Query/              ← Core AI query interface
    │   ├── History/            ← Session replay timeline
    │   └── Settings/
    ├── Navigation/             ← Tab view + routing
    └── Resources/              ← Assets, Info.plist, MockHealthData.json
```

---

## Key Architecture Decisions

| Area | Approach |
|---|---|
| Persistence | SwiftData with `@Model` classes |
| AI abstraction | `AIProvider` protocol — swap providers at runtime |
| HealthKit | `actor HealthKitService` — all HK calls serialized |
| Concurrency | `TaskGroup` for parallel category fetches; `AsyncThrowingStream` for streaming AI |
| Security | All API keys in Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) |
| Navigation | `@Observable NavigationRouter` + `NavigationPath` per tab |
| Simulator | `MockHealthDataProvider` reads `MockHealthData.json` when HealthKit unavailable |

---

## Testing the App

### On Simulator
- MockHealthData.json is loaded automatically
- All AI providers work (configure real API keys)
- HealthKit permission screens appear but do nothing (HealthKit not available)

### On Physical Device
- Full HealthKit access (grant permissions in Onboarding or Settings)
- Background refresh works with real Apple Watch / Health app data
- On-device AI requires iPhone 16 or later with iOS 18.1+

---

## Extending the App

- **Add a new AI provider**: Implement `AIProvider` protocol → add case to `AIProviderType` → register in `AIServiceRouter.buildProvider`
- **Add a new health category**: Add case to `HealthCategory` enum in `HealthKitTypes.swift` → define `quantityTypes`/`categoryTypes` → add color/icon in `DesignTokens.swift`
- **Add a new chart type**: Implement a `View` in `Charts/` → add case to `HealthChartFactory`
