import Foundation

/// Pure, testable state machine for the Track capture flow
/// (timer-capture-experience spec). The view model owns transitions; this
/// type has no UIKit or persistence dependencies.
///
/// Identity is the trimmed exact text (case-sensitive: `Gym` ≠ `GYM`);
/// there is no Activity object anywhere. The draft's ordered categories are
/// inherited from the exact recents match at preparation time and stay live
/// while running.
enum TrackState: Equatable {
    /// A prepared (or running) capture: the locked trimmed text plus the
    /// ordered category draft.
    struct Draft: Equatable {
        let text: String
        var categoryIDs: [String]

        init(text: String, categoryIDs: [String] = []) {
            self.text = text
            self.categoryIDs = categoryIDs
        }
    }

    /// No name entered and no timer running.
    case idle
    /// A name is prepared; an explicit Start is the only way to begin.
    case ready(Draft)
    /// The timer is running against the prepared draft.
    case running(Draft, startedAt: Date)
    /// Stop was activated; the completed entry is being saved locally.
    case saving(Draft, startedAt: Date)
    /// The entry was saved; a brief confirmation is shown, then the same
    /// name returns to ready.
    case saved(Draft, duration: TimeInterval)
    /// A recoverable save failure: running state is preserved so the user
    /// can retry Stop without losing elapsed time.
    case error(Draft, startedAt: Date)

    var draft: Draft? {
        switch self {
        case .idle: nil
        case let .ready(draft), let .running(draft, _), let .saving(draft, _),
             let .saved(draft, _), let .error(draft, _): draft
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
    /// announces the prepared name, timer state, and elapsed duration.
    var readoutAccessibilityLabel: String {
        switch self {
        case .idle:
            return L10n.timerIdlePrompt.text
        case let .ready(draft):
            return "\(draft.text), \(L10n.timerReady.text)"
        case let .running(draft, _), let .saving(draft, _), let .error(draft, _):
            return String(format: L10n.timerCompactRunning.text, draft.text)
        case let .saved(draft, _):
            return "\(draft.text), \(L10n.timerSaved.text)"
        }
    }

    /// VoiceOver label for the compact timer (app-shell spec).
    var compactAccessibilityLabel: String {
        guard let draft = draft else { return L10n.timerCompactStop.text }
        return String(format: L10n.timerCompactRunning.text, draft.text)
    }
}
