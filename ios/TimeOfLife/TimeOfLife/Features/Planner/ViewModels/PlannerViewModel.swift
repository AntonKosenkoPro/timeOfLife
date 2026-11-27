// swiftlint:disable file_length
// (hosts the serialized reload, composer, checklist, undo, Start, and
// gate-preload paths; splitting the VM is future work, not this change.)
import Foundation
import Combine
import SwiftUI

/// One chip tap's staged write (day-planner 16.2): the tapped Recent's exact
/// text plus its full ordered category set. The line shows only this chip
/// while the composer still reads its text; the next submit creates the
/// task with the set.
struct StagedChip: Equatable, Sendable {
    /// The tapped Recent's exact text (selected-only display while the
    /// draft still reads it).
    var text: String
    /// The tapped Recent's full ordered category set (submit-carry).
    var categoryIDs: [String]
}

/// The three planner haptic moments (day-planner 17.3/18.1/18.4, HIG
/// playing-haptics): success when a valid submit completes (an action
/// completed), selection when a chip tap changes the staged selection,
/// reject when a disabled control is tapped instead of acting (the error
/// haptic is the non-motion channel — it fires even under Reduce Motion).
enum PlannerHaptic: Equatable, Sendable {
    case success
    case selection
    case reject
}

    /// The Today projection view model (day-planner spec): an inline composer over
/// a reorderable checklist projected from one ordered backlog, with a task
/// editor sheet for renaming and tagging. Today is the
/// only view — unfinished tasks plus completions on the viewing device's
/// current local civil date, in the shared `(positionKey, id)` order, with
/// done/total counts from the same snapshot.
///
/// Reloads serialize like Track (`loadIfNeeded` + `invalidate`): tab-return,
/// foreground return, and sync-cycle exit all funnel through the guarded
/// load, and no-op reloads publish nothing. The composer draft survives
/// every reload; an invalid or failed submission never adds a row and
/// never discards the draft.
@MainActor
final class PlannerViewModel: ObservableObject {
    /// The current Today projection. Empty until the first load settles.
    @Published private(set) var snapshot = PlannerToday.Snapshot(tasks: [], done: 0, total: 0)
    /// The inline composer draft. Survives reloads; cleared only by a
    /// successful submission. Clearing the draft also clears any staged
    /// chip set (day-planner 16.2).
    @Published var draft = "" {
        didSet {
            if draft.isEmpty {
                stagedChip = nil
            }
        }
    }
    /// The chip-tapped Recent whose line and set are staged (day-planner
    /// 16.2): the tapped exact text (the chips line shows only this chip
    /// while the draft still reads it) plus the Recent's full ordered
    /// category set (carried by the next submit). Staged by tap; cleared by
    /// draft clear or another tap; typing neither stages nor clears — the
    /// line filters again but the set survives until clear or retap.
    @Published private(set) var stagedChip: StagedChip?
    /// The task open in the editor sheet, or nil when the sheet is closed.
    @Published var editingTask: PlannerTask?
    /// The editor sheet's name draft, prefilled from the task.
    @Published var sheetName = ""
    /// The editor sheet's ordered category selection, prefilled from the task.
    @Published var sheetCategoryIDs: [String] = []
    /// The editor sheet's notes draft, prefilled from the task. Optional —
    /// empty when the task carries no notes. The 2000-trimmed-rune relay
    /// bound gates Save (the pushed `NotesEditorPage` also enforces it).
    @Published var sheetNotes = ""
    /// The category catalog backing the sheet's TagSelector.
    @Published var availableCategories: [Category] = []
    /// Every committed entry text for the sheet's shared name picker
    /// (manual-entry parity, day-planner 16.3): newest-first, uncapped —
    /// the picker suggests everything ever used, like the Log Time form.
    /// Settable so tests can seed names directly instead of driving them
    /// through async store paths (LogTimeViewModel.nameRecents precedent).
    @Published var sheetNameRecents: [ExactName] = []
    /// Whether a timer run is active (planner stays usable, but no task
    /// can start another run while one is active).
    @Published private(set) var timerActive = false
    /// The linked task id of the active run, if any (the `In progress` row
    /// reads it; nil for ordinary runs and when idle).
    @Published private(set) var linkedTaskID: String?
    /// The active run's entry name (day-planner 18.4): backs the Today
    /// nav-bar `<name> is in progress now` subheader while the run is NOT
    /// planner-linked. Nil when idle, when the draft has no name, and on
    /// the linked path (the linked run's indicator is the row's
    /// `In progress` label, never this).
    @Published private(set) var runningName: String?
    /// The category catalog backing row icons, keyed by id.
    @Published private(set) var categoryByID: [String: Category] = [:]
    /// Non-field recoverable error (persistence failures).
    @Published var errorMessage: String?
    /// Undo failure surface (mirrors the entry/category undo contract).
    @Published var undoError: String?

