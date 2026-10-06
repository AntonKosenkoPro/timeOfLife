import Combine
import Foundation
import SwiftUI

/// View model for the Track capture screen (timer-capture-experience spec).
///
/// Owns the `TrackState` state machine and the elapsed-time ticker. Capture
/// is plain text: no catalog, no search sheet, no quick-create — the name
/// field is the only input, and the recents chips are exact-text shortcuts.
/// Persistence is delegated to `TimerService`, which writes only to the
/// local database (local-first-store spec).
@MainActor
final class TrackViewModel: ObservableObject {
    /// Settable (not `private(set)`) so tests can seed exact `.ready`/`.error`
    /// states directly instead of driving them through async store paths.
    @Published var state: TrackState = .idle
    @Published var elapsed: TimeInterval = 0
    @Published var errorMessage: String?
    /// The name-field draft (trimmed at Start; a draft, never committed).
    @Published var nameDraft = ""
    /// The 6 exact-text recents (newest first, first-category icon data).
    /// Settable for the same test-seeding reason as `state`.
    @Published var recents: [ExactName] = []
    /// Every committed exact-text name, newest first, uncapped — the source
    /// for the shared name picker (dedicated-name-picker). The chips stay
    /// capped at 6 (`recents`); the picker suggests everything ever used.
    @Published var allNames: [ExactName] = []
    /// The id→Category map used to resolve recents chip icons (design D5).
    @Published private(set) var categories: [String: Category] = [:]

    let service: TimerService
    private let connectivity: Connectivity
    private let nowProvider: () -> Date
    private var ticker: AnyCancellable?
    private var savedResetTask: Task<Void, Never>?

    init(
        service: TimerService,
        connectivity: Connectivity,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.connectivity = connectivity
        self.nowProvider = now
    }

    // MARK: - Recents model

    // MARK: - Lifecycle

    /// Loads the recents and categories and restores a persisted running
    /// draft (R2: the running draft survives app crashes). Reconciles an
    /// externally stopped timer: a `.running` state with no persisted draft
    /// (stopped from the compact timer on another destination) returns to
    /// `.ready`/`.idle` instead of counting elapsed time forever. Call on
    /// appear.
    func load() async {
        do {
            // Seeding lives behind the sign-in gate (`RootView`) only: this
            // load races it on first appear, and seeding is idempotent, but
            // the gate is the single owner — a second racing call site only
            // doubles file traffic on every cold start.
            recents = try await storeRecents()
            allNames = try await storeAllNames()
            categories = Dictionary(uniqueKeysWithValues: try await service.store.categories().map { ($0.id, $0) })
            let persisted = try await service.runningTimerDraft()
            if let persisted, !persisted.activityText.isEmpty {
                let startedAt = persisted.startedAt ?? Date()
                state = .running(
                    TrackState.Draft(
                        text: persisted.activityText,
                        categoryIDs: persisted.categoryIDs,
                        notes: persisted.notes
                    ),
                    startedAt: startedAt
                )
                nameDraft = persisted.activityText
                startTicker(from: startedAt)
            } else if case let .running(draft, _) = state {
                await reconcileExternalStop(draft: draft)
            }
        } catch {
            errorMessage = L10n.text(in: .default, code: "error.unknown")
        }
    }

    private func storeRecents() async throws -> [ExactName] {
        try await service.store.recents(limit: 6).map(ExactName.init(storeRecent:))
    }

    private func storeAllNames() async throws -> [ExactName] {
        try await service.store.allActivityNames().map(ExactName.init(storeRecent:))
    }

    /// Leaves a `.running` state whose persisted draft is gone (stopped from
    /// the compact timer): stops the elapsed ticker, re-enables the idle
    /// timer, resets elapsed to zero, and returns to `.ready` for the same
    /// text — or `.idle` when nothing was entered.
    /// `.saving`/`.error` are deliberately untouched: mid-flight own-stop
    /// states that self-resolve through their async paths.
    private func reconcileExternalStop(draft: TrackState.Draft) async {
        stopTicker()
        UIApplication.shared.isIdleTimerDisabled = false
        elapsed = 0
        // Same grammar as scheduleSavedReset: a restart must not inherit
        // the previous run's notes (e.g. mid-run notes preserved in memory
        // while the persisted draft was stopped elsewhere).
        state = draft.text.isEmpty
            ? .idle
            : .ready(TrackState.Draft(text: draft.text, categoryIDs: draft.categoryIDs))
    }

