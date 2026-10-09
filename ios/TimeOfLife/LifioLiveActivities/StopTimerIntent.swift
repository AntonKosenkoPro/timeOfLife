import AppIntents
import Foundation
import OSLog

import LifioLiveActivityCore

/// Stops the running timer from the Live Activity (live-activities spec:
/// "Stop and return actions").
///
/// Mirrors `TimerService.stopTimerDraft` through the same `LocalStore`
/// chokepoint — same `source='manual'` save, same outbox row — because the
/// app process may be suspended while the intent runs in the extension
/// process. If `TimerService.stopTimerDraft` changes, update this in step.
///
/// The intent does NOT end the activity itself: `ActivityKit` enumeration is
/// scoped by calling process — the extension's `activities` is always empty
/// even with the attributes type unified in `LifioLiveActivityCore`
/// (device-proven). Instead it posts `LiveActivitySignal`, and the app ends
/// the activity with the Saved card on contact (Darwin handler when
/// background-alive, foreground/load sweep otherwise).
///
/// `requiresLocalDeviceAuthentication`: a locked-phone tap demands Face ID /
/// passcode first (pocket-stop protection); unlocked it runs immediately.
/// With no active account file, an unreadable store, or no running draft,
/// it returns success having written nothing and created no file
/// (spec: "Stop fails gracefully").
struct StopTimerIntent: AppIntent {
    // A literal: the metadata processor only accepts literals here, and at
    // runtime it resolves as a key against the extension's shared
    // Localizable.strings ("Stop" / "Стоп").
    static var title: LocalizedStringResource { "timer.stop" }

    // Pocket-stop protection (spec flow): the banner/island Stop is
    // dimmed-disabled on AoD, and this policy makes a locked-phone tap
    // demand Face ID / passcode first — while an unlocked tap runs
    // immediately and the activity disappears via direct end. `alwaysAllowed`
    // would let a pocket tap through the (woken) lock screen.
    static var authenticationPolicy: IntentAuthenticationPolicy {
        .requiresLocalDeviceAuthentication
    }

    func perform() async throws -> some IntentResult {
        guard case .ready(let url) = ActiveAccountFileResolver().resolve() else {
            Self.logger.info("StopTimerIntent ignored: no active account file")
            return .result()
        }
        guard let store = try? LocalStore(url: url) else {
            // Locked keybag with pre-fix file protection, or a damaged
            // file: the draft is untouched, retry from the app unlocked.
            Self.logger.info("StopTimerIntent ignored: store open failed")
            return .result()
        }
        guard let draft = try? await store.timerDraft(),
              !draft.activityText.isEmpty else {
            Self.logger.info("StopTimerIntent ignored: no running draft")
            return .result()
        }
        let startedAt = draft.startedAt ?? Date()
        let endedAt = Date()
        let durationSeconds = max(0, Int(endedAt.timeIntervalSince(startedAt)))
        let existingIDs = Set((try? await store.categories().map(\.id)) ?? [])
        let pruned = draft.categoryIDs.filter { existingIDs.contains($0) }
        let entry = TimeEntry(
            id: await store.newRecordID(),
            activityText: draft.activityText,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            source: "manual",
            categoryIDs: pruned,
            notes: draft.notes
        )
        guard (try? await store.createEntry(entry)) != nil,
              (try? await store.clearTimerDraft()) != nil else {
            // Recoverable: the draft is untouched, so the user can retry
            // from the app (mirrors the in-app `.error` grammar).
            Self.logger.error("StopTimerIntent failed: entry save or draft clear threw")
            return .result()
        }
        // Signal, don't end: enumeration stays app-side (see type docs).
        // The duration rides along so the Saved card shows the true value.
        LiveActivitySignal.post(durationSeconds: durationSeconds)
        Self.logger.info("StopTimerIntent saved entry with duration")
        return .result()
    }

    private static let logger = Logger(
        subsystem: "com.antonkosenko.timeoflifeapp",
        category: "StopTimerIntent"
    )
}
