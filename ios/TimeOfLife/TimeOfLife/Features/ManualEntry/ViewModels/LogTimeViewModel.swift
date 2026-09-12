import Combine
import Foundation
import SwiftUI

/// Presentation mode of the unified entry form (entry-editor spec): CREATE
/// logs new time (manual-entry behavior, unchanged); EDIT corrects an
/// existing `manual` entry; LOCKED shows an imported entry read-only with
/// delete as the only mutation.
enum EntryFormMode: Equatable, Sendable {
    case create
    case edit
    case locked
}

/// View model for the Log Time sheet (manual-entry spec) grown into the
/// unified entry form (entry-editor spec): a validated
/// activity + start/end draft that saves a committed manual entry in CREATE
/// mode, updates an existing `manual` entry in EDIT mode, or exposes an
/// imported entry read-only in LOCKED mode.
///
/// The draft is fully local: Start defaults to now floored to 5 minutes,
/// End to Start + 1h. Moving Start at/past End auto-pushes End to preserve
/// the last valid duration (Calendar behavior); moving End never moves
/// Start. Add/Save is a validity gate (`isAddEnabled`): an activity must be
/// chosen and End must be strictly after Start. Persistence delegates to
/// `TimerService`'s store (`LocalStore.createEntry` + transactional outbox
/// for CREATE, LWW `LocalStore.updateEntry` for EDIT);
/// overlaps and future end-times are allowed, matching store semantics.
@MainActor
final class LogTimeViewModel: ObservableObject, ActivitySearchHosting {
    /// Default duration for a fresh sheet and the fallback when the
    /// previous duration is unknown or invalid.
    static let defaultDuration: TimeInterval = 3_600
    /// Start-time flooring granularity, in minutes.
    static let startGranularityMinutes = 5

    @Published private(set) var selectedActivity: Activity?
    @Published private(set) var startsAt: Date
    @Published private(set) var endsAt: Date
    @Published var errorMessage: String?
    /// The entry being corrected in EDIT mode or shown in LOCKED mode
    /// (nil in CREATE mode).
    @Published private(set) var editingEntry: TimeEntry?
    /// Picker presentation. Set by `activateSearch`, cleared by selection,
    /// creation, restoration, or `cancelSearch`.
    @Published var isPickerActive = false

    /// The last strictly-positive duration, preserved across edits so a
    /// Start pushed past End keeps a meaningful length.
    private var lastValidDuration: TimeInterval = LogTimeViewModel.defaultDuration

    let service: TimerService

    /// The form mode, derived from the edited entry: no entry is CREATE, a
    /// `manual` entry is EDIT, any other source is LOCKED (entry-editor
    /// spec). Pure so the mode routing is unit-testable.
    static func mode(for entry: TimeEntry?) -> EntryFormMode {
        guard let entry else { return .create }
        return entry.source == "manual" ? .edit : .locked
    }

    /// The mode of this form instance.
    var mode: EntryFormMode { Self.mode(for: editingEntry) }

    /// True in LOCKED mode: all inputs are disabled and no confirm action
    /// exists (delete stays available).
    var isLocked: Bool { mode == .locked }

    init(
        service: TimerService,
        initialActivity: Activity? = nil,
        editing entry: TimeEntry? = nil,
        now: Date = Date()
    ) {
        self.service = service
        self.editingEntry = entry
        if let entry {
            // EDIT/LOCKED prefill: the entry's own activity (by id + name;
            // save re-resolves the full record) and interval. The form never
            // receives an in-progress entry (no entry point lists one); a
            // nil end falls back to the default duration defensively.
            self.selectedActivity = Activity(id: entry.activityID, name: entry.activityName)
            self.startsAt = entry.startedAt
            self.endsAt = entry.endedAt ?? entry.startedAt.addingTimeInterval(Self.defaultDuration)
            let duration = endsAt.timeIntervalSince(startsAt)
            self.lastValidDuration = duration > 0 ? duration : Self.defaultDuration
        } else {
            let start = Self.floored(now)
            self.startsAt = start
            self.endsAt = start.addingTimeInterval(Self.defaultDuration)
            self.selectedActivity = initialActivity
        }
    }

