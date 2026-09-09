// swiftlint:disable file_length
import Foundation
import SwiftUI
import Combine

/// View model for the Track capture screen (timer-capture-experience spec).
///
/// Owns the `TrackState` state machine, the temporary Activity-search
/// interaction state (unify-activity-preparation-flow spec), and the
/// elapsed-time ticker. Persistence is delegated to `TimerService`, which
/// writes only to the local database (local-first-store spec).
@MainActor
final class TrackViewModel: ObservableObject, ActivitySearchHosting {
    @Published private(set) var state: TrackState = .idle
    @Published var elapsed: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var isSearchActive = false
    @Published private(set) var search = ActivitySearchState()
    @Published private(set) var activities: [Activity] = []
    /// The id→Category map used to resolve Recents chip icons (design D6).
    @Published private(set) var categories: [String: Category] = [:]
    /// The non-expired pending-deletion identity matching the current query,
    /// refreshed as the query changes (result-model input, decision 7).
    @Published private(set) var pendingDeletion: Activity?

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
            categories = Dictionary(uniqueKeysWithValues: try await service.store.categories().map { ($0.id, $0) })
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

    /// The committed selection's activity id (ActivitySearchHosting
    /// checkmark input): the prepared activity, or nil while idle.
    var selectedActivityID: String? { state.activity?.id }

    /// Prepares an activity (ready state) without starting a timer.
    func select(_ activity: Activity) {        guard !state.isRunning else { return }
        state = .ready(activity)
        elapsed = 0
        isSearchActive = false
        search = ActivitySearchState()
        Haptics.selection()
    }

    // MARK: - Activity search (unify-activity-preparation-flow spec)

    /// The deterministic result model for the active search content. The
    /// non-expired pending-deletion identity (if any) is resolved from the
    /// store so the restore action can replace creation.
    var searchResults: ActivitySearchResults {
        ActivitySearchResults.derive(
            query: search.query,
            activities: activities,
            pendingDeletion: pendingDeletion
        )
    }

    /// A binding to the search query for the native search field. The query
    /// is a draft: it never mutates the committed `TrackState`.
    var searchQueryBinding: Binding<String> {
        Binding(
            get: { self.search.query },
            set: { self.setSearchQuery($0) }
        )
    }

    /// Sets the search query (draft). Used by the native search field binding
    /// and by tests; never mutates the committed `TrackState`. Refreshes the
    /// pending-deletion identity for the result model.
    func setSearchQuery(_ query: String) {
        search.query = query
        refreshPendingDeletion()
    }

    /// Refreshes the non-expired pending-deletion identity matching the
    /// trimmed query (result-model input, decision 7).
    private func refreshPendingDeletion() {
        let trimmed = search.trimmedQuery
        guard !trimmed.isEmpty else {
            pendingDeletion = nil
            return
        }
        Task {
            pendingDeletion = try? await service.store.pendingDeletionActivity(named: trimmed)
        }
    }

    /// Activates Activity search. Idle search begins empty; ready and saved
    /// search begins with the committed Activity name so it can be replaced
    /// directly. The query remains a draft and the committed Activity is
    /// retained as the fallback until a result is confirmed.
    func activateSearch() {
        guard !state.isRunning else { return }
        let initialQuery: String
        switch state {
        case let .ready(activity), let .saved(activity, _):
            initialQuery = activity.name
        case .idle, .running, .saving, .error:
            initialQuery = ""
        }
        search = ActivitySearchState(query: initialQuery)
        isSearchActive = true
        refreshPendingDeletion()
    }

    /// Syncs the native search environment state into the view model. The
    /// operating system owns activation and cancellation; this keeps the
    /// committed timer state untouched for unresolved input.
    func setSearchActive(_ active: Bool) {
        guard isSearchActive != active else { return }
        isSearchActive = active
        if !active {
            search = ActivitySearchState()
        }
    }

    /// Ends search without confirmation: the prior ready or idle timer state
    /// is restored exactly (the draft never mutated it).
    func cancelSearch() {
        isSearchActive = false
        search = ActivitySearchState()
    }

    /// Dismisses the pending-deletion restore prompt without acting.
    func dismissPendingRestore() {
        pendingRestore = nil
    }

    /// Confirms an existing search result: prepares it and dismisses search.
    func confirmSearchResult(_ activity: Activity) {
        select(activity)
    }

    /// Quick-creates the unmatched valid query (categoryless) and prepares
    /// it. On failure the search stays active with the query preserved and a
    /// localized non-field error is shown. When a pending-deletion identity
    /// surfaces at confirmation time, the explicit restore prompt is shown
    /// instead of creating a duplicate.
    func quickCreateFromSearch() async {
        let trimmed = search.trimmedQuery
        guard !trimmed.isEmpty else { return }
        do {
            let outcome = try await service.prepareActivity(named: trimmed)
            switch outcome {
            case let .created(activity), let .existing(activity):
                activities = try await service.store.activities()
                select(activity)
            case let .restorableDeletion(activity):
                pendingRestore = activity
            case .invalid:
                search.errorMessage = L10n.timerEmptyActivityError.text
            case .failure:
                search.errorMessage = L10n.text(in: .default, code: "error.unknown")
            }
        } catch {
            search.errorMessage = L10n.text(in: .default, code: "error.unknown")
        }
    }

