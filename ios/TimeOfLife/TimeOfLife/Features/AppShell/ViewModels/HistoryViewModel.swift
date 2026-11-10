// swiftlint:disable file_length
// (hosts the guarded reload contract, the search derivation, and the
// event-driven subscriptions; splitting the VM is future work, not this
// change — TrackViewModel precedent.)
import Combine
import Foundation
import UIKit

/// Loads committed time entries from the local store and groups them by
/// calendar day for the History list (history-entry-list spec, design D2/D6).
/// Read-only: owns data only — scroll/chrome state lives in `HistoryView`.
/// Rows resolve categories from the entry itself (remove-activities-layer):
/// entries own their ordered category set, so there is no query-time
/// resolution through any other record.
@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var dayGroups: [DayGroup] = []
    @Published private(set) var isLoading = false
    @Published private(set) var undoError: String?
    /// The live History search text, bound to the native search field
    /// (history-search spec). In-memory only: never persisted, logged, or
    /// sent anywhere (design D7). Editing it re-derives from the cached
    /// snapshot; reloads re-apply the latest query (latest-query-wins).
    @Published var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            applySearch()
        }
    }
    /// Localized syntax diagnostic for the current query, or nil when the
    /// query is blank or valid. Invalid queries show no rows at all.
    @Published private(set) var searchDiagnostic: String?
    /// True for valid non-empty queries (including date-only/scope-only):
    /// groups show matching (not tracked) totals.
    @Published private(set) var isSearchFiltering = false
    /// Scrolling result summary for valid non-empty queries with at least
    /// one match (history-search spec): localized plural count plus the
    /// combined known-duration total. Derived from the published groups,
    /// so it needs no stored state and stays consistent with the rows:
    /// nil for blank queries, invalid queries, and zero matches.
    var searchSummary: String? {
        guard isSearchFiltering else { return nil }
        let matched = dayGroups.flatMap(\.entries)
        return HistorySearchSummary.text(
            count: matched.count,
            totalSeconds: HistorySearchSummary.totalSeconds(matched)
        )
    }

    private let store: LocalStore
    private let undoBuffer: UndoBufferStore
    private let nowProvider: () -> Date
    /// Calendar (with locale/time zone) for grouping and labels
    /// (screenshot-capture seam; production keeps `.current`).
    let calendar: Calendar
    /// Notification surface for the event-driven reload subscriptions.
    /// Production uses `.default`; tests inject a private center so global
    /// posts from parallel suites cannot reload this VM out from under
    /// stale-snapshot assertions.
    private let notifications: NotificationCenter
    /// Serializes reloads (TrackViewModel precedent): the appear reload and an
    /// event-driven reload (`.timerStoppedExternally` / foreground /
    /// sync-cycle exit) race on every visible-tab save. `needsReload` starts
    /// true so the first appear loads; `invalidate()` marks the snapshot
    /// stale and the next `loadIfNeeded()` reloads it. A call arriving
    /// mid-load awaits `inFlightLoad` (see `loadIfNeeded`).
    private var inFlightLoad: Task<Bool, Never>?
    private var needsReload = true
    /// Counts `invalidate()` calls so `loadIfNeeded` can tell a concurrent
    /// invalidation (genuine new work — must retry) from a persistent
    /// suspension-classified failure with no progress (must not spin).
    private var invalidateVersion = 0
    /// Whether the owning tab is currently on screen. Event-driven reloads
    /// only fetch while visible: an off-screen event invalidates (so the
    /// next appear reloads) but must not clear `needsReload`, or a later
    /// save that posts no notification (History Log Time, an in-app Track
    /// stop) would leave the next appear serving a stale snapshot. Starts
    /// false — the view sets it on appear/disappear.
    private var isVisible = false
