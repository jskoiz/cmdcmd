import SwiftUI
import UIKit

/// Central design tokens for a restrained, professional interface.
enum Theme {
    // MARK: Neutral palette

    static let brand = adaptiveColor(
        light: UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1),
        dark: UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
    )
    static let brandDeep = adaptiveColor(
        light: UIColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1),
        dark: UIColor.white
    )
    static let brandBright = adaptiveColor(
        light: UIColor(red: 0.88, green: 0.89, blue: 0.91, alpha: 1),
        dark: UIColor(red: 0.26, green: 0.26, blue: 0.28, alpha: 1)
    )
    static let accentBlue = adaptiveColor(
        light: UIColor(red: 0.36, green: 0.36, blue: 0.38, alpha: 1),
        dark: UIColor(red: 0.82, green: 0.82, blue: 0.86, alpha: 1)
    )
    static let secondaryText = adaptiveColor(
        light: UIColor.secondaryLabel,
        dark: UIColor(red: 0.76, green: 0.76, blue: 0.80, alpha: 1)
    )
    static let tertiaryText = adaptiveColor(
        light: UIColor.tertiaryLabel,
        dark: UIColor(red: 0.62, green: 0.62, blue: 0.67, alpha: 1)
    )
    static let previewWellTop = adaptiveColor(
        light: UIColor.secondarySystemBackground.withAlphaComponent(0.82),
        dark: UIColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1)
    )
    static let previewWellMiddle = adaptiveColor(
        light: UIColor.systemBackground.withAlphaComponent(0.72),
        dark: UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)
    )
    static let previewWellBottom = adaptiveColor(
        light: UIColor.systemGray5.withAlphaComponent(0.62),
        dark: UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1)
    )

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
        static let md: CGFloat = 16
    }

    // MARK: Corner radii

    enum Radius {
        static let card: CGFloat = 32
        static let panel: CGFloat = 26
    }

    private static func adaptiveColor(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}
