import SwiftUI
import Combine

/// Root view. Always shows the app shell (D7): the app launches into Track
/// with no account required. `SessionStore.state` gates `SyncController` (the
/// optional paid sync feature), not the root view.
///
/// Also owns the lifecycle wiring for the local-first machinery:
/// - cold launch → commit buffered deletions left over from the previous
///   process (an app restart finalizes whatever is still buffered) and
///   trigger a sync cycle (sync-client spec).
/// - connectivity restored → trigger a sync cycle.
///
/// While the process is alive nothing expires: foreground/background cycles
/// never commit the undo buffer.
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
            .task {
                await container.authService.restoreSession()
                // A restart finalizes deletions buffered by the previous
                // process; only then run the first sync cycle.
                try? await container.undoBuffer.commitAll()
                container.syncController.trigger()
                await seedStarterCategoriesIfNeeded()
            }
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
                // Foregrounding never touches the undo buffer (buffered
                // deletions stay restorable until the app restarts).
                // Then run a sync cycle if signed in.
                Task {
                    container.syncController.trigger()
                }
            }
    }

    /// Seeds the seven localized starter categories on first local dataset
    /// setup (category-management D2). Names are materialized in the active
    /// supported language once; the marker prevents re-seeding, and the
    /// operation is a no-op after the first launch.
    private func seedStarterCategoriesIfNeeded() async {
        let names = [
            L10n.categorySeedWork.text,
            L10n.categorySeedHobby.text,
            L10n.categorySeedSport.text,
            L10n.categorySeedEducation.text,
            L10n.categorySeedRelax.text,
            L10n.categorySeedSleep.text,
            L10n.categorySeedEntertainment.text,
        ]
        _ = try? await container.localStore.seedStarterCategoriesIfNeeded(names: names)
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