    /// The pending-deletion activity awaiting explicit restoration.
    private(set) var pendingRestore: Activity?

    /// Explicitly restores the pending-deletion activity and prepares it.
    /// No outbox row is created (the deletion was never committed).
    func restorePendingDeletion() async {
        guard let pending = pendingRestore else { return }
        do {
            if let restored = try await service.store.restorePendingDeletionActivity(named: pending.name) {
                activities = try await service.store.activities()
                pendingRestore = nil
                select(restored)
            } else {
                // The window elapsed or the buffer was superseded: fall back
                // to ordinary creation.
                pendingRestore = nil
                await quickCreateFromSearch()
            }
        } catch {
            search.errorMessage = L10n.text(in: .default, code: "error.unknown")
        }
    }

    // MARK: - Selected-Activity refinement (refine-selected-activity-from-track)

    @Published private(set) var refinementPresentation: RefinementPresentation?

    struct RefinementPresentation: Identifiable, Equatable {
        let activity: Activity
        var id: String { activity.id }
    }

    /// Activates refinement for the selected Activity. Resolves from
    /// `LocalStore` first; stale preparation clears to idle.
    func presentRefinement() {
        guard let activity = state.activity else { return }
        Task {
            do {
                guard let resolved = try await service.store.activity(id: activity.id) else {
                    state = .idle
                    elapsed = 0
                    errorMessage = L10n.timerStalePreparationError.text
                    return
                }
                refinementPresentation = RefinementPresentation(activity: resolved)
            } catch {
                errorMessage = L10n.text(in: .default, code: "error.unknown")
            }
        }
    }

    /// Dismisses the refinement editor without acting (Cancel).
    func dismissRefinement() {
        refinementPresentation = nil
    }

    /// On refinement save, refreshes the catalog and replaces the Activity
    /// in the current state while preserving the state case and all
    /// associated timer data (decision 5): ready stays ready, running
    /// preserves startedAt and the active ticker, saving preserves
    /// startedAt, saved preserves duration, error preserves startedAt and
    /// retry behavior.
    func saveRefinement(updated: Activity) async {
        if let refreshed = try? await service.store.activities() {
            activities = refreshed
        }
        if let refreshedCategories = try? await service.store.categories() {
            categories = Dictionary(uniqueKeysWithValues: refreshedCategories.map { ($0.id, $0) })
        }
        replaceActivityInState(updated)
        refinementPresentation = nil
    }

    /// Replaces the Activity in the current state without transitioning,
    /// preserving all associated timer data.
    private func replaceActivityInState(_ updated: Activity) {
        switch state {
        case .idle:
            break
        case .ready:
            state = .ready(updated)
        case let .running(_, startedAt):
            state = .running(updated, startedAt: startedAt)
        case let .saving(_, startedAt):
            state = .saving(updated, startedAt: startedAt)
        case let .saved(_, duration):
            state = .saved(updated, duration: duration)
        case let .error(_, startedAt):
            state = .error(updated, startedAt: startedAt)
        }
    }

    // MARK: - Start / Stop

    /// Starts the prepared activity. Selection alone never starts timing
    /// (timer-capture-experience spec); Start is the only entry to running.
    /// The committed Activity identifier is revalidated first: a prepared
    /// Activity that no longer exists clears preparation and returns to idle
    /// with a localized error instead of being recreated.
    func start() {
        guard case let .ready(activity) = state else { return }
        Task {
            do {
                guard try await service.store.activity(id: activity.id) != nil else {
                    state = .idle
                    elapsed = 0
                    errorMessage = L10n.timerStalePreparationError.text
                    return
                }
                beginRunning(activity: activity)
            } catch {
                errorMessage = L10n.text(in: .default, code: "error.unknown")
            }
        }
    }

    private func beginRunning(activity: Activity) {
        let startedAt = Date()
        state = .running(activity, startedAt: startedAt)
        elapsed = 0
        errorMessage = nil
        startTicker(from: startedAt)
        UIApplication.shared.isIdleTimerDisabled = true
        Haptics.selection()
        Task {
            do {
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

#if DEBUG
extension TrackViewModel {
    static func preview(
        state: TrackState = .idle,
        activities: [Activity] = [],
        categories: [String: Category] = [:],
        query: String = "",
        isSearchActive: Bool = false,
        refinementPresentation: RefinementPresentation? = nil
    ) -> TrackViewModel {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("preview.sqlite")
        let store: LocalStore
        do {
            store = try LocalStore(url: url)
        } catch {
            fatalError("Unable to create preview store: \(error)")
        }
        let vm = TrackViewModel(
            service: TimerService(store: store),
            connectivity: MockConnectivity(connected: true)
        )
        vm.state = state
        vm.activities = activities
        vm.categories = categories
        vm.search.query = query
        vm.isSearchActive = isSearchActive
        vm.refinementPresentation = refinementPresentation
        return vm
    }
}
#endif
