import SwiftUI

// DEFERRED: F2 — Sign in with Apple. Disabled "coming soon" button.
struct AppleSignInButton: View {
    var body: some View {
        Button {
            // No-op until F2 lands.
        } label: {
            Text("\(L10n.appleSignInTitle.text) (\(L10n.appleSignInComingSoon.text))")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(true)
        .accessibilityIdentifier("AppleSignInButton")
    }
}

#if DEBUG
#Preview("Apple Sign In Button") {
    AppleSignInButton()
        .padding()
}
#endif
