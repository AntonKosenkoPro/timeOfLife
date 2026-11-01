import Combine
import Foundation
import UIKit

/// Period-scoped breakdown of committed tracked time (insights-breakdown
/// spec). Read-only mirror: loads entries, activities, and categories from
/// the local store and derives the hero total plus per-category / per-activity
/// rows with pure, unit-tested helpers. Owns data only — period/lens
/// selection lives in `InsightsView`.
@MainActor
final class InsightsViewModel: ObservableObject {
    @Published private(set) var hasCommittedAllTime = false
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false

    private let store: LocalStore
    private let nowProvider: () -> Date
    /// Notification surface for the event-driven reload subscriptions.
    /// Production uses `.default`; tests inject a private center so global
    /// posts from parallel suites cannot reload this VM out from under
    /// stale-snapshot assertions.
    private let notifications: NotificationCenter
    /// Serializes reloads (TrackViewModel precedent, HistoryViewModel mirror):
    /// the appear reload and an event-driven reload (`.timerStoppedExternally`
    /// / foreground / sync-cycle exit) race on every visible-tab save. A call
    /// arriving mid-load awaits `inFlightLoad` (see `loadIfNeeded`) instead
    /// of returning with a stale snapshot no later appear retries.
    private var inFlightLoad: Task<Void, Never>?
    private var needsReload = true
    /// Whether the owning tab is currently on screen. Event-driven reloads
    /// only fetch while visible: an off-screen event invalidates (so the
    /// next appear reloads) but must not clear `needsReload`, or a later
    /// save that posts no notification (History Log Time, an in-app Track
    /// stop) would leave the next appear serving a stale breakdown. Starts
    /// false — the view sets it on appear/disappear.
    private var isVisible = false
#if DEBUG
    /// Test hook (nil in production): awaited after the snapshot read, before
    /// publishing — lets tests hold a load open and interleave an invalidate
    /// + reload deterministically (TrackViewModel.stopGate precedent).
    /// Debug-only so no Release caller can suspend a load.
    var loadGate: (@Sendable () async -> Void)?
#endif
    private var snapshot = Snapshot()

    private struct Snapshot {
        var entries: [TimeEntry] = []
        var categories: [Category] = []
    }

    init(store: LocalStore, now: @escaping () -> Date = Date.init, notifications: NotificationCenter = .default) {
        self.store = store
        self.nowProvider = now
        self.notifications = notifications
        observeExternalReload()
    }

