import SwiftUI

/// Semantic design tokens. Colors are resolved from the asset catalog so
/// light/dark (U2) and system color scheme are respected. Views never use
/// raw `Color(...)` literals or magic numbers — only `Theme.*`.
enum Theme {
    // MARK: - Colors

    static let backgroundPrimary = Color("BackgroundPrimary", bundle: .main)
    static let backgroundSecondary = Color("BackgroundSecondary", bundle: .main)
    static let textPrimary = Color("TextPrimary", bundle: .main)
    static let textSecondary = Color("TextSecondary", bundle: .main)
    static let accentPrimary = Color("AccentPrimary", bundle: .main)
    static let danger = Color("Danger", bundle: .main)
    static let success = Color("Success", bundle: .main)
    static let hairline = Color("Hairline", bundle: .main)

    // MARK: - Spacing

    static let spacingExtraSmall: CGFloat = 4
    static let spacingSmall: CGFloat = 8
    static let spacingMedium: CGFloat = 16
    static let spacingLarge: CGFloat = 24
    static let spacingExtraLarge: CGFloat = 32

    // MARK: - Layout

    static let cornerRadius: CGFloat = 10
    static let cornerRadiusLarge: CGFloat = 16
    static let minTapArea: CGFloat = 44
    static let screenHorizontalPadding: CGFloat = 24
    static let maxContentWidth: CGFloat = 420

    // MARK: - Shadows

    static let shadowSmall = ShadowStyle(radius: 4, y: 2, opacity: 0.08)
    static let shadowMedium = ShadowStyle(radius: 8, y: 4, opacity: 0.12)

    // MARK: - Helpers

    /// Returns a font suitable for the large timer display.
    static func timerFont() -> Font {
        .system(size: 64, weight: .semibold, design: .rounded)
    }

    /// Returns a copy of the color with the given alpha component.
    /// `Color.opacity(_:)` is iOS 16+; this helper keeps iOS 15 support.
    static func color(_ color: Color, alpha: Double) -> Color {
        Color(uiColor: UIColor(color).withAlphaComponent(alpha))
    }
}

/// Lightweight shadow description used by view modifiers.
struct ShadowStyle {
    let radius: CGFloat
    let y: CGFloat
    let opacity: Double
}

/// Manages the active color scheme. For the MVP it follows the system;
/// `ThemeManager` is the seam where a future setting could override it.
@MainActor
final class ThemeManager: ObservableObject {
    @Published var colorScheme: ColorScheme? // nil = follow system

    init() {}
}
