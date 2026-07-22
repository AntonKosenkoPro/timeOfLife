import SwiftUI

/// Full-width prominent action button.
///
/// Renders as a fixed-height (54pt) filled rectangle with `Theme.cornerRadius`
/// and continuous corners. This deliberately mirrors the geometry of
/// `AppleSignInButton`, which hosts Apple's `ASAuthorizationAppleIDButton` at the
/// same height and corner radius. Matching the geometry matters for two reasons:
///
/// 1. **Shape parity** — on iOS 27 the system `.borderedProminent` style renders
///    as a floating liquid-glass capsule with different corner radius/height than
///    the pinned Apple control, so the two buttons looked mismatched.
/// 2. **Keyboard animation** — the action bar lives in `safeAreaInset`, whose
///    content tracks the system keyboard transition. A fixed-height solid view
///    follows that transition cleanly, whereas the system prominent style's
///    own floating treatment animated independently ("floating behind the
///    keyboard with strange animation").
///
/// Shows a loading spinner when `isLoading` is true and disables interaction
/// when loading or explicitly disabled. Primary actions across the app use
/// this component.
struct PrimaryButton: View {
    let title: String
    let icon: String?
    let isLoading: Bool
    let isDisabled: Bool
    let accessibilityId: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    HStack(spacing: Theme.spacingSmall) {
                        if let icon {
                            Image(systemName: icon)
                                .font(.body.bold())
                        }
                        Text(title)
                            .font(.body.bold())
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(.white)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .disabled(isLoading || isDisabled)
        .opacity(isLoading || isDisabled ? 0.6 : 1)
        .animation(.easeInOut(duration: 0.15), value: isLoading || isDisabled)
        .accessibilityIdentifier(accessibilityId)
    }

    /// Filled accent background, dimmed while the button is inactive.
    private var background: Color {
        if isLoading || isDisabled {
            return Theme.color(Theme.accentPrimary, alpha: 0.5)
        }
        return Theme.accentPrimary
    }
}

#if DEBUG
#Preview("Primary Button — Default") {
    PrimaryButton(
        title: L10n.emailEntrySubmit.text,
        icon: nil,
        isLoading: false,
        isDisabled: false,
        accessibilityId: "PreviewPrimaryButton"
    ) {}
    .padding()
}

#Preview("Primary Button — Loading") {
    PrimaryButton(
        title: L10n.emailEntrySubmit.text,
        icon: nil,
        isLoading: true,
        isDisabled: false,
        accessibilityId: "PreviewPrimaryButtonLoading"
    ) {}
    .padding()
}

#Preview("Primary Button — Disabled") {
    PrimaryButton(
        title: L10n.emailEntrySubmit.text,
        icon: nil,
        isLoading: false,
        isDisabled: true,
        accessibilityId: "PreviewPrimaryButtonDisabled"
    ) {}
    .padding()
}

#Preview("Primary Button — With Icon") {
    PrimaryButton(
        title: L10n.timerStart.text,
        icon: "play.fill",
        isLoading: false,
        isDisabled: false,
        accessibilityId: "PreviewPrimaryButtonIcon"
    ) {}
    .padding()
}

#endif
