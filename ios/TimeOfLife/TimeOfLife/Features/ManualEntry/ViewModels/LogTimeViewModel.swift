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
/// unified entry form (entry-editor spec): a validated name + categories +
/// notes + start/end draft that saves a committed manual entry in CREATE
/// mode, updates an existing `manual` entry in EDIT mode, or exposes an
/// imported entry read-only in LOCKED mode.
///
/// The draft is fully local: Start defaults to now floored to 5 minutes,
/// End to Start + 1h. Moving Start at/past End auto-pushes End to preserve
/// the last valid duration (Calendar behavior); moving End never moves
/// Start. Add/Save is a validity gate (`isAddEnabled`): the trimmed name
/// must be non-empty and End must be strictly after Start. There is no
/// activity re-resolve — entries own their text (remove-activities-layer).
/// Persistence delegates to `TimerService`'s store (`LocalStore.createEntry`
/// + transactional outbox for CREATE, LWW `LocalStore.updateEntry` for
/// EDIT); overlaps and future end-times are allowed, matching store
/// semantics.
@MainActor
final class LogTimeViewModel: ObservableObject {
    /// Default duration for a fresh sheet and the fallback when the
    /// previous duration is unknown or invalid.
    static let defaultDuration: TimeInterval = 3_600
    /// Start-time flooring granularity, in minutes.
    static let startGranularityMinutes = 5

    @Published var name: String
    /// The ordered category selection (TagSelector parent owns order).
    @Published private(set) var categoryIDs: [String]
    /// The full category catalog for the TagSelector options, loaded once
    /// on open.
    @Published private(set) var availableCategories: [Category] = []
    @Published var notes: String
    @Published private(set) var startsAt: Date
    @Published private(set) var endsAt: Date
    @Published var errorMessage: String?
    /// The entry being corrected in EDIT mode or shown in LOCKED mode
    /// (nil in CREATE mode).
    @Published private(set) var editingEntry: TimeEntry?

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
        initialText: String = "",
        initialCategoryIDs: [String] = [],
        editing entry: TimeEntry? = nil,
        now: Date = Date()
    ) {
        self.service = service
        self.editingEntry = entry
        if let entry {
            // EDIT/LOCKED prefill straight from the entry's own fields —
            // there is no activity to re-resolve. The form never receives an
            // in-progress entry (no entry point lists one); a nil end falls
            // back to the default duration defensively.
            self.name = entry.activityText
            self.categoryIDs = entry.categoryIDs
            self.notes = entry.notes
            self.startsAt = entry.startedAt
            self.endsAt = entry.endedAt ?? entry.startedAt.addingTimeInterval(Self.defaultDuration)
            let duration = endsAt.timeIntervalSince(startsAt)
            self.lastValidDuration = duration > 0 ? duration : Self.defaultDuration
        } else {
            let start = Self.floored(now)
            self.name = initialText
            self.categoryIDs = initialCategoryIDs
            self.notes = ""
            self.startsAt = start
            self.endsAt = start.addingTimeInterval(Self.defaultDuration)
        }
    }

    /// The trimmed name.
    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when the trimmed name is non-empty and End is strictly after
    /// Start.
    var isAddEnabled: Bool {
        !trimmedName.isEmpty && endsAt > startsAt
    }

    /// Loads the category catalog for the TagSelector (idempotent). Called
    /// on open by the view.
    func loadCategoriesIfNeeded(store: LocalStore) async {
        guard availableCategories.isEmpty else { return }
        availableCategories = (try? await store.categories()) ?? []
    }

    /// Toggles a category on the ordered selection (TagSelector parent owns
    /// order: toggling appends or removes, keeping the selection order).
    func toggleCategory(_ categoryID: String) {
        if let index = categoryIDs.firstIndex(of: categoryID) {
            categoryIDs.remove(at: index)
        } else {
            categoryIDs.append(categoryID)
        }
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
    /// persistence fails, or (EDIT) the record changed underneath (stale
    /// write). LOCKED mode has no confirm path and always returns false.
    func save() async -> Bool {
        guard mode != .locked else { return false }
        guard !trimmedName.isEmpty, endsAt > startsAt else { return false }
        do {
            if let editing = editingEntry, mode == .edit {
                let updated = TimeEntry(
                    id: editing.id,
                    activityText: trimmedName,
                    startedAt: startsAt,
                    endedAt: endsAt,
                    durationSeconds: max(0, Int(endsAt.timeIntervalSince(startsAt))),
                    source: editing.source,
                    sourceRef: editing.sourceRef,
                    categoryIDs: categoryIDs,
                    notes: notes,
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
                activityText: trimmedName,
                startedAt: startsAt,
                endedAt: endsAt,
                durationSeconds: max(0, Int(endsAt.timeIntervalSince(startsAt))),
                source: "manual",
                categoryIDs: categoryIDs,
                notes: notes
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

    // MARK: - Helpers

    private func refreshValidDuration() {
        let duration = endsAt.timeIntervalSince(startsAt)
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
