import SwiftUI
import Combine

/// Root view. Always shows the app shell (D7): the app launches into Track
/// with no account required. `SessionStore.state` gates `SyncController` (the
/// optional paid sync feature), not the root view.
///
/// Also owns the lifecycle wiring for the local-first machinery:
/// - foreground → commit expired undo buffers (D3, no background timer) and
///   trigger a sync cycle (sync-client spec).
/// - connectivity restored → trigger a sync cycle.
struct RootView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var container: AppContainer

    var body: some View {
        AppShellView(
            vm: AppShellViewModel(service: container.timerService),
            container: container
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top) {
                OfflineBanner()
                    .environmentObject(container.connectivity)
                    .animation(.easeInOut(duration: 0.2), value: container.connectivity.isConnected)
            }
            .background(Theme.backgroundPrimary.ignoresSafeArea())
            .task { await container.authService.restoreSession() }
            .onChange(of: session.state) { newState in
                switch newState {
                case .signedIn:
                    container.syncController.activate()
                case .signedOut:
                    container.syncController.deactivate()
                }
            }
            .onChange(of: container.connectivity.isConnected) { connected in
                if connected {
                    container.syncController.trigger()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                // Durable undo buffer: commit expired deletions on foreground
                // (never in the background). Then run a sync cycle if signed in.
                Task {
                    try? await container.undoBuffer.commitExpired()
                    container.syncController.trigger()
                }
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
