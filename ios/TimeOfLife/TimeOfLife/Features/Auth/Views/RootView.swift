import SwiftUI

/// Root view. Decides between auth flow and signed-in placeholder based on
/// `SessionStore`, and renders the offline banner.
struct RootView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var container: AppContainer

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top) {
                OfflineBanner()
                    .environmentObject(container.connectivity)
                    .animation(.easeInOut(duration: 0.2), value: container.connectivity.isConnected)
            }
            .background(Theme.backgroundPrimary.ignoresSafeArea())
            .task { await container.authService.restoreSession() }
            .onChange(of: session.state) { newState in
                // When the user signs out, drop any pushed auth routes so they land
                // on the welcome screen instead of the last pushed screen (e.g. OTP).
                if newState == .signedOut {
                    container.navigation.popToRoot()
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch session.state {
        case .signedOut:
            AuthFlowView()
        case .signedIn:
            TimerView(vm: TimerViewModel(
                service: container.timerService,
                authService: container.authService,
                connectivity: container.connectivity
            ))
        }
    }
}

/// Top banner shown when offline.
struct OfflineBanner: View {
    @EnvironmentObject var connectivity: Connectivity

    var body: some View {
        if !connectivity.isConnected {
            Text(L10n.offlineBanner.text)
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
