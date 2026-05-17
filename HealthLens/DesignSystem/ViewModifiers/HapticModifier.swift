import SwiftUI

enum HapticStyle {
    case light, medium, heavy
    case success, warning, error
    case selection
}

struct HapticModifier: ViewModifier {
    let style: HapticStyle

    func body(content: Content) -> some View {
        content.onTapGesture {
            triggerHaptic(style)
        }
    }

    private func triggerHaptic(_ style: HapticStyle) {
        switch style {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}

extension View {
    func hapticOnTap(_ style: HapticStyle = .light) -> some View {
        modifier(HapticModifier(style: style))
    }
}

// Standalone haptic trigger (for use in button actions)
func triggerHaptic(_ style: HapticStyle) {
    switch style {
    case .light:    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    case .medium:   UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    case .heavy:    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    case .success:  UINotificationFeedbackGenerator().notificationOccurred(.success)
    case .warning:  UINotificationFeedbackGenerator().notificationOccurred(.warning)
    case .error:    UINotificationFeedbackGenerator().notificationOccurred(.error)
    case .selection: UISelectionFeedbackGenerator().selectionChanged()
    }
}
