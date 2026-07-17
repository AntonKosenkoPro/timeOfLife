import SwiftUI

/// The auth navigation container. Starts at sign-in; routes push sign-up,
/// forgot-password, reset-password, and verify-email.
struct AuthFlowView: View {
    @EnvironmentObject var container: AppContainer

    var body: some View {
        AppStack(
            stack: container.navigation,
            destination: { route in
                switch route {
                case .signIn:
                    SignInView(vm: SignInViewModel(service: container.authService,
                                                    connectivity: container.connectivity))
                case .signUp:
                    SignUpView(vm: SignUpViewModel(service: container.authService,
                                                    connectivity: container.connectivity))
                case .forgotPassword:
                    ForgotPasswordView(vm: ForgotPasswordViewModel(service: container.authService,
                                                                   connectivity: container.connectivity))
                case .resetPassword(let token):
                    ResetPasswordView(vm: ResetPasswordViewModel(service: container.authService,
                                                                 connectivity: container.connectivity,
                                                                 token: token))
                case .verifyEmail(let token):
                    VerifyEmailView(vm: VerifyEmailViewModel(service: container.authService,
                                                             connectivity: container.connectivity,
                                                             token: token))
                case .signedIn:
                    SignedInView()
                }
            }
        ) {
            SignInView(vm: SignInViewModel(service: container.authService,
                                           connectivity: container.connectivity))
        }
        .environmentObject(container)
    }
}