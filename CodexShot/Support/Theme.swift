import SwiftUI

/// Central design tokens for CodexShot. Keeps the brand palette, gradients and
/// spacing consistent across every screen so the app reads as a single, polished surface.
enum Theme {
    // MARK: Brand palette

    static let brand = Color(red: 0.12, green: 0.74, blue: 0.74)        // primary teal
    static let brandDeep = Color(red: 0.05, green: 0.52, blue: 0.62)    // deep teal/blue
    static let brandBright = Color(red: 0.36, green: 0.86, blue: 0.86)  // bright aqua
    static let accentBlue = Color(red: 0.20, green: 0.55, blue: 0.95)
    static let warning = Color(red: 0.98, green: 0.62, blue: 0.20)

    // MARK: Hero send-button gradient (glossy aqua)

    static let sendGradient = LinearGradient(
        colors: [
            Color(red: 0.42, green: 0.88, blue: 0.89),
            Color(red: 0.16, green: 0.76, blue: 0.80),
            Color(red: 0.07, green: 0.60, blue: 0.70)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Soft inner gloss laid over a filled control to fake a light source.
    static let glossOverlay = LinearGradient(
        colors: [
            Color.white.opacity(0.55),
            Color.white.opacity(0.10),
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