    /// Reloads entries, activities, and categories. A failure keeps the last
    /// good snapshot: a mirror-only screen must not blank on a transient
    /// failure (committed-only totals would otherwise read as zero).
    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            let entries = try await store.entries()
            let categories = try await store.categories()
            #if DEBUG
            if let loadGate { await loadGate() }
            #endif
            snapshot = Snapshot(entries: entries, categories: categories)
            hasCommittedAllTime = entries.contains { $0.endedAt != nil }
        } catch {
            // Keep the last good snapshot (same philosophy as History load).
        }
    }

    /// Reloads only when the data is stale (never loaded, tab left and
    /// re-entered, or an event-driven invalidate while visible). Re-entrancy
    /// safe: never runs two loads concurrently. A call arriving mid-load
    /// awaits the in-flight load's task value instead of returning with a
    /// stale snapshot — callers awaiting this expect fresh state afterwards
    /// (remove-compact-timer: the Island-Stop commit lands while Insights is
    /// visible; an early return leaves the pre-commit breakdown on screen
    /// with no later appear to retry). The loop re-awaits the newest claim
    /// before returning: two waiters resuming from the same in-flight load
    /// must not let the second return while the first's retry still runs.
    /// Deliberately NOT clearing
    /// `inFlightLoad` on completion (TrackViewModel precedent — see
    /// HistoryViewModel for the full rationale).
    func loadIfNeeded() async {
        while true {
            if let inFlightLoad {
                await inFlightLoad.value
            }
            guard needsReload else { return }
            needsReload = false
            let load = Task { await self.load() }
            inFlightLoad = load
            await load.value
        }
    }

    /// Marks the data stale so the next Insights appear reloads it.
    func invalidate() {
        needsReload = true
    }

    /// Tracks tab visibility for the event-driven reload gate. Called from
    /// the view's `onAppear`/`onDisappear`.
    func setVisible(_ visible: Bool) {
        isVisible = visible
    }

    /// Event-driven reloads that must land with no tab switch
    /// (remove-compact-timer): mirrors HistoryViewModel — subscribed here so
    /// the real notification path is unit-testable (deleting a subscription
    /// fails those tests). Lifetime matches the view.
    private var reloadCancellables = Set<AnyCancellable>()

    private func observeExternalReload() {
        notifications.publisher(for: .timerStoppedExternally)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in await self?.handleExternalReload() }
            }
            .store(in: &reloadCancellables)
        notifications.publisher(for: UIApplication.willEnterForegroundNotification)
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

    /// The breakdown for the given period/lens over the loaded snapshot.
    func breakdown(
        period: InsightsPeriod,
        lens: InsightsLens,
        calendar: Calendar = .current
    ) -> InsightsBreakdown {
        Self.makeBreakdown(
            entries: snapshot.entries,
            categories: snapshot.categories,
            interval: period.interval(now: nowProvider(), calendar: calendar),
            lens: lens
        )
    }

    // MARK: - Aggregation (pure, unit-tested)

    /// Builds the hero total plus breakdown rows from committed entries only
    /// (insights-breakdown spec): in-progress entries (`endedAt == nil`) are
    /// excluded and NULL durations contribute zero (D8 precedent). The
    /// activity lens groups by trimmed exact text (`Gym` ≠ `GYM`); the
    /// category lens attributes the full duration to *every* category stored
    /// on the entry (rows may sum above the hero — full-credit by design).
    /// Entries with no categories aggregate into the uncategorized bucket.
    nonisolated static func makeBreakdown(
        entries: [TimeEntry],
        categories: [Category],
        interval: DateInterval?,
        lens: InsightsLens
    ) -> InsightsBreakdown {
        let inPeriod = committedEntries(entries, in: interval)
        let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        var attribution = BreakdownAttribution()
        for entry in inPeriod {
            attribution.attribute(entry, categoriesByID: categoriesByID, lens: lens)
        }
        return InsightsBreakdown(
            totalSeconds: inPeriod.reduce(0) { $0 + ($1.durationSeconds ?? 0) },
            rows: attribution.rows
        )
    }

    /// Committed entries (`endedAt != nil`) whose `startedAt` falls in the
    /// interval (nil interval = unbounded). NULL durations are kept here and
    /// counted as zero by the caller (D8 precedent).
    nonisolated private static func committedEntries(
        _ entries: [TimeEntry],
        in interval: DateInterval?
    ) -> [TimeEntry] {
        entries.filter { entry in
            guard entry.endedAt != nil else { return false }
            guard let interval else { return true }
            return interval.contains(entry.startedAt)
        }
    }

    /// First category's validated SF Symbol, or the `questionmark` fallback
    /// when the entry has no (resolvable) categories (History D6 rule).
    nonisolated static func icon(
        categoryIDs: [String],
        categoriesByID: [String: Category]
    ) -> String {
        guard let first = categoryIDs.compactMap({ categoriesByID[$0] }).first else {
            return "questionmark"
        }
        return CatalogIcon(validated: first.icon).displaySymbol
    }
}

/// Mutable per-entry attribution accumulator behind `makeBreakdown`
/// (file scope: no actor isolation, usable from nonisolated statics).
private struct BreakdownAttribution {
    private var totals: [String: Int] = [:]
    private var members: [String: [String]] = [:]
    private var display: [String: (name: String, icon: String)] = [:]

    /// Biggest total first, ties broken by name for determinism.
    var rows: [InsightsBucket] {
        display.map { id, shown in
            InsightsBucket(
                id: id,
                name: shown.name,
                icon: shown.icon,
                totalSeconds: totals[id] ?? 0,
                entryIDs: (members[id] ?? []).sorted()
            )
        }.sorted {
            if $0.totalSeconds != $1.totalSeconds { return $0.totalSeconds > $1.totalSeconds }
            return $0.name < $1.name
        }
    }

    mutating func attribute(
        _ entry: TimeEntry,
        categoriesByID: [String: Category],
        lens: InsightsLens
    ) {
        let seconds = entry.durationSeconds ?? 0
        switch lens {
        case .activity:
            // Exact trimmed text is the grouping identity (`Gym` ≠ `GYM`);
            // each entry's full duration attributes to its text row.
            add(
                id: "text:\(entry.activityText)",
                name: entry.activityText,
                icon: InsightsViewModel.icon(
                    categoryIDs: entry.categoryIDs,
                    categoriesByID: categoriesByID
                ),
                seconds: seconds,
                entryID: entry.id
            )
        case .category:
            let resolved = entry.categoryIDs.compactMap { categoriesByID[$0] }
            if resolved.isEmpty {
                add(
                    id: InsightsBucket.uncategorizedID,
                    name: L10n.insightsNoCategory.text,
                    icon: "questionmark",
                    seconds: seconds,
                    entryID: entry.id
                )
            } else {
                for category in resolved {
                    add(
                        id: category.id,
                        name: category.name,
                        icon: CatalogIcon(validated: category.icon).displaySymbol,
                        seconds: seconds,
                        entryID: entry.id
                    )
                }
            }
        }
    }

    private mutating func add(id: String, name: String, icon: String, seconds: Int, entryID: String) {
        totals[id, default: 0] += seconds
        members[id, default: []].append(entryID)
        // First-seen display wins: a later zero-duration member (e.g. a
        // failed short entry) must not clobber the row's name/icon.
        if display[id] == nil {
            display[id] = (name, icon)
        }
    }
}
