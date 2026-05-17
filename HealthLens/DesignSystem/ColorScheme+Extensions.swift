import SwiftUI

extension Color {
    // MARK: - Semantic Surface Colors
    static let cardBackground = Color(UIColor.secondarySystemBackground)
    static let primaryBackground = Color(UIColor.systemBackground)
    static let tertiaryBackground = Color(UIColor.tertiarySystemBackground)

    // MARK: - Text Colors
    static let primaryText = Color(UIColor.label)
    static let secondaryText = Color(UIColor.secondaryLabel)
    static let tertiaryText = Color(UIColor.tertiaryLabel)

    // MARK: - Semantic Status Colors
    static let healthGood = Color.green
    static let healthWarning = Color.orange
    static let healthCritical = Color.red
    static let healthNeutral = Color.secondary

    // MARK: - Chart Palette
    static let chartPrimary = Color.blue
    static let chartSecondary = Color.green
    static let chartTertiary = Color.orange
    static let chartQuaternary = Color.purple

    // MARK: - Separator
    static let divider = Color(UIColor.separator)

    // MARK: - Fill Colors
    static let fillQuaternary = Color(UIColor.quaternarySystemFill)
    static let fillTertiary = Color(UIColor.tertiarySystemFill)
    static let fillSecondary = Color(UIColor.secondarySystemFill)

    // MARK: - Gradient helpers
    func cardGradient() -> LinearGradient {
        LinearGradient(
            colors: [self, self.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension ShapeStyle where Self == Color {
    static var cardBackground: Color { .cardBackground }
    static var primaryText:    Color { .primaryText    }
    static var secondaryText:  Color { .secondaryText  }
    static var tertiaryText:   Color { .tertiaryText   }
    static var fillTertiary:   Color { .fillTertiary   }
    static var fillQuaternary: Color { .fillQuaternary }
    static var divider:        Color { .divider        }
    static var healthGood:     Color { .healthGood     }
    static var healthWarning:  Color { .healthWarning  }
    static var healthCritical: Color { .healthCritical }
    static var healthNeutral:  Color { .healthNeutral  }
}
