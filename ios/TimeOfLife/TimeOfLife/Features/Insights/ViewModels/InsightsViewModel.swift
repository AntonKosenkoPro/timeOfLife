import Foundation

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
    private var needsReload = true
    private var snapshot = Snapshot()

    private struct Snapshot {
        var entries: [TimeEntry] = []
        var activities: [Activity] = []
        var categories: [Category] = []
    }

    init(store: LocalStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.nowProvider = now
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
            let activities = try await store.activities()
            let categories = try await store.categories()
            snapshot = Snapshot(entries: entries, activities: activities, categories: categories)
            hasCommittedAllTime = entries.contains { $0.endedAt != nil }
        } catch {
            // Keep the last good snapshot (same philosophy as History load).
        }
    }

    /// Reloads only when the data has not been loaded yet or the tab was
    /// left and re-entered (an entry may have been saved on Track in
    /// between). Re-entrancy safe, mirroring `HistoryViewModel`.
    func loadIfNeeded() async {
        guard needsReload, !isLoading else { return }
        needsReload = false
        await load()
    }

    /// Marks the data stale so the next Insights appear reloads it.
    func invalidate() {
        needsReload = true
    }

    /// The breakdown for the given period/lens over the loaded snapshot.
    func breakdown(
        period: InsightsPeriod,
        lens: InsightsLens,
        calendar: Calendar = .current
    ) -> InsightsBreakdown {
        Self.makeBreakdown(
            entries: snapshot.entries,
            activities: snapshot.activities,
            categories: snapshot.categories,
            interval: period.interval(now: nowProvider(), calendar: calendar),
            lens: lens
        )
    }

    // MARK: - Aggregation (pure, unit-tested)

    /// Builds the hero total plus breakdown rows from committed entries only
    /// (insights-breakdown spec): in-progress entries (`endedAt == nil`) are
    /// excluded and NULL durations contribute zero (D8 precedent). Entries
    /// resolve the activity's *current* categories at query time, so
    /// recategorization reclassifies history. The category lens attributes
    /// the full duration to *every* attached category; activities with no
    /// (resolvable) categories aggregate into the uncategorized bucket.
    nonisolated static func makeBreakdown(
        entries: [TimeEntry],
        activities: [Activity],
        categories: [Category],
        interval: DateInterval?,
        lens: InsightsLens
    ) -> InsightsBreakdown {
        let inPeriod = committedEntries(entries, in: interval)
        let activitiesByID = Dictionary(uniqueKeysWithValues: activities.map { ($0.id, $0) })
        let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        var attribution = BreakdownAttribution()
        for entry in inPeriod {
            attribution.attribute(
                entry,
                activitiesByID: activitiesByID,
                categoriesByID: categoriesByID,
                lens: lens
            )
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
    /// when the activity has no (resolvable) categories (History D6 rule).
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
        activitiesByID: [String: Activity],
        categoriesByID: [String: Category],
        lens: InsightsLens
    ) {
        let seconds = entry.durationSeconds ?? 0
        switch lens {
        case .activity:
            let activity = activitiesByID[entry.activityID]
            add(
                id: entry.activityID,
                name: activity?.name ?? entry.activityName,
                icon: InsightsViewModel.icon(
                    categoryIDs: activity?.categoryIDs ?? [],
                    categoriesByID: categoriesByID
                ),
                seconds: seconds,
                entryID: entry.id
            )
        case .category:
            let resolved = (activitiesByID[entry.activityID]?.categoryIDs ?? [])
                .compactMap { categoriesByID[$0] }
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
        display[id] = (name, icon)
    }
}
