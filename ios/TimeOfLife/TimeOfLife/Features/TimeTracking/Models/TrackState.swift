import Foundation

/// Pure, testable state machine for the Track capture flow
/// (timer-capture-experience spec). The view model owns transitions; this
/// type has no UIKit or persistence dependencies.
enum TrackState: Equatable {
    /// No activity selected and no timer running.
    case idle
    /// An activity is prepared; an explicit Start is the only way to begin.
    case ready(Activity)
    /// The timer is running against a prepared activity.
    case running(Activity, startedAt: Date)
    /// Stop was activated; the completed entry is being saved locally.
    case saving(Activity, startedAt: Date)
    /// The entry was saved; a brief confirmation is shown, then the same
    /// activity returns to ready.
    case saved(Activity, duration: TimeInterval)
    /// A recoverable save failure: running state is preserved so the user
    /// can retry Stop without losing elapsed time.
    case error(Activity, startedAt: Date)

    var activity: Activity? {
        switch self {
        case .idle: nil
        case let .ready(activity), let .running(activity, _), let .saving(activity, _),
             let .saved(activity, _), let .error(activity, _): activity
        }
    }

    /// True while the timer is running or a recoverable error preserves it.
    var isRunning: Bool {
        switch self {
        case .running, .error: true
        default: false
        }
    }

    var isSaving: Bool {
        if case .saving = self { return true }
        return false
    }

    /// The exact elapsed duration at `now` for the current state.
    func elapsed(at now: Date) -> TimeInterval {
        switch self {
        case let .running(_, startedAt), let .saving(_, startedAt), let .error(_, startedAt):
            return max(0, now.timeIntervalSince(startedAt))
        case let .saved(_, duration):
            return duration
        case .idle, .ready:
            return 0
        }
    }
}

extension TrackState {
    /// VoiceOver label for the numeric readout (timer-capture-experience spec):
    /// announces the selected Activity, timer state, and elapsed duration.
    var readoutAccessibilityLabel: String {
        switch self {
        case .idle:
            return L10n.timerChooseActivityPrompt.text
        case let .ready(activity):
            return "\(activity.name), \(L10n.timerReady.text)"
        case let .running(activity, _), let .saving(activity, _), let .error(activity, _):
            return String(format: L10n.timerCompactRunning.text, activity.name)
        case let .saved(activity, _):
            return "\(activity.name), \(L10n.timerSaved.text)"
        }
    }

    /// VoiceOver label for the compact timer (app-shell spec).
    var compactAccessibilityLabel: String {
        guard let activity = activity else { return L10n.timerCompactStop.text }
        return String(format: L10n.timerCompactRunning.text, activity.name)
    }
}