    private let store: LocalStore
    private let undoBuffer: UndoBufferStore
    private let timer: TimerService
    /// Haptic sink (day-planner 17.3): success on valid submit, selection
    /// on chip tap. Production maps to the shared `Haptics` wrapper;
    /// tests inject a recorder (generators never fire headless, so the
    /// wiring is verified through this seam).
    private let playHaptic: (PlannerHaptic) -> Void
    /// Notification surface for the linked-stop commit reload (day-planner
    /// 14.2). Production uses `.default`; tests inject a private center so
    /// global posts from parallel suites cannot reload this VM out from
    /// under stale-snapshot assertions (History precedent).
    private let notifications: NotificationCenter
    /// The UndoManager the current registration belongs to, held weakly so
    /// a dismissed surface never keeps it alive (entry/category precedent).
    private weak var registeredUndoManager: UndoManager?

    private var tasks: [PlannerTask] = []
    private var recents: [RecentEntry] = []
    private var todayString: String = PlannerCivilDate.today()
    private var inFlightLoad: Task<Void, Never>?
    private var needsReload = true
    /// The id of a just-submitted task whose insertion the next `load()`
    /// animates (day-planner 12.2: the fresh row expands in at the top).
    /// Consumed by the first load after the submit; every other load
    /// publishes without animation.
    private var pendingInsertionID: String?

    init(store: LocalStore, undoBuffer: UndoBufferStore, timer: TimerService, notifications: NotificationCenter = .default, playHaptic: ((PlannerHaptic) -> Void)? = nil) {
        self.store = store
        self.undoBuffer = undoBuffer
        self.timer = timer
        self.notifications = notifications
        self.playHaptic = playHaptic ?? { event in
            switch event {
            case .success: Haptics.success()
            case .selection: Haptics.selection()
            case .reject: Haptics.error()
            }
        }
        observeLinkedStop()
        observeTaskConvergence()
    }

    // MARK: - Loading (serialized, Track precedent)

    /// Reloads only when stale or never loaded. Re-entrancy safe: concurrent
    /// callers join the in-flight load instead of forking another.
    func loadIfNeeded() async {
        if let inFlightLoad {
            await inFlightLoad.value
        }
        guard needsReload else { return }
        needsReload = false
        let task = Task<Void, Never> { await load() }
        inFlightLoad = task
        await task.value
        inFlightLoad = nil
    }

    /// Marks the snapshot stale (tab-return, foreground return, sync exit,
    /// undo, a linked Stop, or a mutation that bypasses this view model).
    func invalidate() {
        needsReload = true
    }

    /// Event-driven reload for linked Stops (day-planner 14.2): the Stop
    /// path completes the task behind this view model, so the posted commit
    /// invalidates the stale projection and the guarded load republishes
    /// the new counts. Subscribed here — not in the view — so the real
    /// notification path is unit-testable (History precedent).
    private var linkedStopCancellables = Set<AnyCancellable>()

    /// Event-driven reload for Track-side convergence (day-planner 16.4):
    /// a Track retag or notes save converged the linked task behind this
    /// view model, so the posted event invalidates the stale projection and
    /// the guarded load republishes the converged set with no navigation.
    private var taskConvergedCancellables = Set<AnyCancellable>()

