import SwiftUI

/// A simple left-aligned wrapping layout for chips and tags.
/// Used by `TagSelector` to wrap category chips without clipping.
///
/// Uses `LazyVGrid` with adaptive columns for iOS 15 compatibility
/// (the `Layout` protocol is iOS 16+).
struct FlowLayout: View {
    let spacing: CGFloat
    let content: () -> AnyView

    init(spacing: CGFloat = Theme.spacingSmall, @ViewBuilder content: @escaping () -> some View) {
        self.spacing = spacing
        self.content = { AnyView(content()) }
    }

    var body: some View {
        // For iOS 15 compatibility, `LazyVGrid` with adaptive minimum column
        // width wraps chips naturally. The `Layout` protocol is iOS 16+.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 80), spacing: spacing, alignment: .leading)],
            alignment: .leading,
            spacing: spacing
        ) {
            content()
        }
    }
}