#if DEBUG || SCREENSHOT_CAPTURE
    /// Test hook (nil in production): awaited after the snapshot read, before
    /// publishing — lets tests hold a load open and interleave an invalidate
    /// + reload deterministically (TrackViewModel.stopGate precedent).
    /// Debug/Screenshot-only so no Release caller can suspend a load.
    var loadGate: (@Sendable () async -> Void)?
    /// Test-only loader override (nil in production): when set, `load()`
    /// fetches through this instead of the store, so tests can simulate a
    /// persistent suspension-classified failure while the policy reads
    /// resumed — proving `loadIfNeeded` bounds its retry instead of spinning.
    var loadEntriesOverride: (@Sendable () async throws -> ([TimeEntry], [Category]))?
#endif
    private var categoriesByID: [String: Category] = [:]
    /// Cached ungrouped snapshot feeding both blank History and search
    /// derivation (design D1). Replaced on every load; never mutated.
    private var allEntries: [TimeEntry] = []
    /// True while the cached snapshot is missing because the last fetch
    /// failed — not because History is legitimately empty. `allEntries`
    /// is empty in both cases, but only the failure must keep
    /// `applySearch()` out of the filtering branch: otherwise the next
    /// keystroke or foreground time-context refresh would resurrect the
    /// no-results + Clear-search state on a snapshot that was never
    /// loaded. Set by `load()`; cleared by the next successful load.
    private var isSnapshotUnavailable = false
    /// Per-entry search presentation for the current query, keyed by
    /// entry id. Rebuilt with every derivation, never in row bodies.
    private var searchPresentations: [String: HistorySearchRowPresentation] = [:]
    /// The UndoManager the current registration belongs to, held weakly so
    /// the re-registration after an undo targets the same manager without
    /// capturing a non-Sendable value in the undo handler closure.
    private weak var registeredUndoManager: UndoManager?

    init(
        store: LocalStore,
        undoBuffer: UndoBufferStore,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        notifications: NotificationCenter = .default
    ) {
        self.store = store
        self.undoBuffer = undoBuffer
        self.nowProvider = now
        self.calendar = calendar
        self.notifications = notifications
        observeExternalReload()
    }

    /// Reloads entries and categories and rebuilds the day groups. Runs only
    /// through `loadIfNeeded` (which serializes concurrent reloads) — never
    /// call directly from a second path (see `performUndo`). Returns whether
    /// the failure was suspension-classified (stale preserved for the resume
    /// re-trigger) so `loadIfNeeded` can bound its retry.
    @discardableResult
    func load() async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            let entries: [TimeEntry]
            let categories: [Category]
            #if DEBUG || SCREENSHOT_CAPTURE
            if let loadEntriesOverride {
                let result = try await loadEntriesOverride()
                entries = result.0
                categories = result.1
            } else {
                entries = try await store.entries()
                categories = try await store.categories()
            }
            #else
            entries = try await store.entries()
            categories = try await store.categories()
            #endif
            categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
            #if DEBUG || SCREENSHOT_CAPTURE
            if let loadGate { await loadGate() }
            #endif
            allEntries = entries
            isSnapshotUnavailable = false
            // Derive from the CURRENT query, not a captured one: typing may
            // have advanced while the fetch was in flight, and the newest
            // text must win over this load (design D1).
            applySearch()
            return false
        } catch {
            if DatabaseSuspension.isSuspensionError(error) {
                // Fail-fast suspension refusal: keep the last good snapshot
                // and stay stale so the resume re-trigger reloads instead
                // of blanking committed history mid-transition.
                needsReload = true
                return true
            }
            allEntries = []
            dayGroups = []
            searchPresentations = [:]
            // A storage failure must not present as a zero-match query:
            // without this the view renders the no-results state with a
            // Clear-search action for a failed fetch. The flag below keeps
            // later keystrokes and foreground refreshes out of the
            // filtering branch until a load succeeds.
            isSnapshotUnavailable = true
            isSearchFiltering = false
            return false
        }
    }

    /// Reloads only when the data is stale (never loaded, tab left and
    /// re-entered, or an event-driven invalidate while visible). Re-entrancy
    /// safe: never runs two loads concurrently. A call arriving mid-load
    /// awaits the in-flight load's task value instead of returning with a
    /// stale snapshot — callers awaiting this expect fresh state afterwards
    /// (remove-compact-timer: the Island-Stop commit lands while History is
    /// visible; an early return leaves the pre-commit snapshot on screen
    /// with no later appear to retry). The loop re-awaits the newest claim
    /// before returning: two waiters resuming from the same in-flight load
    /// must not let the second return while the first's retry still runs.
    /// Awaiting `Task<Bool, Never>.value` is
    /// precise (no polling), never throws, and does not inherit caller
    /// cancellation. Deliberately NOT clearing `inFlightLoad` on completion
    /// (TrackViewModel precedent): resumption order after `load.value` is
    /// unspecified, and nulling here can discard a NEWER in-flight load
    /// installed by another waiter's mid-load resumption — breaking the
    /// single-load invariant. Awaiting a completed task's `.value` returns
    /// immediately, so a stale handle is harmless and is overwritten at the
    /// next claim.
    func loadIfNeeded() async {
        while true {
            if let inFlightLoad {
                _ = await inFlightLoad.value
            }
            // Fail-fast while suspended (fix-database-suspension-kill):
            // without this the loop would spin — every refused load
            // re-marks the snapshot stale and the next iteration retries
            // immediately. Keep the stale flag; the resume re-trigger
            // retries with access guaranteed.
            guard needsReload, !DatabaseSuspension.shared.isSuspended else { return }
            needsReload = false
            let generationBefore = DatabaseSuspension.shared.generation
            let invalidationsBefore = invalidateVersion
            let load = Task { await self.load() }
            inFlightLoad = load
            let suspendedFailure = await load.value
            // Bound the suspension retry (review round 1): a persistent
            // suspension-classified failure while the policy reads resumed
            // (misclassified ABORT/INTERRUPT, or a resume landing between the
            // throw and the catch with no further progress) must not spin
            // this loop forever. Retry only when something actually moved
            // (a policy transition or a concurrent invalidate brought new
            // work); otherwise keep the stale flag and return — the resume
            // re-trigger owns the retry. Genuine invalidates always retry
            // (version moved), and the TOCTOU resume-retry still runs once
            // (generation moved), so the dropped-reload contract holds.
            if suspendedFailure,
               needsReload,
               !DatabaseSuspension.shared.isSuspended,
               DatabaseSuspension.shared.generation == generationBefore,
               invalidateVersion == invalidationsBefore {
                break
            }
        }
    }

    /// Marks the data stale so the next History appear reloads it.
    func invalidate() {
        needsReload = true
        invalidateVersion &+= 1
    }

    /// Tracks tab visibility for the event-driven reload gate. Called from
    /// the view's `onAppear`/`onDisappear`.
    func setVisible(_ visible: Bool) {
        isVisible = visible
    }

    // MARK: - History search (history-search spec, design D1/D7)

    /// Re-derives groups and match presentation from the cached snapshot
    /// and the current query/calendar context. Called on query edits and
    /// on significant time/timezone changes while History stays visible.
    /// Pure rendering control: never touches the outbox or sync.
    func refreshTimeContext() {
        applySearch()
    }

    /// Whether a History search query hides the bottom tab bar
    /// (history-search spec, design D4): any non-blank text hides it —
    /// results, no-matches, and syntax-diagnostic states alike. A blank
    /// query (empty or whitespace-only, including a merely focused empty
    /// field) keeps the tab bar. `nonisolated`: pure text check, callable
    /// from synchronous test contexts without a host app.
    nonisolated static func hidesTabBar(for query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Search presentation for a row, or nil on the blank path (the row
    /// then renders exactly as unfiltered History).
    func searchPresentation(for entry: TimeEntry) -> HistorySearchRowPresentation? {
        guard isSearchFiltering else { return nil }
        return searchPresentations[entry.id]
    }

    /// Parses once per query and derives once per entry/snapshot.
    /// Grouping resolves in the injected calendar against the injected now
    /// (screenshot-capture seam; production passes `.current`/`Date.init`,
    /// identical to the previous wall-clock behavior).
    private func applySearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchDiagnostic = nil
            isSearchFiltering = false
            searchPresentations = [:]
            dayGroups = Self.makeDayGroups(entries: allEntries, now: nowProvider(), calendar: calendar, locale: calendar.locale ?? .current)
            return
        }
        switch HistorySearchParser.parse(searchText) {
        case .blank:
            searchDiagnostic = nil
            isSearchFiltering = false
            searchPresentations = [:]
            dayGroups = Self.makeDayGroups(entries: allEntries, now: nowProvider(), calendar: calendar, locale: calendar.locale ?? .current)
        case .invalid(let diagnostic):
            searchDiagnostic = diagnostic.message
            isSearchFiltering = false
            searchPresentations = [:]
            dayGroups = []
        case .valid(let query):
            guard !isSnapshotUnavailable else {
                // The snapshot was never loaded (storage failure): stay
                // out of the filtering branch so the view never renders
                // the no-results + Clear-search state for a failed fetch.
                searchDiagnostic = nil
                isSearchFiltering = false
                searchPresentations = [:]
                dayGroups = []
                return
            }
            searchDiagnostic = nil
            isSearchFiltering = true
            let derived = HistorySearchEvaluator.derive(
                entries: allEntries,
                categoriesByID: categoriesByID,
                query: query
            )
            searchPresentations = derived.presentations
            dayGroups = Self.makeDayGroups(entries: derived.matched, now: nowProvider(), calendar: calendar, locale: calendar.locale ?? .current)
        }
    }

    /// Event-driven reloads that must land with no tab switch
    /// (remove-compact-timer): an external stop (Island Stop intent,
    /// widget/control stop) commits behind a visible tab, and a backgrounded
    /// save is picked up on foreground return. Subscribed here — not in the
    /// view — so the real notification path is unit-testable: tests post to
    /// NotificationCenter and assert the reload (deleting a subscription
    /// fails those tests). Lifetime matches the view: the owning
    /// `@StateObject` holds this VM, whose cancellables die with it.
    private var reloadCancellables = Set<AnyCancellable>()

    private func observeExternalReload() {
        notifications.publisher(for: .timerStoppedExternally)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in await self?.handleExternalReload() }
            }
            .store(in: &reloadCancellables)
        // Single foreground path (review round 1): `DatabaseSuspension`
        // posts `didResumeNotification` synchronously from its own
        // `willEnterForeground` observer, so a foreground subscription here
        // would double every foreground return (two invalidates → two full
        // loads). The resume signal implies foreground return and carries
        // resumable access, so it owns the reload alone.
        notifications.publisher(for: DatabaseSuspension.didResumeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in await self?.handleExternalReload() }
            }
            .store(in: &reloadCancellables)
    }

    /// Shared event-driven reload (remove-compact-timer): the exact
    /// invalidate + guarded-reload sequence the views and the VM-owned
    /// notification subscriptions run on `.timerStoppedExternally`,
    /// foreground return, and sync-cycle exit. Off-screen events invalidate
    /// only — the appear reload still sees the stale flag (without this the
    /// off-screen reload would consume it and a later notification-less
    /// save would never surface). Production code under test —
    /// the refresh tests drive this helper and the notification tests drive
    /// the real posted-notification path.
    func handleExternalReload() async {
        invalidate()
        guard isVisible else { return }
        await loadIfNeeded()
    }

    // MARK: - Entry shake-to-undo (history-entry-list, fix-87)

    /// Registers the newest restorable entry deletion with the system Undo
    /// manager, so shaking surfaces the DEFAULT Undo confirmation and
    /// confirming restores exactly one entry — the most recent buffered
    /// one. Previous registrations are cleared first, so one shake+confirm
    /// can never restore two deletions. Offers nothing when the buffer holds
    /// no entry deletion — including when the newest row belongs to another
    /// surface (U7 supersession). Mirrors
    /// `ManageCategoriesViewModel.registerSystemUndo`.
    func registerSystemUndo(with undoManager: UndoManager?) async {
        guard let undoManager else { return }
        registeredUndoManager = undoManager
        undoManager.removeAllActions(withTarget: self)
        guard let recent = try? await undoBuffer.mostRecent(),
              (try? await store.entryDeletionSnapshot(bufferID: recent.id)) != nil else { return }
        undoManager.registerUndo(withTarget: self) { target in
            Task { @MainActor in
                await target.performUndo()
                await target.registerSystemUndo(with: target.registeredUndoManager)
            }
        }
        // Names the undoable action so the DEFAULT system confirmation
        // states what Confirm will restore. Reuses the existing localized
        // Delete string — no new strings (U4).
        undoManager.setActionName(L10n.entryDeleteConfirm.text)
    }

    /// Undoes the most recent entry deletion: restores the entry with its
    /// ordered categories, removes the buffer row, and rebuilds the day
    /// groups. Only entry deletions are restored here — buffer rows owned
    /// by other surfaces are left for their owners. Nothing is synced.
    /// Refused while a buffered-deletion push is in flight (the row may
    /// commit at any moment; retry after the sync finishes) — surfaced as
    /// the persistence error, same as a failed restore, since the
    /// user-visible outcome is identical (no undo).
    func performUndo() async {
        do {
            guard let recent = try await undoBuffer.mostRecent() else { return }
            guard try await store.entryDeletionSnapshot(bufferID: recent.id) != nil else { return }
            if try await store.undoEntryDeletion(bufferID: recent.id) != nil {
                undoError = nil
                // Serialized like every other reload: a direct `load()` here
                // would race an in-flight `loadIfNeeded()` load and the
                // pre-restore snapshot could overwrite the restored row.
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

    // MARK: - Row presentation (EntryRow inputs)

    /// First category's validated SF Symbol, or the `questionmark` fallback
    /// when the entry has no categories (D6).
    func icon(for entry: TimeEntry) -> String {
        guard let first = categories(for: entry).first else {
            return "questionmark"
        }
        return CatalogIcon(validated: first.icon).displaySymbol
    }

    /// Comma-separated category names; empty string when none (D6).
    func categoryNames(for entry: TimeEntry) -> String {
        categories(for: entry).map(\.name).joined(separator: ", ")
    }

    func isInProgress(_ entry: TimeEntry) -> Bool {
        entry.endedAt == nil
    }

    /// Whether the entry's row shows the notes indicator: true when notes
    /// are non-empty. Whitespace-only notes count as empty
    /// (history-entry-list notes indicator).
    func hasNotes(for entry: TimeEntry) -> Bool {
        !entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Short-time caption ("14:00") in the view model's calendar
    /// (TrackViewModel precedent): capture pins locale/time zone through
    /// the injected calendar; production keeps `.current`, identical to
    /// the static helper. One formatter for the view-model lifetime
    /// (`calendar` is a `let`): `timeframeText` runs per History row, and
    /// a fresh `DateFormatter` per call pays an ICU locale load on the
    /// main thread.
    private func timeText(for date: Date) -> String {
        timeFormatter.string(from: date)
    }

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.locale = calendar.locale ?? .current
        formatter.timeZone = calendar.timeZone
        return formatter
    }()

    /// The start–end timeframe caption ("14:00 – 15:20"); an in-progress
    /// entry shows the start time followed by the in-progress indicator (D5).
    func timeframeText(for entry: TimeEntry) -> String {
        let start = timeText(for: entry.startedAt)
        if isInProgress(entry) {
            return "\(start) – \(L10n.historyInProgress.text)"
        }
        guard let endedAt = entry.endedAt else {
            return start
        }
        return "\(start) – \(timeText(for: endedAt))"
    }

    /// The entry's natural-language duration in the given locale; an
    /// in-progress entry shows the localized in-progress indicator
    /// instead (D5).
    /// - Note: the in-progress indicator intentionally follows the app
    ///   language (`L10n`), not `locale`.
    /// - Note: a nil locale follows the capture request locale while a
    ///   capture override is active (screenshot-capture chrome fix), else
    ///   the process locale. Explicit locales always win.
    func durationText(for entry: TimeEntry, locale: Locale? = nil) -> String {
        if isInProgress(entry) {
            return L10n.historyInProgress.text
        }
        let seconds = entry.durationSeconds ?? Self.clampedSeconds(
            start: entry.startedAt,
            end: entry.endedAt
        )
        return Self.naturalDuration(seconds, locale: locale)
    }

    /// The entry's own ordered categories, position-preserved, unknown ids
    /// skipped (entries own their categories; nothing resolves elsewhere).
    func categories(for entry: TimeEntry) -> [Category] {
        entry.categoryIDs.compactMap { categoriesByID[$0] }
    }

    // MARK: - Grouping (pure, unit-tested)

    /// Groups entries by the calendar day of `startedAt` (D2): newest day
    /// first, entries within a day newest first, per-day totals (D8).
    /// - Note: `locale` governs durations only (row durations via
    ///   `durationText`, day totals). Group headings intentionally follow
    ///   the app language and calendar (`dayLabel`), never `locale`.
    nonisolated static func makeDayGroups(
        entries: [TimeEntry],
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> [DayGroup] {
        let sorted = entries.sorted { $0.startedAt > $1.startedAt }
        var buckets: [String: [TimeEntry]] = [:]
        var order: [String] = []
        for entry in sorted {
            let day = calendar.startOfDay(for: entry.startedAt)
            let key = dayKey(day, calendar: calendar)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(entry)
        }

        // One reusable day-label formatter per derivation (not per group):
        // building a DateFormatter costs an ICU data load, and this runs on
        // every keystroke while searching (history-search perf). The box is
        // thread-confined to this call — no sharing, no per-group locking.
        var dayFormatter: DateFormatter?
        return order.map { key in
            let dayEntries = buckets[key] ?? []
            let day = dayFromKey(key, calendar: calendar)
            return DayGroup(
                id: key,
                label: dayLabel(for: day, now: now, calendar: calendar, formatter: &dayFormatter),
                entries: dayEntries,
                total: naturalDuration(
                    dayEntries.reduce(0) { $0 + ($1.durationSeconds ?? 0) },
                    locale: locale
                )
            )
        }
    }

    /// Natural-language duration in the given locale (`33s`, `1m 20s`,
    /// `1h 12m`, `1d 12h` in English; locale-correct abbreviations and
    /// plurals elsewhere, e.g. `1 ч 12 мин` in Russian) (D5). The grammar —
    /// which tiers appear — is fixed here; Foundation owns the unit words.
    /// Implementation lives in `DurationFormatting`; this forwards so
    /// existing call sites keep compiling unchanged. A nil locale follows
    /// the capture request locale while a capture override is active
    /// (screenshot-capture chrome fix), else the process locale.
    nonisolated static func naturalDuration(_ seconds: Int, locale: Locale? = nil) -> String {
        DurationFormatting.natural(seconds, locale: defaultUnitLocale(locale))
    }

    /// Default locale for unit chrome: the capture request locale while a
    /// capture override is active, else the process locale. Explicit
    /// parameters always win (unit tests pass explicit values).
    nonisolated private static func defaultUnitLocale(_ locale: Locale?) -> Locale {
        #if SCREENSHOT_CAPTURE
        if let locale {
            return locale
        }
        return ScreenshotLocale.appLocale ?? .current
        #else
        return locale ?? .current
        #endif
    }

    private static func clampedSeconds(start: Date, end: Date?) -> Int {
        guard let end else { return 0 }
        return max(0, Int(end.timeIntervalSince(start).rounded()))
    }

    nonisolated private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            comps.year ?? 0,
            comps.month ?? 0,
            comps.day ?? 0
        )
    }

    nonisolated private static func dayFromKey(_ key: String, calendar: Calendar) -> Date {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        var comps = DateComponents()
        comps.year = !parts.isEmpty ? parts[0] : 0
        comps.month = parts.count > 1 ? parts[1] : 0
        comps.day = parts.count > 2 ? parts[2] : 0
        return calendar.date(from: comps) ?? Date()
    }
}
