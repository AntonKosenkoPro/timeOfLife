import Combine
import Foundation

/// Lazily loaded day-planner state (day-planner spec): owns the account-local
/// checklist, the add-field draft, and serialized mutations. Created when the
/// planner sheet opens — never from the launch-gate `TrackSnapshot`, so
/// planning never delays Track's first paint.
///
/// Account fencing: the view model captures the bound account identity at
/// open (`expectedUserID`) plus a monotonically bumped `generation`. Every
/// mutation re-reads the store's bound identity immediately before executing
/// and every completion is discarded when the generation moved on (a sheet
/// surviving an account switch), so a stale operation can never read/write
/// another account's tasks or publish its rows.
@MainActor
final class PlannerViewModel: ObservableObject {
    /// The visible checklist state.
    enum Phase: Equatable {
        /// The initial load (or a retry) is in flight.
        case loading
        /// The checklist resolved; the associated value is the last durable
        /// snapshot (empty when the account has no tasks).
        case loaded
        /// The last load or mutation failed durably-side; the sheet stays
        /// open with the last good snapshot and a retry path.
        case failed
    }

    @Published private(set) var phase: Phase = .loading
    /// The last durable checklist snapshot, in stable creation order.
    @Published private(set) var tasks: [PlannerTask] = []
    /// The add field's uncommitted text. Preserved across failed Adds.
    @Published var inputText = ""
    /// The latest validation or persistence failure, if any.
    @Published private(set) var errorMessage: String?
    /// A write is in flight: all task actions disable until it settles, so
    /// duplicate taps cannot fork concurrent writes.
    @Published private(set) var isMutating = false
    /// The task awaiting confirmed removal (one destructive confirmation
    /// naming its text; cancel preserves it).
    @Published var pendingRemoval: PlannerTask?

    private let store: LocalStore
    private let calendar: Calendar
    private let nowProvider: () -> Date
    /// The account this generation is bound to (nil until opened).
    private var expectedUserID: String?
    /// Bumps on every open/account change; async completions carrying an
    /// older generation are discarded.
    private var generation = 0

    init(
        store: LocalStore,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.calendar = calendar
        self.nowProvider = now
    }

    /// Whether a task-name selection may prepare Track right now. The caller
    /// (the sheet) rechecks Track running/saving state at execution time;
    /// this gate covers the planner side: a settled load with no write in
    /// flight and a bound account.
    var canInteract: Bool {
        phase != .loading && !isMutating
    }

    /// The account this generation is bound to (nil until opened). Read by
    /// the sheet to recheck account validity at selection-execution time.
    var expectedAccountID: String? { expectedUserID }

    /// Opens (or re-opens) the checklist for the currently bound account:
    /// captures the account identity, bumps the generation, and reconciles
    /// (prunes eligible completed rows, then loads) in one durable step.
    /// Safe to call on every sheet open, foreground resume, and local-day
    /// change while open — a redundant call simply re-resolves the same
    /// snapshot. Stale completions never publish.
    func open() async {
        let bound = await store.boundUserID
        generation += 1
        let current = generation
        expectedUserID = bound
        await reconcile(generation: current)
    }

    /// Reconciles when the sheet is open and active: foreground/resume after
    /// the database resumes, local-day changes, and clock/time-zone shifts.
    /// Uses the device's current local day boundary at execution time. A
    /// suspended store keeps the last snapshot with the stale flag (failed
    /// phase + retry) instead of clearing the list or claiming success.
    func reconcileActive() async {
        generation += 1
        let current = generation
        expectedUserID = await store.boundUserID
        await reconcile(generation: current)
    }

    /// Retries the last failed load or mutation against the currently bound
    /// account.
    func retry() async {
        generation += 1
        let current = generation
        expectedUserID = await store.boundUserID
        phase = .loading
        errorMessage = nil
        await reconcile(generation: current)
    }

    /// Adds the input field's text as a new independent task. Duplicate text
    /// is allowed. On success the field clears; on failure the input is
    /// preserved with an accessible explanation and the last snapshot stays.
    func add() async {
        guard !isMutating else { return }
        let text = inputText
        let validation = ActivityName.validate(text)
        guard case .valid(let normalized) = validation else {
            switch validation {
            case .empty:
                errorMessage = L10n.plannerValidationEmpty.text
            case .tooLong:
                errorMessage = L10n.plannerValidationTooLong.text
            case .valid:
                break
            }
            return
        }
        isMutating = true
        defer { isMutating = false }
        let current = generation
        let expected = expectedUserID
        do {
            let created = try await store.addPlannerTask(text: normalized, expectedUserID: expected)
            guard current == generation else {
                // A day-change/foreground trigger landed mid-write: the write
                // is durable, so re-resolve under the new generation instead
                // of leaving the list stale.
                await reconcile(generation: generation)
                return
            }
            tasks.append(created)
            tasks.sort { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
            inputText = ""
            errorMessage = nil
            phase = .loaded
        } catch {
            guard current == generation else { return }
            errorMessage = L10n.text(in: .default, code: "error.unknown")
            if phase != .loaded { phase = .failed }
        }
    }

    /// Toggles one task's manual completion. Never reorders the list and
    /// never touches any timer or entry state.
    func toggle(_ task: PlannerTask) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        let current = generation
        let expected = expectedUserID
        do {
            let updated = try await store.setPlannerTaskCompleted(
                id: task.id,
                completed: !task.isCompleted,
                expectedUserID: expected
            )
            guard current == generation else {
                await reconcile(generation: generation)
                return
            }
            if let updated, let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index] = updated
            }
            errorMessage = nil
        } catch {
            guard current == generation else { return }
            errorMessage = L10n.text(in: .default, code: "error.unknown")
        }
    }

    /// Permanently removes one task after confirmation. No relay operation,
    /// no shared undo-buffer participation, no timer/entry change.
    func confirmRemoval(_ task: PlannerTask) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        let current = generation
        let expected = expectedUserID
        do {
            let removed = try await store.removePlannerTask(id: task.id, expectedUserID: expected)
            guard current == generation else {
                await reconcile(generation: generation)
                return
            }
            if removed {
                tasks.removeAll { $0.id == task.id }
            }
            pendingRemoval = nil
            errorMessage = nil
        } catch {
            guard current == generation else { return }
            pendingRemoval = nil
            errorMessage = L10n.text(in: .default, code: "error.unknown")
        }
    }

    /// Cancels a pending removal: the task is preserved, nothing is written.
    func cancelRemoval() {
        pendingRemoval = nil
    }

    // MARK: - Internals

    /// Prunes prior-day completed rows and loads the remainder atomically,
    /// then publishes only when the generation is still current.
    private func reconcile(generation current: Int) async {
        phase = .loading
        let expected = expectedUserID
        let cutoff = PlannerDayCutoff.startOfLocalDay(containing: nowProvider(), calendar: calendar)
        do {
            let reconciled = try await store.reconciledPlannerTasks(pruningBefore: cutoff, expectedUserID: expected)
            guard current == generation else { return }
            tasks = reconciled
            phase = .loaded
            errorMessage = nil
        } catch {
            guard current == generation else { return }
            // Suspension or account loss: keep the last snapshot (possibly
            // empty on first open) with a retry path — never publish a
            // cleared list as success.
            if tasks.isEmpty {
                phase = .failed
            } else {
                phase = .loaded
            }
            errorMessage = L10n.text(in: .default, code: "error.unknown")
        }
    }
}
