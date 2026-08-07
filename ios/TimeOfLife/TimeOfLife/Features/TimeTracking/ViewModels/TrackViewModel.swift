import Foundation
import SwiftUI
import Combine

/// View model for the Track capture screen (timer-capture-experience spec).
///
/// Owns the `TrackState` state machine, the activity chooser data, and the
/// elapsed-time ticker. Persistence is delegated to `TimerService`, which
/// writes only to the local database (local-first-store spec).
@MainActor
final class TrackViewModel: ObservableObject {
    @Published private(set) var state: TrackState = .idle
    @Published var elapsed: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var isChoosingActivity = false
    @Published var chooserQuery = ""
    @Published private(set) var activities: [Activity] = []

    let service: TimerService
    private let connectivity: Connectivity
    private var ticker: AnyCancellable?
    private var savedResetTask: Task<Void, Never>?

    init(service: TimerService, connectivity: Connectivity) {
        self.service = service
        self.connectivity = connectivity
    }

    // MARK: - Lifecycle

    /// Loads the catalog and restores a persisted running timer (R2: the
    /// running timer survives app crashes). Call on appear.
    func load() async {
        do {
            activities = try await service.store.activities()
            if let running = try await service.runningTimerState(),
               let activityID = running.activityID,
               let activity = try await service.store.activity(id: activityID) {
                let startedAt = running.startedAt ?? Date()
                state = .running(activity, startedAt: startedAt)
                startTicker(from: startedAt)
            }
        } catch {
            errorMessage = L10n.text(in: .default, code: "error.unknown")
        }
    }

    // MARK: - Activity selection

    /// Prepares an activity (ready state) without starting a timer.
    func select(_ activity: Activity) {
        guard !state.isRunning else { return }
        state = .ready(activity)
        elapsed = 0
        isChoosingActivity = false
        Haptics.selection()
    }

    /// Creates an activity from unmatched chooser input and prepares it.
    func createActivity(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let activity = try await service.ensureActivity(named: trimmed)
            activities = try await service.store.activities()
            select(activity)
        } catch {
            errorMessage = L10n.text(in: .default, code: "error.unknown")
        }
    }

    // MARK: - Start / Stop

    /// Starts the prepared activity. Selection alone never starts timing
    /// (timer-capture-experience spec); Start is the only entry to running.
    func start() {
        guard case let .ready(activity) = state else { return }
        let startedAt = Date()
        state = .running(activity, startedAt: startedAt)
        elapsed = 0
        errorMessage = nil
        startTicker(from: startedAt)
        UIApplication.shared.isIdleTimerDisabled = true
        Haptics.selection()
        Task {
            do {
                // Ensure the activity row exists (auto-create, F4) so the
                // persisted timer state and the later entry insert hold.
                _ = try await service.ensureActivity(id: activity.id, name: activity.name)
                try await service.startTimer(activityID: activity.id, startedAt: startedAt)
            } catch {
                // Local persistence failure: keep the timer running in memory
                // so the user can still stop and retry (recoverable error).
                errorMessage = L10n.text(in: .default, code: "error.unknown")
            }
        }
    }

    /// Stops the running timer and saves the completed entry locally.
    func stop() async {
        guard case let .running(activity, startedAt) = state else { return }
        state = .saving(activity, startedAt: startedAt)
        stopTicker()
        do {
            try await service.stopTimer(activityID: activity.id, startedAt: startedAt, endedAt: Date())
            let duration = max(0, Date().timeIntervalSince(startedAt))
            state = .saved(activity, duration: duration)
            elapsed = duration
            UIApplication.shared.isIdleTimerDisabled = false
            Haptics.success()
            scheduleSavedReset()
        } catch {
            // Recoverable: preserve running state so elapsed time is not lost.
            state = .error(activity, startedAt: startedAt)
            errorMessage = L10n.text(in: .default, code: "error.unknown")
            Haptics.error()
            startTicker(from: startedAt)
        }
    }

    /// Retries Stop after a recoverable save failure.
    func retryStop() async {
        guard case let .error(activity, startedAt) = state else { return }
        state = .running(activity, startedAt: startedAt)
        await stop()
    }

    // MARK: - Chooser

    /// Recency-ordered activities, filtered case-insensitively by the query.
    var filteredActivities: [Activity] {
        let query = chooserQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return activities }
        return activities.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// True when the trimmed query has no case-insensitive match — the chooser
    /// then offers `Create "Name"`.
    var canCreateFromQuery: Bool {
        let query = chooserQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return false }
        return !activities.contains { $0.name.caseInsensitiveCompare(query) == .orderedSame }
    }

    // MARK: - Ticker

    private func startTicker(from startedAt: Date) {
        ticker?.cancel()
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.elapsed = max(0, Date().timeIntervalSince(startedAt))
            }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    /// Returns the state to ready for the same activity after the brief
    /// saved confirmation (timer-capture-experience spec).
    private func scheduleSavedReset() {
        savedResetTask?.cancel()
        savedResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            guard let self, case let .saved(activity, _) = self.state else { return }
            self.state = .ready(activity)
            self.elapsed = 0
        }
    }
}
