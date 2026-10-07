// ActivityKit's `Activity`/`ActivityContent` are not Sendable on this
// SDK, so iterating `activities` and awaiting `end` trips Swift 6 region
// isolation under the repo's `complete` checking. The preconcurrency
// import scopes the relaxation to this file only.
@preconcurrency import ActivityKit
import Foundation
import OSLog

/// Controls the running-timer Live Activity (live-activities spec:
/// "Live Activity follows the running timer").
///
/// The protocol keeps every layer replaceable in tests: production wires
/// the real `LiveActivityService`, tests inject a fake. All methods are
/// fire-and-forget from the caller's view — ActivityKit failures never
/// fail the timer itself (spec: starting succeeds with no activity when
/// disabled).
@MainActor
protocol LiveActivityControlling: Sendable {
    /// Mirrors a timer start on the Island/banner. No-op when an activity
    /// for the same exact text is already live (singleton guard).
    func runStarted(text: String, iconSymbol: String, startedAt: Date) async
    /// Ends every live timer activity with the Saved card. No-op when
    /// none is live (idempotent — covers app/intent double stops).
    func runEnded(startedAt: Date, durationSeconds: Int) async
}

/// No-op implementation for previews and tests that must not touch
/// ActivityKit.
@MainActor
final class NoopLiveActivityController: LiveActivityControlling {
    func runStarted(text: String, iconSymbol: String, startedAt: Date) async {}
    func runEnded(startedAt: Date, durationSeconds: Int) async {}
}

/// The real ActivityKit implementation (D1/D2/D6).
///
/// - Request is foreground-only (ActivityKit rejects background requests),
///   gated on `areActivitiesEnabled`, and singleton-guarded: a live
///   activity for the same text is reused, a stale one for another text is
///   ended first (the draft survives crashes, so a relaunch must not
///   duplicate the Island).
/// - End is allowed from any state (foreground or background — the Stop
///   intent fires while locked) with the Saved card and the tuned
///   `.after` dismissal (D6).
/// - `staleDate` is nil: faces tick on-system via `Text(timerInterval:)`
///   with zero `update()` calls, so there is nothing to go stale.
@MainActor
final class LiveActivityService: LiveActivityControlling {
    /// Starting point for the Saved-card dismissal delay (D6); tuned
    /// on-device in task 5.1.
    static let dismissalDelaySeconds = 6.0

    private static let logger = Logger(
        subsystem: "com.antonkosenko.timeoflifeapp",
        category: "LiveActivityService"
    )

    /// Foreground probe. Injected (not defaulted) because the app and the
    /// extension observe foreground differently — and `UIApplication` is
    /// unavailable in extensions, so this file must not reference it: the
    /// app passes the real probe at its call site, the Stop intent passes
    /// `{ true }` (it only ends, which needs no gate).
    private let isForeground: () -> Bool

    init(isForeground: @escaping () -> Bool) {
        self.isForeground = isForeground
    }

    func runStarted(text: String, iconSymbol: String, startedAt: Date) async {
        let liveCount = Activity<TimerActivityAttributes>.activities.count
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Self.logger.info("request skipped: activities disabled")
            return
        }
        guard isForeground() else {
            Self.logger.info("request skipped: not foreground")
            return
        }
        let live = Activity<TimerActivityAttributes>.activities
        if live.contains(where: { $0.attributes.entryText == text }) { return }
        for activity in live {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        let attributes = TimerActivityAttributes(entryText: text, iconSymbol: iconSymbol)
        let state = TimerActivityAttributes.ContentState(startedAt: startedAt)
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            Self.logger.info("request ok liveBefore=\(liveCount) id=\(activity.id)")
        } catch {
            // Never fail the timer: starting succeeds with no activity.
            Self.logger.error("request threw \(String(describing: error)) liveBefore=\(liveCount)")
        }
    }

    func runEnded(startedAt: Date, durationSeconds: Int) async {
        let live = Activity<TimerActivityAttributes>.activities
        Self.logger.info("end: liveCount=\(live.count)")
        let final = TimerActivityAttributes.ContentState(
            startedAt: startedAt,
            savedDurationSeconds: durationSeconds
        )
        for activity in live {
            await activity.end(
                .init(state: final, staleDate: nil),
                dismissalPolicy: .after(.now + Self.dismissalDelaySeconds)
            )
        }
    }
}
