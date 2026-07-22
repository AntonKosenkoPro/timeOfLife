import AuthenticationServices
import SwiftUI
import UIKit

/// "Sign in with Apple" button.
///
/// Renders Apple's official `ASAuthorizationAppleIDButton` (a UIControl) and
/// forwards taps to `action`, which drives the authorization flow through
/// `AppleSignInService`. A transparent overlay `Button` captures the tap so the
/// underlying control never fires its own (unconfigured) target-action — the
/// service's `ASAuthorizationController` is the single presenter.
///
/// The button renders without the Sign in with Apple capability; only the
/// actual authorization requires it.
struct AppleSignInButton: View {
    let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    var body: some View {
        AppleIDButtonControl()
            .frame(height: 54)
            .overlay {
                Button(action: action) {
                    Color.clear
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("AppleSignInButton")
            }
    }
}

/// `ASAuthorizationAppleIDButton` is a UIKit `UIControl`; wrap it so SwiftUI can
/// display it. It carries no target — taps are handled by the overlay.
private struct AppleIDButtonControl: UIViewRepresentable {
    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(
            authorizationButtonType: .signIn,
            authorizationButtonStyle: .black
        )
        button.cornerRadius = Theme.cornerRadius
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}
}

#if DEBUG
#Preview("Apple Sign In Button") {
    AppleSignInButton { }
        .padding()
}
#endif
