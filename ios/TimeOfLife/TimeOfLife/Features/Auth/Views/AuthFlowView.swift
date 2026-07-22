import SwiftUI

/// The auth navigation container. Passwordless: root is `EmailEntryView`;
/// routes push `OtpEntryView`, `SignedInView`, and `TimerView`.
struct AuthFlowView: View {
    @EnvironmentObject var container: AppContainer

    var body: some View {
        AppStack(
            stack: container.navigation,
            destination: { route in
                switch route {
                case .emailEntry:
                    EmailEntryView(vm: EmailEntryViewModel(
                        service: container.authService,
                        connectivity: container.connectivity,
                        appleService: container.appleService,
                        sessionStore: container.sessionStore
                    ))
                case .otpEntry(let email):
                    OtpEntryView(vm: OtpEntryViewModel(
                        service: container.authService,
                        connectivity: container.connectivity,
                        email: email
                    ))
                case .signedIn:
                    SignedInView()
                case .timer:
                    TimerView(vm: TimerViewModel(
                        service: container.timerService,
                        connectivity: container.connectivity
                    ))
                }
            },
            root: {
                EmailEntryView(vm: EmailEntryViewModel(
                    service: container.authService,
                    connectivity: container.connectivity,
                    appleService: container.appleService,
                    sessionStore: container.sessionStore
                ))
            }
        )
        .environmentObject(container)
    }
}
