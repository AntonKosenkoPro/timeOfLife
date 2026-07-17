import SwiftUI

// DEFERRED: F2 — Sign in with Apple. Disabled "coming soon" button.
struct AppleSignInButton: View {
    var body: some View {
        Button {
            // No-op until F2 lands.
        } label: {
            Text("\(NSLocalizedString("appleSignIn.title", comment: "")) (\(NSLocalizedString("appleSignIn.comingSoon", comment: "")))")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(true)
        .accessibilityIdentifier("AppleSignInButton")
    }
}