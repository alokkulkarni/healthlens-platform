import SwiftUI

enum DesignTokens {
    // MARK: - Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Corner Radius
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let pill: CGFloat = 100
    }

    // MARK: - Typography
    enum Typography {
        static let largeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
        static let title = Font.system(size: 28, weight: .bold, design: .rounded)
        static let title2 = Font.system(size: 22, weight: .semibold, design: .rounded)
        static let title3 = Font.system(size: 20, weight: .semibold, design: .rounded)
        static let headline = Font.system(size: 17, weight: .semibold, design: .default)
        static let body = Font.system(size: 17, weight: .regular, design: .default)
        static let callout = Font.system(size: 16, weight: .regular, design: .default)
        static let subheadline = Font.system(size: 15, weight: .regular, design: .default)
        static let footnote = Font.system(size: 13, weight: .regular, design: .default)
        static let caption = Font.system(size: 12, weight: .regular, design: .default)
        static let caption2 = Font.system(size: 11, weight: .regular, design: .default)
        static let monoCaption = Font.system(size: 12, weight: .medium, design: .monospaced)
    }

    // MARK: - Shadow
    enum Shadow {
        static let sm = ShadowConfig(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        static let md = ShadowConfig(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        static let lg = ShadowConfig(color: .black.opacity(0.14), radius: 20, x: 0, y: 8)
    }

    struct ShadowConfig {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    // MARK: - Animation
    enum Animation {
        static let fast = SwiftUI.Animation.spring(response: 0.25, dampingFraction: 0.8)
        static let standard = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.75)
        static let slow = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.7)
        static let easeOut = SwiftUI.Animation.easeOut(duration: 0.25)
    }
}

// MARK: - Semantic colors per HealthCategory
extension HealthCategory {
    var color: Color {
        switch self {
        case .activity:     return .green
        case .body:         return Color(red: 0.6, green: 0.4, blue: 1.0)
        case .heart:        return .pink
        case .sleep:        return .indigo
        case .nutrition:    return .orange
        case .vitals:       return .teal
        case .mindfulness:  return Color(red: 0.4, green: 0.8, blue: 0.6)
        case .reproductive: return Color(red: 1.0, green: 0.4, blue: 0.6)
        case .labs:         return Color(red: 0.2, green: 0.6, blue: 0.9)
        case .environment:  return Color(red: 0.3, green: 0.7, blue: 0.5)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [color, color.opacity(0.6)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
