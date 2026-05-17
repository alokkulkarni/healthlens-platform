import SwiftUI

struct CardModifier: ViewModifier {
    var padding: CGFloat
    var cornerRadius: CGFloat
    var shadowConfig: DesignTokens.ShadowConfig

    init(
        padding: CGFloat = DesignTokens.Spacing.md,
        cornerRadius: CGFloat = DesignTokens.Radius.lg,
        shadow: DesignTokens.ShadowConfig = DesignTokens.Shadow.sm
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadowConfig = shadow
    }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: shadowConfig.color,
                radius: shadowConfig.radius,
                x: shadowConfig.x,
                y: shadowConfig.y
            )
    }
}

extension View {
    func card(
        padding: CGFloat = DesignTokens.Spacing.md,
        cornerRadius: CGFloat = DesignTokens.Radius.lg,
        shadow: DesignTokens.ShadowConfig = DesignTokens.Shadow.sm
    ) -> some View {
        modifier(CardModifier(padding: padding, cornerRadius: cornerRadius, shadow: shadow))
    }
}
