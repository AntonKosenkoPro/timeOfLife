import SwiftUI

/// A circular button for icon-only actions.
///
/// The frame is at least `Theme.minTapArea` in both dimensions to satisfy
/// Apple HIG minimum touch targets.
struct IconButton: View {
    let icon: String
    let accessibilityId: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.bold())
                .foregroundStyle(Theme.accentPrimary)
                .frame(width: Theme.minTapArea, height: Theme.minTapArea)
        }
        .disabled(isDisabled)
        .accessibilityIdentifier(accessibilityId)
    }
}

#if DEBUG
#Preview("Icon Button") {
    IconButton(
        icon: "gear",
        accessibilityId: "PreviewIconButton",
        isDisabled: false
    ) {}
}
#endif
