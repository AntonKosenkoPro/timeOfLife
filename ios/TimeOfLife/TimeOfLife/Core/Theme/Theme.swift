import SwiftUI

/// Semantic color tokens. Resolved from the asset catalog so light/dark
/// (U2) and system color scheme are respected. Views never use raw
/// `Color(...)` literals — only `Theme.*`.
enum Theme {
    static let backgroundPrimary = Color("BackgroundPrimary", bundle: .main)
    static let backgroundSecondary = Color("BackgroundSecondary", bundle: .main)
    static let textPrimary = Color("TextPrimary", bundle: .main)
    static let textSecondary = Color("TextSecondary", bundle: .main)
    static let accentPrimary = Color("AccentPrimary", bundle: .main)
    static let danger = Color("Danger", bundle: .main)
    static let success = Color("Success", bundle: .main)
    static let hairline = Color("Hairline", bundle: .main)
}

/// Manages the active color scheme. For the MVP it follows the system;
/// `ThemeManager` is the seam where a future setting could override it.
@MainActor
final class ThemeManager: ObservableObject {
    @Published var colorScheme: ColorScheme? // nil = follow system

    init() {}
}
