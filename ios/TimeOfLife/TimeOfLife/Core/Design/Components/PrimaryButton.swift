import SwiftUI

/// Full-width prominent action button.
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
            if isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: Theme.spacingSmall) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.body.bold())
                    }
                    Text(title)
                        .font(.body.bold())
                }
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isLoading || isDisabled)
        .accessibilityIdentifier(accessibilityId)
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