    // MARK: - Capture (plain text)

    /// True when the trimmed name draft is non-empty (the Start gate).
    var canStart: Bool {
        !trimmedName.isEmpty
    }

    private var trimmedName: String {
        nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Keeps the committed `.ready`/`.idle` state in step with the typed
    /// name draft while not running: a trimmed non-empty name prepares it
    /// (inheriting the exact recents match's categories), clearing the field
    /// returns to idle. Any edit re-derives the draft — including edits after
    /// a chip selection, which is just a fill. Typing never starts anything
    /// and never commits a partial draft. Called by the name field's
    /// edit/commit callbacks.
    func syncReadyFromDraft() {
        guard !state.isRunning, !state.isSaving else { return }
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if state != .idle {
                state = .idle
            }
            elapsed = 0
            return
        }
        let inherited = recents.first { $0.text == trimmed }?.categoryIDs ?? []
        let draft = TrackState.Draft(text: trimmed, categoryIDs: inherited)
        if state != .ready(draft) {
            state = .ready(draft)
            elapsed = 0
        }
    }

    /// Selects a recents chip: fills the exact text plus that recent's full
    /// ordered categories without starting timing and without creating
    /// anything.
    func select(_ recent: ExactName) {
        guard !state.isRunning else { return }
        nameDraft = recent.text
        state = .ready(TrackState.Draft(text: recent.text, categoryIDs: recent.categoryIDs))
        elapsed = 0
        Haptics.selection()
    }

    /// Starts the prepared name (timer-capture-experience spec); typing or
    /// chip selection alone never starts timing. Start is gated on the
    /// trimmed text being non-empty. A committed `.ready` draft starts
    /// exactly as prepared — typing already inherited the exact-recents
    /// match (or empty) in `syncReadyFromDraft`, and chip selection filled
    /// it in `select` — so Start never re-derives categories behind the
    /// user's back. Only from `.idle` (a Start tap that raced the field's
    /// commit) is the field synced first; an invalid `.ready` draft
    /// (empty text) is left untouched and Start does nothing.
    ///
    /// Start is immediate: naming happens on the picker page (its keyboard
    /// dismisses on pop), so Start never competes with a keyboard slide.
    func start() {
        // Tap-time sync (see `syncReadyFromDraft`): a carried-over `.ready`
        // (e.g. after a stop) may hold a stale draft for the field's current
        // text. Matching text needs no sync — this preserves programmatically
        // prepared categories and the empty-text state. `.saved` is excluded:
        // the disabled Start button is the only caller and cannot fire there.
        switch state {
        case .idle:
            syncReadyFromDraft()
        case .ready(let draft) where draft.text != nameDraft:
            syncReadyFromDraft()
        default:
            break
        }
        guard case let .ready(draft) = state, canStart else { return }
        Haptics.selection()
        beginRunning(draft: draft, startedAt: Date())
    }

    private func beginRunning(draft: TrackState.Draft, startedAt: Date) {        state = .running(draft, startedAt: startedAt)
        elapsed = 0
        errorMessage = nil
        startTicker(from: startedAt)
        UIApplication.shared.isIdleTimerDisabled = true
        Task {
            do {
                try await service.startTimerDraft(
                    text: draft.text,
                    categoryIDs: draft.categoryIDs,
                    notes: draft.notes,
                    startedAt: startedAt
                )
            } catch {
                // Local persistence failure: keep the timer running in memory
                // so the user can still stop and retry (recoverable error).
                errorMessage = L10n.text(in: .default, code: "error.unknown")
            }
        }
    }

