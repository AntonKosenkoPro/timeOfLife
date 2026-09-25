import SwiftUI
import Combine

/// Root view: the mandatory auth gate (account-bound-local-data).
///
/// Signed out → the auth flow, full-screen (app-shell spec): never the shell,
/// never a sheet, no dismiss path back into the app. Signed in → the app
/// shell. `SessionStore.state` is the single gate every surface consults.
///
/// The local-first lifecycle wiring moves behind the gate: everything that
/// touches the active account's store (cold-launch undo-buffer commit,
/// starter seeding, sync activation + the first-sync cycle) runs only once a
/// session exists — see `runSignedInStartup`. The gate itself never reads or
/// writes tracker data (local-first-store spec).
struct RootView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var container: AppContainer

    var body: some View {
        Group {
            switch session.state {
            case .signedIn(let session):
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
                    .task { await runSignedInStartup(userID: session.id) }
            case .signedOut:
                AuthFlowView()
            }
        }
            .background(Theme.backgroundPrimary.ignoresSafeArea())
            .task {
                // Restores a cached session (signed-in → the shell mounts and
                // runs the startup above) or leaves the gate up.
                await container.authService.restoreSession()
            }
            .onChange(of: session.state) { newState in
                switch newState {
                case .signedIn:
                    break
                case .signedOut:
                    // Sync stops before the file closes: an in-flight cycle
                    // aborts at its next stage guard, then the account's file
                    // goes dormant (logout keeps all files).
                    container.syncController.deactivate()
                    Task { await container.closeLocalStore() }
                }
            }
            .onChange(of: container.connectivity.isConnected) { connected in
                if connected, case .signedIn = session.state {
                    container.syncController.trigger(userID: sessionUserID())
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                // Foregrounding never touches the undo buffer (buffered
                // deletions stay restorable until their push succeeds).
                if case .signedIn = session.state {
                    container.syncController.trigger(userID: sessionUserID())
                }
            }
    }

    /// Runs once per signed-in shell mount: every sign-in path (fresh OTP/
    /// Apple sign-in, silent session restore at launch, re-login) lands here.
    /// Ordering matters: the account's file is opened FIRST (`lifio_<userId>.db`
    /// via `openLocalStore`, account-bound-store spec — nothing may touch a
    /// tracker file before an account is bound); a restart then finalizes
    /// deletions buffered by the previous process BEFORE the first sync cycle
    /// runs; seeding is idempotent (per-file marker) and activation records
    /// the bound account and performs the pull-first first-sync (sync-client
    /// spec).
    private func runSignedInStartup(userID: String) async {
        await container.openLocalStore(userID: userID)
        try? await container.undoBuffer.commitAll()
        container.syncController.activate(userID: userID)
        await seedStarterCategoriesIfNeeded()
    }

    /// The authenticated session's `userId` (empty when signed out — callers
    /// gate on `session.state` first). Feeds the sync same-account guard.
    private func sessionUserID() -> String {
        if case let .signedIn(session) = session.state { return session.id }
        return ""
    }

    /// Seeds the seven localized starter categories on the active local
    /// dataset's first setup (category-management D2). Names are materialized
    /// in the active supported language once; the marker prevents re-seeding,
    /// and the operation is a no-op after the first launch.
    private func seedStarterCategoriesIfNeeded() async {
        _ = try? await container.localStore.seedStarterCategoriesIfNeeded(names: String.starterCategoryNames)
    }
}

/// Top banner shown when offline (offline signed-in keeps working; the gate
/// needs no banner — the auth flow is fully offline-capable).
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
