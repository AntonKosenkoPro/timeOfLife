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
    @Published var recents: [RecentEntry] = []
    /// The id→Category map used to resolve recents chip icons (design D5).
    @Published private(set) var categories: [String: Category] = [:]

    let service: TimerService
    private let connectivity: Connectivity
    private let nowProvider: () -> Date
    private var ticker: AnyCancellable?
    private var savedResetTask: Task<Void, Never>?
    /// Name-field focus from the view: a focused Start tap resigns first and
    /// the swap waits out the keyboard slide, so Stop appears in place.
    var nameFieldFocused = false
    /// A Start deferred until the keyboard finishes dismissing (see above).
    /// Cancelled by any draft change before it fires, so a stale draft can
    /// never start.
    private var pendingStart: Task<Void, Never>?

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

    /// One recents chip: the exact text, its newest entry's first-position
    /// category (icon source), and the full ordered categories a tap
    /// inherits (design D5).
    struct RecentEntry: Identifiable, Equatable {
        let text: String
        let categoryIDs: [String]
        /// The first-position category id, or nil when the newest entry has
        /// no categories (the chip renders without an icon).
        let firstCategoryID: String?

        var id: String { text }
    }

    // MARK: - Lifecycle

    /// Loads the recents and categories and restores a persisted running
    /// draft (R2: the running draft survives app crashes). Reconciles an
    /// externally stopped timer: a `.running` state with no persisted draft
    /// (stopped from the compact timer on another destination) returns to
    /// `.ready`/`.idle` instead of counting elapsed time forever. Call on
    /// appear.
    func load() async {
        do {
            // Seed first: on a fresh install the seeding task in RootView
            // can still be in flight when this first load runs, which used
            // to leave the running tag selector empty until the next tab
            // switch. Seeding is idempotent (marker-guarded), so racing it
            // here is safe.
            _ = try? await service.store.seedStarterCategoriesIfNeeded(names: String.starterCategoryNames)
            recents = try await storeRecents()
            categories = Dictionary(uniqueKeysWithValues: try await service.store.categories().map { ($0.id, $0) })
            let persisted = try await service.runningTimerDraft()
            if let persisted, !persisted.activityText.isEmpty {
                let startedAt = persisted.startedAt ?? Date()
                state = .running(
                    TrackState.Draft(text: persisted.activityText, categoryIDs: persisted.categoryIDs),
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

    private func storeRecents() async throws -> [RecentEntry] {
        try await service.store.recents(limit: 6).map { recent in
            RecentEntry(
                text: recent.activityText,
                categoryIDs: recent.categoryIDs,
                firstCategoryID: recent.categoryIDs.first
            )
        }
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
        state = draft.text.isEmpty ? .idle : .ready(draft)
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
                pendingStart?.cancel()
                pendingStart = nil
            }
            elapsed = 0
            return
        }
        let inherited = recents.first { $0.text == trimmed }?.categoryIDs ?? []
        let draft = TrackState.Draft(text: trimmed, categoryIDs: inherited)
        if state != .ready(draft) {
            state = .ready(draft)
            // The draft changed under a deferred Start (e.g. the resign
            // after a tap recomputed it): a changed draft cancels the
            // pending start so a stale draft can never start. An unchanged
            // recompute keeps a pending start valid.
            pendingStart?.cancel()
            pendingStart = nil
            elapsed = 0
        }
    }

    /// Selects a recents chip: fills the exact text plus that recent's full
    /// ordered categories without starting timing and without creating
    /// anything.
    func select(_ recent: RecentEntry) {
        guard !state.isRunning else { return }
        pendingStart?.cancel()
        pendingStart = nil
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
    /// focus-resign) is the field synced first; an invalid `.ready` draft
    /// (empty text) is left untouched and Start does nothing.
    ///
    /// When the field is focused, the tap also resigns it: the keyboard
    /// slide and the running swap must not coincide, so the swap waits for
    /// the keyboard to actually finish dismissing (see
    /// `waitForKeyboardDismissal`) while the haptic fires immediately and
    /// `startedAt` stays the tap time. When nothing is focused (chip flow),
    /// Start is immediate.
    func start() {
        // Tap-time sync (see `syncReadyFromDraft`): a carried-over `.ready`
        // (e.g. after a stop) may hold a stale draft for the field's current
        // text. Syncing first means the deferred swap below captures the
        // fresh draft, so the tap's own focus-resign finds nothing to cancel.
        // Matching text needs no sync — this preserves programmatically
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
        if nameFieldFocused {
            nameFieldFocused = false
            Haptics.selection()
            let startedAt = Date()
            pendingStart?.cancel()
            pendingStart = Task { [weak self] in
                await Self.waitForKeyboardDismissal()
                guard !Task.isCancelled else { return }
                guard let self, case .ready = self.state else { return }
                self.beginRunning(draft: draft, startedAt: startedAt)
            }
        } else {
            Haptics.selection()
            beginRunning(draft: draft, startedAt: Date())
        }
    }

    /// Waits for the keyboard-dismissal slide to finish so the running swap
    /// lands on a settled layout. Fires on the real `didHide` notification —
    /// a fixed delay guesses wrong on devices whose slide outlasts it — with
    /// a bounded fallback for hardware keyboards, where no dismissal fires.
    private static func waitForKeyboardDismissal() async {
        await withTaskGroup(of: String.self) { group in
            group.addTask {
                let dismissed = NotificationCenter.default.notifications(
                    named: UIResponder.keyboardDidHideNotification
                )
                for await _ in dismissed.prefix(1) { break }
                return "didHide"
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: Self.keyboardDismissFallback)
                return "fallback"
            }
            _ = await group.next()
            group.cancelAll()
        }
    }

    /// Upper bound for the dismissal wait (hardware keyboards never notify).
    private static let keyboardDismissFallback: UInt64 = 600_000_000

    private func beginRunning(draft: TrackState.Draft, startedAt: Date) {
        pendingStart?.cancel()
        pendingStart = nil
        state = .running(draft, startedAt: startedAt)
        elapsed = 0
        errorMessage = nil
        startTicker(from: startedAt)
        UIApplication.shared.isIdleTimerDisabled = true
        Task {
            do {
                try await service.startTimerDraft(text: draft.text, categoryIDs: draft.categoryIDs, startedAt: startedAt)
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
                startedAt: startedAt
            )
        }
    }

    /// Stops the running timer and saves the completed entry locally with
    /// the final ordered categories (empty notes) and a single outbox row.
    func stop() async {
        guard case let .running(draft, startedAt) = state else { return }
        state = .saving(draft, startedAt: startedAt)
        stopTicker()
        do {
            try await service.stopTimerDraft(
                text: draft.text,
                categoryIDs: draft.categoryIDs,
                startedAt: startedAt,
                endedAt: Date()
            )
            let duration = max(0, Date().timeIntervalSince(startedAt))
            state = .saved(draft, duration: duration)
            elapsed = duration
            UIApplication.shared.isIdleTimerDisabled = false
            Haptics.success()
            scheduleSavedReset()
            recents = (try? await storeRecents()) ?? recents
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

    /// Returns the state to ready for the same text after the brief saved
    /// confirmation (timer-capture-experience spec).
    private func scheduleSavedReset() {
        savedResetTask?.cancel()
        savedResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            guard let self, case let .saved(draft, _) = self.state else { return }
            self.state = .ready(draft)
            self.elapsed = 0
        }
    }
}

#if DEBUG
extension TrackViewModel {
    static func preview(
        state: TrackState = .idle,
        recents: [RecentEntry] = [],
        categories: [String: Category] = [:],
        nameDraft: String = ""
    ) -> TrackViewModel {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("preview.sqlite")
        let store: LocalStore
        do {
            store = try LocalStore(url: url, userID: "preview-user")
        } catch {
            fatalError("Unable to create preview store: \(error)")
        }
        let vm = TrackViewModel(
            service: TimerService(store: store),
            connectivity: MockConnectivity(connected: true)
        )
        vm.state = state
        vm.recents = recents
        vm.categories = categories
        vm.nameDraft = nameDraft
        return vm
    }
}
#endif
