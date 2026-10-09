import Foundation
import UIKit

/// Orchestrates the timer against the local database (local-first-store spec).
///
/// The service is the single entry point for view models. It writes only to
/// `LocalStore` — the device is the source of truth. Remote propagation is the
/// responsibility of the background `SyncController` (the outbox row is
/// written in the same transaction as the state change), so there is no
/// remote-push path here.
@MainActor
final class TimerService: ObservableObject {
    let store: LocalStore
    private let liveActivities: LiveActivityControlling

    init(
        store: LocalStore,
        liveActivities: LiveActivityControlling = LiveActivityService {
            UIApplication.shared.applicationState == .active
        }
    ) {
        self.store = store
        self.liveActivities = liveActivities
    }

    /// Starts (or rewrites) the persisted running draft for the given
    /// trimmed text, ordered category snapshot, and notes snapshot (D3/D4)
    /// so it survives a crash and is readable by widgets and lock-screen
    /// Controls.
    ///
    /// Also mirrors the run on the Live Activity (live-activities spec):
    /// the singleton guard inside makes rewrites (mid-run retags, crash
    /// relaunches with the same text) safe no-ops.
    func startTimerDraft(text: String, categoryIDs: [String], notes: String = "", startedAt: Date = Date()) async throws {
        try await store.saveTimerDraft(activityText: text, categoryIDs: categoryIDs, startedAt: startedAt, notes: notes)
        await liveActivities.runStarted(
            text: text,
            iconSymbol: firstIconSymbol(for: categoryIDs),
            startedAt: startedAt
        )
    }

    /// Rewrites only the persisted running draft's live notes snapshot (a
    /// mid-run notes save). The locked text, categories, and `started_at`
    /// are untouched.
    func updateTimerDraftNotes(_ notes: String) async throws {
        try await store.updateTimerDraftNotes(notes)
    }

    /// The persisted running-timer draft, or nil when no timer is running.
    /// Read on app launch to resume the running-timer UI after a crash or
    /// relaunch (local-first-store spec).
    func runningTimerDraft() async throws -> RunningTimerDraft? {
        try await store.timerDraft()
    }

    /// Stops the running timer: saves the completed entry (with
    /// `source='manual'` and the draft's final notes) in one transaction
    /// with its single outbox row and clears the persisted running draft.
    /// Category ids that vanished mid-run (deleted elsewhere while timing)
    /// are pruned with the remainder kept — a stop never fails on a dead tag.
    ///
    /// Also ends the Live Activity with the Saved card (live-activities
    /// spec) — every Stop path (Track, compact timer, retry, Island intent)
    /// flows through here, so this is the single end call site.
    func stopTimerDraft(text: String, categoryIDs: [String], startedAt: Date, endedAt: Date = Date(), notes: String = "") async throws {
        let existing = Set(try await store.categories().map(\.id))
        let pruned = categoryIDs.filter { existing.contains($0) }
        let durationSeconds = Int(endedAt.timeIntervalSince(startedAt))
        let entry = TimeEntry(
            id: await store.newRecordID(),
            activityText: text,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            source: "manual",
            categoryIDs: pruned,
            notes: notes
        )
        try await store.createEntry(entry)
        try await store.clearTimerDraft()
        await liveActivities.runEnded(startedAt: startedAt, durationSeconds: durationSeconds)
    }

    /// Re-mirrors an already-persisted run on the Live Activity without
    /// touching the draft (cold-start/restore path: `load()` revives
    /// `.running` from storage, and a fresh `request()` is the only thing
    /// that brings the Island back — restores never pass through
    /// `beginRunning`). The singleton guard inside makes repeats and
    /// already-live activities safe no-ops. Never throws: ActivityKit
    /// failures must not break loading Track.
    func refreshLiveActivity(text: String, categoryIDs: [String], startedAt: Date) async {
        await liveActivities.runStarted(
            text: text,
            iconSymbol: firstIconSymbol(for: categoryIDs),
            startedAt: startedAt
        )
    }
    /// Ends live activities whose persisted draft is gone (stopped from
    /// the Island — the intent can't end them itself, so the app reaps
    /// them on contact: Darwin signal, foreground, load-reconcile). A
    /// present draft means the run is genuinely active: nothing is
    /// orphaned, nothing ends. Never throws.
    ///
    /// Fail-closed on read errors: `try? … == nil` would mistake a
    /// transient DB failure for "no draft" and dismiss a live Island —
    /// the exact blank-island report from the device.
    func endOrphanedActivities(knownDurationSeconds: Int? = nil) async {
        let draft: RunningTimerDraft?
        do {
            draft = try await store.timerDraft()
        } catch {
            return
        }
        guard draft == nil else { return }
        await liveActivities.endOrphanedActivities(knownDurationSeconds: knownDurationSeconds)
    }

    /// The first-position category's display icon for the Live Activity
    /// (recents-chip rule), or `"timer"` when the run has no categories
    /// or the category is unknown locally.
    private func firstIconSymbol(for categoryIDs: [String]) async -> String {
        guard let firstID = categoryIDs.first,
              let match = (try? await store.categories())?.first(where: { $0.id == firstID })
        else { return "timer" }
        return CatalogIcon(validated: match.icon).displaySymbol
    }
}
