import SwiftUI

/// Root view. Decides between auth flow and signed-in placeholder based on
/// `SessionStore`, and renders the offline banner.
struct RootView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var container: AppContainer

    var body: some View {
        ZStack(alignment: .top) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            OfflineBanner()
                .environmentObject(container.connectivity)
        }
        .background(Theme.backgroundPrimary.ignoresSafeArea())
        .task { await container.authService.restoreSession() }
    }

    @ViewBuilder
    private var content: some View {
        switch session.state {
        case .signedOut:
            AuthFlowView()
        case .signedIn:
            SignedInView()
        case .verifyingEmail(let token):
            VerifyEmailView(vm: VerifyEmailViewModel(
                service: container.authService,
                connectivity: container.connectivity,
                token: token
            ))
        }
    }
}

/// Top banner shown when offline.
struct OfflineBanner: View {
    @EnvironmentObject var connectivity: Connectivity

    var body: some View {
        if !connectivity.isConnected {
            Text(NSLocalizedString("offline.banner", comment: ""))
                .font(.footnote)
                .foregroundStyle(.white)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(Theme.danger)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityIdentifier("OfflineBanner")
        }
    }
}