    /// Toggles a category on the running draft (D4): rewrites only the
    /// running draft snapshot — never an entry, history row, or recents.
    func toggleDraftCategory(_ categoryID: String) {
        guard case let .running(draft, startedAt) = state else { return }
        var updated = draft
        if let index = updated.categoryIDs.firstIndex(of: categoryID) {
            updated.categoryIDs.remove(at: index)
        } else {
            updated.categoryIDs.append(categoryID)
        }
        state = .running(updated, startedAt: startedAt)
        Task {
            try? await service.startTimerDraft(
                text: updated.text,
                categoryIDs: updated.categoryIDs,
                notes: updated.notes,
                startedAt: startedAt
            )
        }
    }

    /// Saves notes on the running draft (separate-notes-editor): rewrites
    /// only the running draft notes snapshot — never an entry, history
    /// row, or recents. History learns the notes at Stop. Available in
    /// both recording states (running + error), preserving whichever holds.
    func updateDraftNotes(_ notes: String) async {
        switch state {
        case let .running(draft, startedAt):
            var updated = draft
            updated.notes = notes
            state = .running(updated, startedAt: startedAt)
        case let .error(draft, startedAt):
            var updated = draft
            updated.notes = notes
            state = .error(updated, startedAt: startedAt)
        case .idle, .ready, .saving, .saved:
            return
        }
        try? await service.updateTimerDraftNotes(notes)
    }

    /// Stops the running timer and saves the completed entry locally with
    /// the final ordered categories, the final draft notes, and a single
    /// outbox row.
    func stop() async {
        guard case let .running(draft, startedAt) = state else { return }
        state = .saving(draft, startedAt: startedAt)
        stopTicker()
        do {
            try await service.stopTimerDraft(
                text: draft.text,
                categoryIDs: draft.categoryIDs,
                startedAt: startedAt,
                endedAt: Date(),
                notes: draft.notes
            )
            let duration = max(0, Date().timeIntervalSince(startedAt))
            state = .saved(draft, duration: duration)
            elapsed = duration
            UIApplication.shared.isIdleTimerDisabled = false
            Haptics.success()
            scheduleSavedReset()
            recents = (try? await storeRecents()) ?? recents
            allNames = (try? await storeAllNames()) ?? allNames
        } catch {
            // Recoverable: preserve running state so elapsed time is not lost.
            state = .error(draft, startedAt: startedAt)
            errorMessage = L10n.text(in: .default, code: "error.unknown")
            Haptics.error()
            startTicker(from: startedAt)
        }
    }

    /// Retries Stop after a recoverable save failure.
    func retryStop() async {
        guard case let .error(draft, startedAt) = state else { return }
        state = .running(draft, startedAt: startedAt)
        await stop()
    }

    // MARK: - Ticker

    private func startTicker(from startedAt: Date) {
        ticker?.cancel()
        ticker = Ticker.everySecond { [weak self] in
            self?.elapsed = max(0, Date().timeIntervalSince(startedAt))
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    /// Returns the state to ready for the same text after the brief saved
    /// confirmation (timer-capture-experience spec). The draft notes reset
    /// to empty: each run starts noteless, and a restart must not inherit
    /// the previous run's notes.
    private func scheduleSavedReset() {
        savedResetTask?.cancel()
        savedResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            guard let self, case let .saved(draft, _) = self.state else { return }
            self.state = .ready(TrackState.Draft(text: draft.text, categoryIDs: draft.categoryIDs))
            self.elapsed = 0
        }
    }
}

#if DEBUG
extension TrackViewModel {
    static func preview(
        state: TrackState = .idle,
        recents: [ExactName] = [],
        categories: [String: Category] = [:],
        nameDraft: String = ""
    ) -> TrackViewModel {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("preview.sqlite")
        // A preview must never crash: a store failure falls back to an
        // unbound store with the failure surfaced in the error banner slot.
        let bound = try? LocalStore(url: url, userID: "preview-user")
        let vm = TrackViewModel(
            service: TimerService(store: bound ?? LocalStore()),
            connectivity: MockConnectivity(connected: true)
        )
        if bound == nil {
            vm.errorMessage = L10n.text(in: .default, code: "error.unknown")
        }
        vm.state = state
        vm.recents = recents
        vm.categories = categories
        vm.nameDraft = nameDraft
        return vm
    }
}
#endif
