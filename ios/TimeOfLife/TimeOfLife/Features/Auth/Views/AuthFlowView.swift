import SwiftUI

/// The auth navigation container. Passwordless: root is `EmailEntryView`;
/// routes push `OtpEntryView` and `SignedInView`.
struct AuthFlowView: View {
    @EnvironmentObject var container: AppContainer

    var body: some View {
        AppStack(
            stack: container.navigation,
            destination: { route in
                switch route {
                case .emailEntry:
                    EmailEntryView(vm: EmailEntryViewModel(service: container.authService,
                                                           connectivity: container.connectivity))
                case .otpEntry(let email):
                    OtpEntryView(vm: OtpEntryViewModel(service: container.authService,
                                                        connectivity: container.connectivity,
                                                        email: email))
                case .signedIn:
                    SignedInView()
                }
            }
        ) {
            EmailEntryView(vm: EmailEntryViewModel(service: container.authService,
                                                    connectivity: container.connectivity))
        }
        .environmentObject(container)
    }
}
