// swiftlint:disable file_length
// (hosts the serialized reload, composer, checklist, undo, Start, and
// gate-preload paths; splitting the VM is future work, not this change.)
import Foundation
import Combine
import SwiftUI

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
    /// successful submission.
    @Published var draft = ""
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
    /// Whether a timer run is active (planner stays usable, but no task
    /// can start another run while one is active).
    @Published private(set) var timerActive = false
    /// The linked task id of the active run, if any (the `In progress` row
    /// reads it; nil for ordinary runs and when idle).
    @Published private(set) var linkedTaskID: String?
    /// The category catalog backing row icons, keyed by id.
    @Published private(set) var categoryByID: [String: Category] = [:]
    /// Non-field recoverable error (persistence failures).
    @Published var errorMessage: String?
    /// Undo failure surface (mirrors the entry/category undo contract).
    @Published var undoError: String?

    private let store: LocalStore
    private let undoBuffer: UndoBufferStore
    private let timer: TimerService
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

    init(store: LocalStore, undoBuffer: UndoBufferStore, timer: TimerService, notifications: NotificationCenter = .default) {
        self.store = store
        self.undoBuffer = undoBuffer
        self.timer = timer
        self.notifications = notifications
        observeLinkedStop()
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
        categoryByID = Dictionary(uniqueKeysWithValues: preloaded.categories.map { ($0.id, $0) })
        availableCategories = preloaded.categories
        snapshot = preloaded.snapshot
        needsReload = false
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
    var chips: [RecentEntry] {
        let trimmed = ActivityName.normalized(draft)
        guard !trimmed.isEmpty else { return Array(recents.prefix(Self.chipDisplayCap)) }
        let lowered = trimmed.lowercased()
        return Array(recents
            .filter { $0.activityText.lowercased().hasPrefix(lowered) }
            .prefix(Self.chipDisplayCap))
    }

    /// Fills the composer with a chip's exact text for editing or
    /// submission. Creates no task, starts no timer.
    func fillFromChip(_ recent: RecentEntry) {
        draft = recent.activityText
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
    /// and reloads. The field never resigns across this round-trip: the
    /// UIKit-backed composer suppresses the Return default resign at
    /// dispatch, so no refocusing is needed afterwards. An invalid or failed
    /// submission prepends nothing and keeps the draft.
    func submit() async {
        let trimmed = ActivityName.normalized(draft)
        guard case .valid = ActivityName.validate(trimmed) else { return }
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
                operationID: await store.newRecordID()
            )
            guard case .saved = outcome else {
                errorMessage = L10n.text(in: .default, code: "error.unknown")
                return
            }
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
    /// the only entry point — there is no inline renaming. Starts a fresh
    /// error scope: a banner from an earlier surface must not greet the editor.
    func beginEdit(_ task: PlannerTask) {
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
            // place). The ticker and the locked name are untouched.
            if let draft = try await store.timerDraft(),
               draft.plannerTaskID == task.id,
               let startedAt = draft.startedAt {
                await timer.refreshLiveActivity(
                    text: draft.activityText,
                    categoryIDs: draft.categoryIDs,
                    startedAt: startedAt
                )
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

    /// Loads the category catalog for the sheet's TagSelector (idempotent;
    /// LogTimeViewModel precedent). Called on sheet open by the view.
    func loadSheetCategoriesIfNeeded() async {
        guard availableCategories.isEmpty else { return }
        availableCategories = (try? await store.categories()) ?? []
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
    /// confirmation (entry/category precedent). Reloads even when every
    /// deletion reports missing (a sync may have removed the row first).
    func delete(at offsets: IndexSet) async {
        for index in offsets {
            guard snapshot.tasks.indices.contains(index) else { continue }
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