    /// True when an activity is chosen and End is strictly after Start.
    var isAddEnabled: Bool {
        selectedActivity != nil && endsAt > startsAt
    }

    /// Chooses the activity (picker confirm or quick-create result) and
    /// closes the picker.
    func select(_ activity: Activity) {
        selectedActivity = activity
        isPickerActive = false
        errorMessage = nil
    }

    /// Moves Start, auto-pushing End to preserve the last valid duration
    /// when the new Start lands at or past End.
    func setStartsAt(_ newStart: Date) {
        refreshValidDuration()
        startsAt = newStart
        if endsAt <= newStart {
            endsAt = newStart.addingTimeInterval(lastValidDuration)
        }
        refreshValidDuration()
    }

    /// Moves End. Never moves Start; the form may hold end <= start, in
    /// which case Add stays disabled.
    func setEndsAt(_ newEnd: Date) {
        endsAt = newEnd
        refreshValidDuration()
    }

    /// Saves the draft: a committed manual entry in CREATE mode, a
    /// last-write-wins update in EDIT mode. Returns false (with
    /// `errorMessage` set and the draft intact) when the form is invalid,
    /// the activity no longer exists, persistence fails, or (EDIT) the
    /// record changed underneath (stale write). LOCKED mode has no confirm
    /// path and always returns false.
    func save() async -> Bool {
        guard mode != .locked else { return false }
        guard let selected = selectedActivity, endsAt > startsAt else { return false }
        do {
            guard let activity = try await service.store.activity(id: selected.id) else {
                errorMessage = L10n.logTimeActivityMissing.text
                return false
            }
            if let editing = editingEntry, mode == .edit {
                let updated = TimeEntry(
                    id: editing.id,
                    activityID: activity.id,
                    activityName: activity.name,
                    startedAt: startsAt,
                    endedAt: endsAt,
                    durationSeconds: max(0, Int(endsAt.timeIntervalSince(startsAt))),
                    source: editing.source,
                    sourceRef: editing.sourceRef,
                    createdAt: editing.createdAt,
                    updatedAt: Date()
                )
                guard try await service.store.updateEntry(updated) else {
                    // Lost the last-write-wins race (e.g. a sync pull landed
                    // a newer version): keep the draft, stay open.
                    errorMessage = L10n.entryStaleError.text
                    return false
                }
                return true
            }
            let entry = TimeEntry(
                id: await service.store.newRecordID(),
                activityID: activity.id,
                activityName: activity.name,
                startedAt: startsAt,
                endedAt: endsAt,
                durationSeconds: max(0, Int(endsAt.timeIntervalSince(startsAt))),
                source: "manual"
            )
            try await service.store.createEntry(entry)
            return true
        } catch {
            errorMessage = L10n.text(in: .default, code: "error.unknown")
            return false
        }
    }

    /// Deletes the edited entry (EDIT + LOCKED modes) into the durable undo
    /// buffer (no outbox row yet — shake-to-undo restores it; expiry commits
    /// on foreground). Returns true when the caller should dismiss the form
    /// (deleted, or already gone elsewhere); false keeps the form open with
    /// `errorMessage` set.
    func deleteConfirmed() async -> Bool {
        guard let editing = editingEntry, mode != .create else { return false }
        do {
            switch try await service.store.deleteEntryUndoable(id: editing.id) {
            case .deleted:
                return true
            case .missing:
                // Already gone elsewhere — the desired end state holds.
                return true
            case .failure:
                errorMessage = L10n.errorLocalPersistence.text
                return false
            }
        } catch {
            errorMessage = L10n.errorLocalPersistence.text
            return false
        }
    }

    // MARK: - Activity picking (ActivitySearchHosting)

