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
    static let cornerRadiusSmall: CGFloat = 8
    static let cornerRadiusLarge: CGFloat = 16
    static let minTapArea: CGFloat = 44
    static let screenHorizontalPadding: CGFloat = 24
    static let maxContentWidth: CGFloat = 420

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

    // swiftlint:disable cyclomatic_complexity
    /// Resolves an `ActivityColor` palette key to its light/dark asset (D15).
    /// Switches on the enum cases so each asset name is a compile-time
    /// PascalCase literal matching the colorset names in `Assets.xcassets`
    /// (`Gray`, `Red`, … `Mint`) — not the lowercase backend raw value. The
    /// exhaustive switch is required by `DECISIONS.md#D15` (closed 12-key
    /// palette); its complexity exceeds the default threshold only because the
    /// palette has 12 keys, hence the scoped disable.
    static func activityColor(_ color: ActivityColor) -> Color {
        switch color {
        case .gray: return Color("Gray", bundle: .main)
        case .red: return Color("Red", bundle: .main)
        case .orange: return Color("Orange", bundle: .main)
        case .yellow: return Color("Yellow", bundle: .main)
        case .green: return Color("Green", bundle: .main)
        case .teal: return Color("Teal", bundle: .main)
        case .blue: return Color("Blue", bundle: .main)
        case .indigo: return Color("Indigo", bundle: .main)
        case .purple: return Color("Purple", bundle: .main)
        case .pink: return Color("Pink", bundle: .main)
        case .brown: return Color("Brown", bundle: .main)
        case .mint: return Color("Mint", bundle: .main)
        }
    }
    // swiftlint:enable cyclomatic_complexity
}

/// Lightweight shadow description used by view modifiers.
struct ShadowStyle {
    let radius: CGFloat
    let y: CGFloat
    let opacity: Double
}

extension Theme {
    /// Small card shadow: radius 4, y 2, opacity 0.08 (TOKENS.md → Shadows).
    static let shadowSmall = ShadowStyle(radius: 4, y: 2, opacity: 0.08)
}
