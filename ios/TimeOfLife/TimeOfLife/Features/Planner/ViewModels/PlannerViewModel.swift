// swiftlint:disable file_length
// (hosts the serialized reload, composer, checklist, undo, Start, and
// gate-preload paths; splitting the VM is future work, not this change.)
import Foundation
import Combine
import SwiftUI

/// The Today planner view model (day-planner spec): an inline composer over
/// a reorderable checklist projected from one ordered backlog. Today is the
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
    /// The inline rename draft, bound to the row being renamed.
    @Published var editText = ""
    /// The task currently renamed inline, or nil.
    @Published var editingTaskID: String?
    /// Whether a timer run is active (planner stays usable, but no task
    /// can start another run while one is active).
    @Published private(set) var timerActive = false
    /// Non-field recoverable error (persistence failures).
    @Published var errorMessage: String?
    /// Undo failure surface (mirrors the entry/category undo contract).
    @Published var undoError: String?

    private let store: LocalStore
    private let undoBuffer: UndoBufferStore
    private let timer: TimerService
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

    init(store: LocalStore, undoBuffer: UndoBufferStore, timer: TimerService) {
        self.store = store
        self.undoBuffer = undoBuffer
        self.timer = timer
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
    /// undo, or a mutation that bypasses this view model).
    func invalidate() {
        needsReload = true
    }

    /// The unguarded worker: one snapshot query batch whose results publish
    /// in a single commit, skipping the publish when nothing changed.
    func load() async {
        do {
            todayString = PlannerCivilDate.today()
            let fetched = try await store.plannerTasks()
            let fetchedRecents = try await store.recents(limit: Self.chipPoolLimit)
            let draftExists = try await store.timerDraft() != nil
            let projected = PlannerToday.project(tasks: fetched, on: todayString)
            tasks = fetched
            recents = fetchedRecents
            timerActive = draftExists
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
            if editingTaskID != nil, !projected.tasks.contains(where: { $0.id == editingTaskID }) {
                editingTaskID = nil
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
        return PlannerToday.Preloaded(
            today: today,
            tasks: tasks,
            recents: try await store.recents(limit: chipPoolLimit),
            timerActive: try await store.timerDraft() != nil,
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
        snapshot = preloaded.snapshot
        needsReload = false
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

    /// Begins an inline rename, prefilled with the task's exact name.
    func beginRename(_ task: PlannerTask) {
        editingTaskID = task.id
        editText = task.name
    }

    /// Cancels an inline rename without writing.
    func cancelRename() {
        editingTaskID = nil
    }

    /// Commits an inline rename (Return). An empty result reverts to the
    /// stored name with no write; anything else renames in place.
    func commitRename(_ task: PlannerTask) async {
        defer { editingTaskID = nil }
        let trimmed = ActivityName.normalized(editText)
        guard !trimmed.isEmpty, trimmed != task.name else { return }
        guard case .valid = ActivityName.validate(trimmed) else { return }
        do {
            _ = try await store.renamePlannerTask(
                id: task.id,
                name: trimmed,
                operationID: await store.newRecordID()
            )
            invalidate()
            await loadIfNeeded()
        } catch {
            errorMessage = L10n.text(in: .default, code: "error.unknown")
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

    /// Starts an open task in one tap when no timer is active: the exact
    /// text goes through the ordinary category-inheritance rule (the newest
    /// committed entry with that exact text lends its ordered categories),
    /// and the task's id rides the draft so Stop completes exactly it.
    /// Returns false (staying usable, starting nothing) when a run is
    /// active, saving, or awaiting a Stop retry — a second Start never
    /// replaces a pending or active run at the store boundary. A task rename
    /// never changes the locked timer name: the name is copied at Start.
    func startTask(_ task: PlannerTask) async -> Bool {
        guard task.completedOn == nil else { return false }
        do {
            if try await store.timerDraft() != nil { return false }
            let inherited = recents.first { $0.activityText == task.name }?.categoryIDs ?? []
            return try await timer.startLinkedTask(
                name: task.name,
                categoryIDs: inherited,
                taskID: task.id,
                startedAt: Date()
            )
        } catch {
            errorMessage = L10n.text(in: .default, code: "error.unknown")
            return false
        }
    }
}
