import Foundation

/// Pull-to-refresh verdict logic for the History list (history-pull-to-sync
/// spec). Owns the refresh decision so it is unit-testable — `HistoryView`
/// only binds the notice, the error dialog, and the Enable Sync sheet.
///
/// The pull is sync-only: it never reloads local data directly. The existing
/// `sync.status` cycle-exit observer in `HistoryView` stays the sole reload
/// path. Verdict order: signed-out → signed-out notice (no network traffic);
/// offline → offline notice (no cycle burned); otherwise await a fresh or
/// joined cycle and surface its error, if any, as dialog content. A
/// connectivity loss mid-cycle is a cycle failure, so it routes to the
/// dialog — never back to the offline notice.
@MainActor
final class HistoryPullModel: ObservableObject {
    /// Inline notice shown below the navigation bar (one at a time).
    enum Notice: Equatable {
        case signedOut
        case offline
    }

    /// The currently visible inline notice (nil = none).
    @Published private(set) var notice: Notice?
    /// Secret-free message of the last pull-awaited cycle failure (nil = no
    /// dialog). Set only by `refresh()` — background cycles never touch it.
    @Published private(set) var syncErrorMessage: String?

    private let sync: SyncController
    private let session: SessionStore
    private let connectivity: Connectivity
    private let noticeLifetime: TimeInterval
    private var dismissTask: Task<Void, Never>?

    init(
        sync: SyncController,
        session: SessionStore,
        connectivity: Connectivity,
        noticeLifetime: TimeInterval = 5
    ) {
        self.sync = sync
        self.session = session
        self.connectivity = connectivity
        self.noticeLifetime = noticeLifetime
    }

    /// Runs the pull verdict flow. The native spinner ticks exactly as long
    /// as this awaits (fresh or joined cycle); pre-check verdicts return
    /// immediately with no spinner wait and no network traffic.
    func refresh() async {
        guard case .signedIn = session.state else {
            showNotice(.signedOut)
            return
        }
        guard connectivity.isConnected else {
            showNotice(.offline)
            return
        }
        await sync.syncNow()
        if case let .error(message) = sync.status {
            syncErrorMessage = message
        }
    }

    /// Dismisses the notice immediately (navigation away, sign-in flip).
    func cancelNotice() {
        dismissTask?.cancel()
        dismissTask = nil
        notice = nil
    }

    /// Clears the error dialog (OK tap).
    func clearError() {
        syncErrorMessage = nil
    }

    /// Shows a notice with a 5-second auto-dismiss; re-pull cancels and
    /// restarts the timer (newest pull wins).
    private func showNotice(_ notice: Notice) {
        self.notice = notice
        dismissTask?.cancel()
        dismissTask = Task { [weak self, noticeLifetime] in
            try? await Task.sleep(nanoseconds: UInt64(noticeLifetime * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }
}
