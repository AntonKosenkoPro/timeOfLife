import Foundation

/// Day-grouped view data for the History list (history-entry-list spec).
struct DayGroup: Identifiable, Equatable {
    /// Stable identifier for the calendar day (e.g. "2026-09-03").
    let id: String
    /// Relative ("Today" / "Yesterday") or absolute regional day label.
    let label: String
    /// The day's entries, newest first.
    let entries: [TimeEntry]
    /// Natural-language sum of the day's known durations (e.g. "2h 35m").
    /// Entries with no duration (in-progress) contribute zero (D8).
    let total: String
}

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

    private let store: LocalStore
    private let undoBuffer: UndoBufferStore
    private let nowProvider: () -> Date
    private var needsReload = true
    private var categoriesByID: [String: Category] = [:]
    /// The UndoManager the current registration belongs to, held weakly so
    /// the re-registration after an undo targets the same manager without
    /// capturing a non-Sendable value in the undo handler closure.
    private weak var registeredUndoManager: UndoManager?

    init(
        store: LocalStore,
        undoBuffer: UndoBufferStore,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.undoBuffer = undoBuffer
        self.nowProvider = now
    }

    /// Reloads entries and categories and rebuilds the day groups. Called on
    /// appear.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let entries = try await store.entries()
            let categories = try await store.categories()
            categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

            dayGroups = Self.makeDayGroups(entries: entries, now: Date())
        } catch {
            dayGroups = []
        }
    }

    /// Reloads only when the data has not been loaded yet or the tab was
    /// left and re-entered (an entry may have been saved on Track in
    /// between). Re-entrancy safe: never runs two loads concurrently; a call
    /// arriving mid-load keeps `needsReload` set so the next appear retries.
    func loadIfNeeded() async {
        guard needsReload, !isLoading else { return }
        needsReload = false
        await load()
    }

    /// Marks the data stale so the next History appear reloads it.
    func invalidate() {
        needsReload = true
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
                await load()
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

    /// Localized "via <Source>" provenance label; empty for manual entries
    /// (entry-provenance D7).
    func viaText(for entry: TimeEntry) -> String {
        EntryProvenance.viaText(for: entry.source)
    }

    /// The start–end timeframe caption ("14:00 – 15:20"); an in-progress
    /// entry shows the start time followed by the in-progress indicator (D5).
    func timeframeText(for entry: TimeEntry) -> String {
        let start = Self.timeText(for: entry.startedAt)
        if isInProgress(entry) {
            return "\(start) – \(L10n.historyInProgress.text)"
        }
        guard let endedAt = entry.endedAt else {
            return start
        }
        return "\(start) – \(Self.timeText(for: endedAt))"
    }

    /// The entry's natural-language duration in the given locale; an
    /// in-progress entry shows the localized in-progress indicator
    /// instead (D5).
    /// - Note: the in-progress indicator intentionally follows the app
    ///   language (`L10n`), not `locale`.
    func durationText(for entry: TimeEntry, locale: Locale = .current) -> String {
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

        return order.map { key in
            let dayEntries = buckets[key] ?? []
            let day = dayFromKey(key, calendar: calendar)
            return DayGroup(
                id: key,
                label: dayLabel(for: day, now: now, calendar: calendar),
                entries: dayEntries,
                total: naturalDuration(
                    dayEntries.reduce(0) { $0 + ($1.durationSeconds ?? 0) },
                    locale: locale
                )
            )
        }
    }

    /// "Today" / "Yesterday" for the two most recent calendar days, then the
    /// device-locale regional date for older days (D3).
    nonisolated static func dayLabel(for day: Date, now: Date, calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: now)
        let dayStart = calendar.startOfDay(for: day)
        let days = calendar.dateComponents([.day], from: dayStart, to: today).day ?? 0
        switch days {
        case 0: return L10n.historyDayToday.text
        case 1: return L10n.historyDayYesterday.text
        default:
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            formatter.calendar = calendar
            return formatter.string(from: day)
        }
    }

    /// Natural-language duration in the given locale (`33s`, `1m 20s`,
    /// `1h 12m`, `1d 12h` in English; locale-correct abbreviations and
    /// plurals elsewhere, e.g. `1 ч 12 мин` in Russian) (D5). The grammar —
    /// which tiers appear — is fixed here; Foundation owns the unit words.
    /// Implementation lives in `DurationFormatting`; this forwards so
    /// existing call sites keep compiling unchanged.
    nonisolated static func naturalDuration(_ seconds: Int, locale: Locale = .current) -> String {
        DurationFormatting.natural(seconds, locale: locale)
    }

    /// Short-time caption ("14:00").
    nonisolated static func timeText(for date: Date) -> String {
        timeFormatter.string(from: date)
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

    nonisolated private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}
