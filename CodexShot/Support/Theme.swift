import SwiftUI

/// Central design tokens for a restrained, professional interface.
enum Theme {
    // MARK: Neutral palette

    static let brand = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let brandDeep = Color(red: 0.02, green: 0.02, blue: 0.02)
    static let brandBright = Color(red: 0.88, green: 0.89, blue: 0.91)
    static let accentBlue = Color(red: 0.36, green: 0.36, blue: 0.38)
    static let warning = Color(red: 0.42, green: 0.42, blue: 0.44)

    // MARK: Primary action gradient

    static let sendGradient = LinearGradient(
        colors: [
            Color(red: 0.24, green: 0.24, blue: 0.25),
            Color(red: 0.08, green: 0.08, blue: 0.09),
            Color.black
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Soft inner gloss laid over a filled control to fake a light source.
    static let glossOverlay = LinearGradient(
        colors: [
            Color.white.opacity(0.22),
            Color.white.opacity(0.06),
            Color.clear
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: Spacing scale

    enum Space {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 22
        static let xl: CGFloat = 30
    }

    // MARK: Corner radii

    enum Radius {
        static let card: CGFloat = 32
        static let panel: CGFloat = 26
        static let pill: CGFloat = 22
    }
}

extension ShapeStyle where Self == Color {
    static var brand: Color { Theme.brand }
}
