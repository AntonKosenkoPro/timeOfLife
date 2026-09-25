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
/// session exists — see `beginSignIn`. The gate itself never reads or
/// writes tracker data (local-first-store spec).
struct RootView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var container: AppContainer
    /// The account whose file has finished binding and is safe for tracker
    /// reads. Nil while the bind is in flight (fresh sign-in, restore,
    /// re-login) or after sign-out. The shell mounts only once this matches
    /// the signed-in session id (bind-then-reveal): no tracker read (Track /
    /// shell `.load()`) precedes `openLocalStore`, so a fresh sign-in never
    /// flashes `error.unknown` from `LocalStoreError.notBound`.
    @State private var boundUserID: String?
    /// Serializes the account-bound store lifecycle across rapid
    /// transitions: every sign-in/sign-out cancels its predecessor, so a
    /// late sign-out close can never unbind a newer sign-in's file
    /// (open-after-close).
    @State private var lifecycleTask: Task<Void, Never>?

    var body: some View {
        Group {
            switch session.state {
            case .signedIn(let current):
                if boundUserID == current.id {
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
                } else {
                    // Bind-then-reveal: the gate stays up (a spinner, never
                    // the shell) until the account's file is bound. The
                    // startup runs here — not in `onChange` — so it fires on
                    // every shell mount, including the restore-driven one.
                    // A failed bind keeps the gate up with the error surfaced
                    // instead of the shell — the store is unbound, so no
                    // tracker read may mount.
                    if container.localStoreOpenError != nil {
                        Text(L10n.errorLocalPersistence.text)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityIdentifier("LocalStoreOpenError")
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .task { beginSignIn(userID: current.id) }
                    }
                }
            case .signedOut:
                AuthFlowView()
            }
        }
            .background(Theme.backgroundPrimary.ignoresSafeArea())
            .task {
                // Restores a cached session (signed-in → the binding
                // placeholder above mounts and runs the startup) or leaves
                // the gate up.
                await container.authService.restoreSession()
            }
            .onChange(of: session.state) { newState in
                switch newState {
                case .signedIn:
                    break
                case .signedOut:
                    beginSignOut()
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
    ///
    /// The caller cancels superseded lifecycles, so every suspension point
    /// re-checks cancellation and the live session: a sign-out that lands
    /// mid-bind must neither reveal the shell nor activate sync for it.
    private func beginSignIn(userID: String) {
        lifecycleTask?.cancel()
        lifecycleTask = Task {
            if Task.isCancelled { return }
            let opened = await container.openLocalStore(userID: userID)
            if Task.isCancelled { return }
            guard case let .signedIn(current) = session.state, current.id == userID else { return }
            // A failed bind leaves the store cleanly unbound: the gate stays
            // up (the error is surfaced via `localStoreOpenError` above) and
            // `boundUserID` is never set — commitAll/seed/sync must not run
            // against the wrong file or an unbound store. The next sign-in
            // (or relaunch restore) retries the bind.
            guard opened else { return }
            boundUserID = userID
            try? await container.undoBuffer.commitAll()
            if Task.isCancelled { return }
            guard case let .signedIn(current) = session.state, current.id == userID else { return }
            container.syncController.activate(userID: userID)
            await seedStarterCategoriesIfNeeded()
        }
    }

    /// Tears down the signed-in lifecycle on every transition to `.signedOut`
    /// (plain logout and server-driven revocation alike): stops sync, clears
    /// stale auth routes so the gate never reopens on a pre-filled OTP
    /// screen, hides the shell, then closes the account's file (logout keeps
    /// all files) — but only after the in-flight cycle actually ended and
    /// only while still signed out, so a fast re-login's file stays bound
    /// (open-after-close).
    private func beginSignOut() {
        // Sync stops before the file closes: an in-flight cycle aborts at
        // its next stage guard, then the account's file goes dormant.
        container.syncController.deactivate()
        container.navigation.path = []
        boundUserID = nil
        lifecycleTask?.cancel()
        lifecycleTask = Task {
            await waitForSyncShutdown()
            guard !Task.isCancelled else { return }
            // Rapid re-login flips the state before the close runs: skip it.
            // The guard and the close share one MainActor turn, so no flip
            // can slip between them — the close always precedes a later open.
            guard case .signedOut = session.state else { return }
            await container.closeLocalStore()
        }
    }

    /// Waits until SyncController's in-flight cycle actually ends
    /// (`deactivate()` only requests cancellation) so `closeLocalStore`
    /// never pulls the file out from under a running cycle — which would
    /// surface `notBound` as `.error` instead of `.inactive` and strand the
    /// next sign-in's `activate` (it only runs from `.inactive`). Bounded:
    /// the cycle is already cancelled, so it resolves on its next
    /// suspension point.
    private func waitForSyncShutdown() async {
        let deadline = Date().addingTimeInterval(2)
        while !Task.isCancelled, container.syncController.isCycleLive, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
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