    private func observeLinkedStop() {
        notifications.publisher(for: .plannerLinkedStopCommitted)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.invalidate()
                    await self?.loadIfNeeded()
                }
            }
            .store(in: &linkedStopCancellables)
    }

    /// Subscribes the task-converged reload (day-planner 16.4): the
    /// Track-side retag/notes path converged the linked task behind this
    /// view model, so the posted event invalidates the stale projection and
    /// the guarded load republishes the converged task in place.
    /// Subscribed here — not in the view — so the path is unit-testable
    /// (linked-stop precedent).
    private func observeTaskConvergence() {
        notifications.publisher(for: .plannerTaskConverged)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.invalidate()
                    await self?.loadIfNeeded()
                }
            }
            .store(in: &taskConvergedCancellables)
    }

    /// The unguarded worker: one snapshot query batch whose results publish
    /// in a single commit, skipping the publish when nothing changed.
    func load() async {
        do {
            todayString = PlannerCivilDate.today()
            let fetched = try await store.plannerTasks()
            let fetchedRecents = try await store.recents(limit: Self.chipPoolLimit)
            let fetchedCategories = try await store.categories()
            let draft = try await store.timerDraft()
            let projected = PlannerToday.project(tasks: fetched, on: todayString)
            tasks = fetched
            recents = fetchedRecents
            timerActive = draft != nil
            linkedTaskID = draft?.plannerTaskID
            runningName = draft?.plannerTaskID == nil ? draft?.activityText : nil
            categoryByID = Dictionary(uniqueKeysWithValues: fetchedCategories.map { ($0.id, $0) })
            availableCategories = fetchedCategories
            // A submit-then-load round-trip animates only the fresh row's
            // insertion (its `.transition` fires); every other load — tab
            // return, sync exit, toggle, move, delete — publishes silently.
            let insertedID = pendingInsertionID.flatMap { id in
                projected.tasks.contains { $0.id == id } ? id : nil
            }
            pendingInsertionID = nil
            if projected != snapshot {
                if insertedID != nil {
                    withAnimation(.default) { snapshot = projected }
                } else {
                    snapshot = projected
                }
            }
        } catch {
            if DatabaseSuspension.isSuspensionError(error) {
                needsReload = true
                return
            }
            errorMessage = L10n.text(in: .default, code: "error.unknown")
        }
    }

    // MARK: - Launch-gate preload (timer-capture-experience 12.3)

    /// Resolves everything `load()` reads in one batch for the launch gate
    /// (`RootView.beginSignIn`, steady-track-launch precedent): with warm
    /// local data the shell mounts with actual Today counts instead of
    /// painting 0/0 until the first tab-return, foreground return, or
    /// sync-cycle exit reloads. Throws on an unbound store like `load()`.
    static func preload(store: LocalStore) async throws -> PlannerToday.Preloaded {
        let today = PlannerCivilDate.today()
        let tasks = try await store.plannerTasks()
        let draft = try await store.timerDraft()
        return PlannerToday.Preloaded(
            today: today,
            tasks: tasks,
            recents: try await store.recents(limit: chipPoolLimit),
            timerActive: draft != nil,
            linkedTaskID: draft?.plannerTaskID,
            runningName: draft?.plannerTaskID == nil ? draft?.activityText : nil,
            categories: try await store.categories(),
            snapshot: PlannerToday.project(tasks: tasks, on: today)
        )
    }

    /// Adopts a gate-preloaded bundle without re-querying: synchronous
    /// single-commit assignments identical to `load()`'s, so a shell
    /// mounted with it paints actual counts on its first commit. The
    /// appear-time `loadIfNeeded` below would only re-resolve the identical
    /// snapshot (a no-op publish), so the queries are skipped outright.
    /// A later `invalidate()` reloads normally — tab-return, sync-exit,
    /// and Today edits are unaffected.
    func adopt(_ preloaded: PlannerToday.Preloaded) {
        todayString = preloaded.today
        tasks = preloaded.tasks
        recents = preloaded.recents
        timerActive = preloaded.timerActive
        linkedTaskID = preloaded.linkedTaskID
        runningName = preloaded.runningName
        categoryByID = Dictionary(uniqueKeysWithValues: preloaded.categories.map { ($0.id, $0) })
        availableCategories = preloaded.categories
        snapshot = preloaded.snapshot
        needsReload = false
    }

    /// The Today nav-bar subtitle while a NON-planner timer runs
    /// (day-planner 18.4): `<name> is in progress now`. Nil when idle,
    /// when the draft carries no name, and when the run is planner-linked
    /// (the linked run's indicator is the row's `In progress` label).
    /// Pinned here — SwiftUI rendering is not unit-testable (the
    /// `PlannerStartSlot` precedent).
    var outsideRunSubtitle: String? {
        guard timerActive, linkedTaskID == nil else { return nil }
        guard let name = runningName, !name.isEmpty else { return nil }
        return String(format: L10n.plannerOutsideRun.text, locale: .current, name)
    }

    /// Whether a Start tap must reject instead of starting (day-planner
    /// 18.4): a run is active and the task is open. Completed rows never
    /// fire (their slot stays disabled and hidden) and the running row
    /// shows no Start at all, so the view only consults this for a visible
    /// Start under an active run. Pinned here — same precedent.
    func startShouldReject(_ task: PlannerTask) -> Bool {
        timerActive && task.completedOn == nil
    }

    /// Feedback for a rejected Start tap (day-planner 18.4): plays the
    /// reject haptic through the injected seam (test double; the generator
    /// never fires headless). Starts nothing — the caller must not call
    /// `startTask` on this path. The caller shakes the nav-bar subheader
    /// (suppressed under Reduce Motion — the haptic is the non-motion
    /// channel there).
    func rejectDisabledStart() {
        playHaptic(.reject)
    }

    /// Ordered categories for a task row (day-planner 15.4): the task's
    /// ordered id set resolved against the loaded catalog; unknown ids
    /// drop (the same prune rule as Stop).
    func rowCategories(for task: PlannerTask) -> [Category] {
        task.categoryIDs.compactMap { categoryByID[$0] }
    }

    // MARK: - Composer (fast repeated input)

    /// Chip pool size: the capped newest-first Recents drawn from
    /// committed entries. Display is bounded separately (a single chips
    /// line between the composer and the keyboard showing at most
    /// `chipDisplayCap` chips).
    private static let chipPoolLimit = 10
    /// Maximum chips rendered: one horizontally scrollable line between
    /// the composer and the keyboard, so keystrokes only swap chips inside
    /// that fixed-height line and the list above never moves.
    static let chipDisplayCap = 5

    /// Matching chips for the current draft, newest-first: the full capped
    /// strip for an empty draft, case-insensitive prefix matches over exact
    /// entry texts while typing. Tapping a chip only fills the composer.
    /// After a tap the line shows ONLY the selected chip while the draft
    /// still reads its exact text (day-planner 16.2); typing anything else
    /// filters again — the staged set survives, only the display narrows.
    var chips: [RecentEntry] {
        if let selected = selectedRecent { return [selected] }
        let trimmed = ActivityName.normalized(draft)
        guard !trimmed.isEmpty else { return Array(recents.prefix(Self.chipDisplayCap)) }
        let lowered = trimmed.lowercased()
        return Array(recents
            .filter { $0.activityText.lowercased().hasPrefix(lowered) }
            .prefix(Self.chipDisplayCap))
    }

    /// The single selected chip (day-planner 17.1): the tapped Recent while
    /// the draft still reads its exact text — the line's selected-only
    /// display, rendered in the filled-accent selected presentation
    /// (Track Recents parity). Nil while merely filtering, after typing
    /// resumes, or when the draft clears.
    private var selectedRecent: RecentEntry? {
        guard let staged = stagedChip, draft == staged.text else { return nil }
        return recents.first { $0.id == staged.text }
    }

    /// Whether a chip renders in the selected presentation (day-planner
    /// 17.1): true only for the isolated staged chip above — the helper
    /// `PlannerView` consumes, pinned here because SwiftUI rendering is
    /// not unit-testable (the `PlannerStartSlot` precedent).
    func isSelectedChip(_ recent: RecentEntry) -> Bool {
        selectedRecent?.id == recent.id
    }

    /// Fills the composer with a chip's exact text for editing or
    /// submission and stages the Recent's full ordered category set for the
    /// created task (day-planner 16.2). Creates no task, starts no timer.
    /// Replaces any previously staged set; the set survives typing and
    /// clears only when the draft clears or another chip is tapped.
    /// Tapping plays the selection haptic (day-planner 17.3 — a selection
    /// changed).
    func fillFromChip(_ recent: RecentEntry) {
        draft = recent.activityText
        stagedChip = StagedChip(text: recent.activityText, categoryIDs: recent.categoryIDs)
        playHaptic(.selection)
    }

    /// Validated SF Symbol for a chip's leading icon (day-planner 16.2):
    /// the Recent's first category's symbol, or nil when the Recent carries
    /// none or the id left the catalog — the chip then renders text-only
    /// (the pre-16.2 capsule, unchanged).
    func chipIconSymbol(for recent: RecentEntry) -> String? {
        guard let first = recent.categoryIDs.first, let category = categoryByID[first] else { return nil }
        return CatalogIcon(validated: category.icon).displaySymbol
    }

    /// Whether the chips line shows the no-match placeholder (day-planner
    /// 11.3): a non-blank draft that filters the Recent pool to nothing.
    /// An empty or whitespace-only draft shows the full capped strip
    /// instead — never this.
    var showsChipsNoMatch: Bool {
        !ActivityName.normalized(draft).isEmpty && chips.isEmpty
    }

    /// Submits the composer (Return or the accessible Add affordance):
    /// prepends one task before the existing Today rows, clears the draft,
    /// and reloads. The task carries the chip-staged category set when a
    /// chip tap staged one (day-planner 16.2), or no categories otherwise
    /// (the sheet tags them afterwards; Start falls back to Recents). The
    /// field never resigns across this round-trip: the UIKit-backed composer
    /// suppresses the Return default resign at dispatch, so no refocusing is
    /// needed afterwards. An invalid or failed submission prepends nothing
    /// and keeps the draft (and any staged set).
    func submit() async {
        let trimmed = ActivityName.normalized(draft)
        guard case .valid = ActivityName.validate(trimmed) else { return }
        let staged = stagedChip?.categoryIDs ?? []
        let visible = snapshot.tasks
        let first = visible.first?.positionKey
        guard let key = PlannerPositionKey.allocate(before: nil, after: first) else {
            errorMessage = L10n.text(in: .default, code: "error.unknown")
            return
        }
        do {
            let id = await store.newRecordID()
            let outcome = try await store.createPlannerTask(
                id: id,
                name: trimmed,
                positionKey: key,
                operationID: await store.newRecordID(),
                categoryIDs: staged
            )
            guard case .saved = outcome else {
                errorMessage = L10n.text(in: .default, code: "error.unknown")
                return
            }
            // A valid submit completed (day-planner 17.3): the success
            // haptic fires only on the saved path — invalid drafts return
            // above, failures report an error with the draft intact.
            playHaptic(.success)
            draft = ""
            pendingInsertionID = id
            invalidate()
            await loadIfNeeded()
        } catch {
            errorMessage = L10n.text(in: .default, code: "error.unknown")
        }
    }

    // MARK: - Checklist edits

    /// Toggles a task's completion for today (completing keeps its
    /// position; reopening keeps it too). Never starts, stops, creates, or
    /// modifies a timer or time entry.
    func toggleComplete(_ task: PlannerTask) async {
        do {
            if task.completedOn == nil {
                _ = try await store.completePlannerTask(
                    id: task.id,
                    completedOn: PlannerCivilDate.today(),
                    operationID: await store.newRecordID()
                )
                // Completing a task completed an action (day-planner 18.1,
                // HIG playing-haptics) — reopening stays silent.
                playHaptic(.success)
            } else {
                _ = try await store.reopenPlannerTask(
                    id: task.id,
                    operationID: await store.newRecordID()
                )
            }
            invalidate()
            await loadIfNeeded()
        } catch {
            errorMessage = L10n.text(in: .default, code: "error.unknown")
        }
    }

    // MARK: - Task editor sheet

    /// Opens the editor sheet for a task, prefilling the name, ordered
    /// category, and notes drafts from the snapshot copy. Tapping a row is
    /// the only entry point — there is no inline renaming. Completed tasks
    /// never open the editor (day-planner 17.2): a completed tap is a
    /// no-op, editing resumes only after reopening. Starts a fresh
    /// error scope: a banner from an earlier surface must not greet the editor.
    func beginEdit(_ task: PlannerTask) {
        guard task.completedOn == nil else { return }
        errorMessage = nil
        editingTask = task
        sheetName = task.name
        sheetCategoryIDs = task.categoryIDs
        sheetNotes = task.notes
    }

    /// Closes the editor sheet without writing.
    func cancelEdit() {
        editingTask = nil
    }

    /// Whether the sheet's Save confirm is enabled (Log Time validity-gate
    /// grammar): the trimmed name must satisfy the shared timer-name rule.
    /// Categories are optional — the set may be empty; notes are optional
    /// but bound to the shared 2000-trimmed-rune relay limit (the pushed
    /// editor page enforces the same bound per keystroke).
    var isSheetSaveEnabled: Bool {
        guard editingTask != nil else { return false }
        guard case .valid = ActivityName.validate(ActivityName.normalized(sheetName)) else { return false }
        return !NotesCounter.isOverLimit(sheetNotes)
    }

    /// Saves the editor sheet: the name, ordered set, and notes each travel
    /// as their own field intent when changed (`rename`, `retag`, `notes`),
    /// so a name-only edit sends no tags and a notes-only edit sends no
    /// name. When the task carries the active linked run, the running
    /// draft's live categories and notes converge in the same chokepoint
    /// transaction (the locked name never moves). Position, completion, and
    /// every timer/entry stay untouched.
    /// An invalid name, over-limit notes, or a failed write keeps the sheet
    /// open with the draft intact (Log Time save-failure grammar). Returns
    /// whether the sheet closed.
    func saveSheet() async -> Bool {
        guard let task = editingTask else { return false }
        let trimmed = ActivityName.normalized(sheetName)
        guard case .valid = ActivityName.validate(trimmed) else { return false }
        guard !NotesCounter.isOverLimit(sheetNotes) else { return false }
        do {
            let outcome = try await store.savePlannerTaskSheet(
                id: task.id,
                write: PlannerSheetWrite(
                    name: trimmed,
                    categoryIDs: sheetCategoryIDs,
                    notes: sheetNotes,
                    renameOperationID: await store.newRecordID(),
                    retagOperationID: await store.newRecordID(),
                    notesOperationID: await store.newRecordID()
                )
            )
            guard case .saved = outcome else {
                errorMessage = L10n.text(in: .default, code: "error.unknown")
                return false
            }
            // A save on the running task converged its draft in the same
            // transaction (day-planner 15.2) — re-mirror the Live Activity
            // chips from the new set (mid-run retag refreshes chips in
            // place) and tell Track to reload, converging its in-memory
            // snapshot (tags, notes editor baseline) with no navigation.
            // The ticker and the locked name are untouched.
            if let draft = try await store.timerDraft(),
               draft.plannerTaskID == task.id {
                if let startedAt = draft.startedAt {
                    await timer.refreshLiveActivity(
                        text: draft.activityText,
                        categoryIDs: draft.categoryIDs,
                        startedAt: startedAt
                    )
                }
                notifications.post(name: .plannerDraftConverged, object: nil)
            }
            editingTask = nil
            errorMessage = nil
            invalidate()
            await loadIfNeeded()
            return true
        } catch {
            errorMessage = L10n.text(in: .default, code: "error.unknown")
            return false
        }
    }

    /// Whether the sheet edits the running linked task (day-planner 18.1):
    /// the sheet shows the `In progress` subheader and its bottom delete
    /// is disabled — a disabled-tap shakes the subheader and plays the
    /// reject haptic instead of deleting. False when the sheet is closed,
    /// when idle, and when the sheet edits any other task.
    var isEditingRunningTask: Bool {
        guard let editing = editingTask else { return false }
        guard let linked = linkedTaskID else { return false }
        return editing.id == linked
    }

    /// Deletes the sheet's task into the durable undo buffer and closes the
    /// sheet (day-planner 18.1) — the normal path: the row vanishes with no
    /// outbox row yet, restorable through the system Undo confirmation
    /// (`delete(at:)` precedent). Reloads the snapshot on success. Returns
    /// whether the sheet closed. When the sheet edits the running task the
    /// delete is disabled: plays the reject haptic through the injected
    /// seam, deletes nothing, and returns false with the sheet open — the
    /// caller shakes the subheader instead (suppressed under Reduce
    /// Motion; the haptic is the non-motion channel there).
    func attemptDeleteEditingTask() async -> Bool {
        guard let editing = editingTask else { return false }
        guard !isEditingRunningTask else {
            playHaptic(.reject)
            return false
        }
        do {
            _ = try await store.deletePlannerTaskUndoable(id: editing.id)
            editingTask = nil
            errorMessage = nil
            invalidate()
            await loadIfNeeded()
            return true
        } catch {
            errorMessage = L10n.text(in: .default, code: "error.unknown")
            return false
        }
    }

    /// Loads the category catalog for the sheet's TagSelector (idempotent;
    /// LogTimeViewModel precedent). Called on sheet open by the view.
    func loadSheetCategoriesIfNeeded() async {
        guard availableCategories.isEmpty else { return }
        availableCategories = (try? await store.categories()) ?? []
    }

    /// Loads every committed entry text for the sheet's shared name picker
    /// (idempotent; LogTimeViewModel.loadNameRecentsIfNeeded parity,
    /// day-planner 16.3). A failure leaves suggestions empty — it never
    /// blocks the sheet. Called on sheet open by the view alongside the
    /// catalog load.
    func loadSheetNameRecentsIfNeeded() async {
        guard sheetNameRecents.isEmpty else { return }
        sheetNameRecents = (try? await store.allActivityNames().map(ExactName.init(storeRecent:))) ?? []
    }

    /// Fills the sheet name draft from a picker suggestion (the Recents tap
    /// contract, LogTimeViewModel.applySuggestion parity): exact text plus
    /// that entry's full ordered categories. Draft-only — no committed
    /// entry is touched and validation/save behavior is unchanged.
    func applySheetSuggestion(text: String, categoryIDs: [String]) {
        sheetName = text
        sheetCategoryIDs = categoryIDs
    }

    /// Completes the sheet picker with typed text (LogTimeViewModel
    /// parity): an exact-recent match inherits that entry's ordered
    /// categories (the Recents-tap contract); any other non-empty text keeps
    /// the caller's current categories (e.g. chosen in the TagSelector).
    /// Empty input is a no-op — Back remains the exit. Draft-only, like
    /// `applySheetSuggestion`.
    func completeSheetTypedName(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let match = sheetNameRecents.first(where: { $0.text == trimmed }) {
            applySheetSuggestion(text: match.text, categoryIDs: match.categoryIDs)
        } else {
            sheetName = trimmed
        }
    }

    /// Toggles a category on the sheet's ordered selection (TagSelector
    /// parent owns order: toggling appends or removes, keeping the
    /// selection order).
    func toggleSheetCategory(_ categoryID: String) {
        if let index = sheetCategoryIDs.firstIndex(of: categoryID) {
            sheetCategoryIDs.remove(at: index)
        } else {
            sheetCategoryIDs.append(categoryID)
        }
    }

    /// Attaches a freshly created category to the sheet draft and reloads
    /// the options (LogTimeViewModel precedent: draft-only until save).
    func attachSheetCategory(_ category: Category) async {
        if !sheetCategoryIDs.contains(category.id) {
            sheetCategoryIDs.append(category.id)
        }
        if let fresh = try? await store.categories() {
            availableCategories = fresh
        } else if !availableCategories.contains(where: { $0.id == category.id }) {
            availableCategories.append(category)
        }
    }

    /// Moves a task within the visible Today order (List `onMove` in visible
    /// coordinates): allocates a key between the new visible neighbors so
    /// no other row is rewritten. Hidden (other-day-completed) rows keep
    /// their keys; a shared-key tie with a hidden row resolves by id and
    /// never disturbs the visible position.
    func move(from source: IndexSet, to destination: Int) async {
        // Single-row moves reallocate between the new visible neighbors;
        // multi-row moves reload unchanged (no partial rewrite).
        guard source.count == 1 else {
            invalidate()
            await loadIfNeeded()
            return
        }
        var revised = snapshot.tasks
        revised.move(fromOffsets: source, toOffset: destination)
        guard let movedID = source.first.map({ snapshot.tasks[$0].id }),
              let newIndex = revised.firstIndex(where: { $0.id == movedID })
        else { return }
        let before = newIndex > 0 ? revised[newIndex - 1].positionKey : nil
        let after = newIndex + 1 < revised.count ? revised[newIndex + 1].positionKey : nil
        guard let key = PlannerPositionKey.allocate(before: before, after: after),
              key != snapshot.tasks.first(where: { $0.id == movedID })?.positionKey
        else { return }
        do {
            _ = try await store.movePlannerTask(
                id: movedID,
                positionKey: key,
                operationID: await store.newRecordID()
            )
            invalidate()
            await loadIfNeeded()
        } catch {
            errorMessage = L10n.text(in: .default, code: "error.unknown")
        }
    }

    /// Deletes the visible tasks (swipe-to-delete) into the durable undo
    /// buffer: the rows vanish with no outbox row yet, restorable until
    /// restart or a successful push through the DEFAULT system Undo
    /// confirmation (entry/category precedent). The running linked task is
    /// never deletable (day-planner 17.2): its offsets are skipped, so a
    /// delete-all gesture leaves exactly it behind. Reloads even when every
    /// deletion reports missing (a sync may have removed the row first).
    func delete(at offsets: IndexSet) async {
        for index in offsets {
            guard snapshot.tasks.indices.contains(index) else { continue }
            guard snapshot.tasks[index].id != linkedTaskID else { continue }
            do {
                _ = try await store.deletePlannerTaskUndoable(id: snapshot.tasks[index].id)
            } catch {
                errorMessage = L10n.text(in: .default, code: "error.unknown")
                return
            }
        }
        invalidate()
        await loadIfNeeded()
    }

    // MARK: - System shake-to-undo (entry/category precedent)

    /// Registers the newest restorable planner deletion with the system Undo
    /// manager, so shaking surfaces the DEFAULT Undo confirmation and
    /// confirming restores exactly the most recent buffered planner task.
    /// Offers nothing when the buffer holds no planner deletion — including
    /// when the newest row belongs to another surface (U7 supersession).
    func registerSystemUndo(with undoManager: UndoManager?) async {
        guard let undoManager else { return }
        registeredUndoManager = undoManager
        undoManager.removeAllActions(withTarget: self)
        guard let recent = try? await undoBuffer.mostRecent(),
              (try? await store.plannerTaskDeletionSnapshot(bufferID: recent.id)) != nil else { return }
        undoManager.registerUndo(withTarget: self) { target in
            Task { @MainActor in
                await target.performUndo()
                await target.registerSystemUndo(with: target.registeredUndoManager)
            }
        }
        undoManager.setActionName(L10n.entryDeleteConfirm.text)
    }

    /// Undoes the most recent planner deletion: restores the task at its
    /// existing position and rebuilds the snapshot. Only planner deletions
    /// are restored here — buffer rows owned by other surfaces are left
    /// for their owners. Nothing is synced.
    func performUndo() async {
        do {
            guard let recent = try await undoBuffer.mostRecent() else { return }
            guard try await store.plannerTaskDeletionSnapshot(bufferID: recent.id) != nil else { return }
            if try await store.undoPlannerTaskDeletion(bufferID: recent.id) != nil {
                undoError = nil
                invalidate()
                await loadIfNeeded()
            }
        } catch {
            undoError = L10n.errorLocalPersistence.text
        }
    }

    /// Clears the undo error, e.g. when the user dismisses the undo-error
    /// dialog. The view cannot nil it directly (`private(set)`).
    func clearUndoError() {
        undoError = nil
    }

    // MARK: - One-tap Start (day-planner D4)

    /// Starts an open task in one tap when no timer is active: a task
    /// holding categories starts with exactly those (sheet-assigned); a
    /// task without categories falls back to the ordinary
    /// exact-text category inheritance (the newest committed entry with
    /// that exact text lends its ordered categories). The task's notes ride
    /// the draft too (day-planner §15). The task's id rides
    /// the draft so Stop completes exactly it. Returns false (staying
    /// usable, starting nothing) when a run is active, saving, or awaiting
    /// a Stop retry — a second Start never replaces a pending or active run
    /// at the store boundary. A task rename never changes the locked timer
    /// name: the name is copied at Start.
    func startTask(_ task: PlannerTask) async -> Bool {
        guard task.completedOn == nil else { return false }
        do {
            if try await store.timerDraft() != nil { return false }
            let inherited = task.categoryIDs.isEmpty
                ? recents.first { $0.activityText == task.name }?.categoryIDs ?? []
                : task.categoryIDs
            return try await timer.startLinkedTask(
                name: task.name,
                categoryIDs: inherited,
                notes: task.notes,
                taskID: task.id,
                startedAt: Date()
            )
        } catch {
            errorMessage = L10n.text(in: .default, code: "error.unknown")
            return false
        }
    }
}