    /// The recency-ordered catalog for the picker, loaded on open.
    @Published private(set) var activities: [Activity] = []
    /// The draft search state; never mutates the chosen activity until a
    /// result is confirmed or quick-created.
    @Published private(set) var search = ActivitySearchState()
    @Published private(set) var pendingDeletion: Activity?
    private(set) var pendingRestore: Activity?

    var selectedActivityID: String? { selectedActivity?.id }

    var searchResults: ActivitySearchResults {
        ActivitySearchResults.derive(
            query: search.query,
            activities: activities,
            pendingDeletion: pendingDeletion
        )
    }

    var searchQueryBinding: Binding<String> {
        Binding(
            get: { self.search.query },
            set: { self.setSearchQuery($0) }
        )
    }

    func setSearchQuery(_ query: String) {
        search.query = query
        refreshPendingDeletion()
    }

    /// Opens the picker: pre-fills the chosen activity name (or empty),
    /// refreshes the catalog, and presents.
    func activateSearch() {
        search = ActivitySearchState(query: selectedActivity?.name ?? "")
        isPickerActive = true
        refreshPendingDeletion()
        Task {
            if let loaded = try? await service.store.activities() {
                activities = loaded
            }
        }
    }

    /// Ends picking without confirmation: the previously chosen activity
    /// (or none) is unchanged.
    func cancelSearch() {
        isPickerActive = false
        search = ActivitySearchState()
    }

    func dismissPendingRestore() {
        pendingRestore = nil
    }

    /// Confirms an existing picker result: chooses it and closes.
    func confirmSearchResult(_ activity: Activity) {
        select(activity)
    }

    /// Quick-creates the unmatched valid query (categoryless) and chooses
    /// it. On failure the picker stays open with the query preserved and a
    /// localized non-field error. A matching restorable deletion surfaces
    /// the explicit restore prompt instead of creating a duplicate.
    func quickCreateFromSearch() async {
        let trimmed = search.trimmedQuery
        guard !trimmed.isEmpty else { return }
        do {
            let outcome = try await service.prepareActivity(named: trimmed)
            switch outcome {
            case let .created(activity), let .existing(activity):
                activities = try await service.store.activities()
                select(activity)
            case let .restorableDeletion(activity):
                pendingRestore = activity
            case .invalid:
                search.errorMessage = L10n.timerEmptyActivityError.text
            case .failure:
                search.errorMessage = L10n.text(in: .default, code: "error.unknown")
            }
        } catch {
            search.errorMessage = L10n.text(in: .default, code: "error.unknown")
        }
    }

    /// Explicitly restores the pending-deletion activity and chooses it.
    /// No outbox row is created (the deletion was never committed).
    func restorePendingDeletion() async {
        guard let pending = pendingRestore else { return }
        do {
            if let restored = try await service.store.restorePendingDeletionActivity(named: pending.name) {
                activities = try await service.store.activities()
                pendingRestore = nil
                select(restored)
            } else {
                // The buffer row is gone (restored elsewhere or the app
                // restarted and it committed): fall back
                // to ordinary creation.
                pendingRestore = nil
                await quickCreateFromSearch()
            }
        } catch {
            search.errorMessage = L10n.text(in: .default, code: "error.unknown")
        }
    }

    private func refreshPendingDeletion() {
        let trimmed = search.trimmedQuery
        guard !trimmed.isEmpty else {
            pendingDeletion = nil
            return
        }
        Task {
            pendingDeletion = try? await service.store.pendingDeletionActivity(named: trimmed)
        }
    }

    // MARK: - Helpers

    private func refreshValidDuration() {        let duration = endsAt.timeIntervalSince(startsAt)
        if duration > 0 {
            lastValidDuration = duration
        }
    }

    /// Floors a date down to the granularity boundary.
    static func floored(_ date: Date, toMinutes minutes: Int = startGranularityMinutes) -> Date {
        let step = Double(minutes * 60)
        let interval = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: floor(interval / step) * step)
    }
}
