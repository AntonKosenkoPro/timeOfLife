import ActivityKit
import Foundation

/// ActivityKit attributes for the running-timer Live Activity
/// (live-activities spec: "Live Activity follows the running timer").
///
/// The file compiles into BOTH the app target (which requests/ends the
/// activity from `TimerService`) and the widget extension (which renders
/// it) — so it depends only on Foundation + ActivityKit, never on app
/// modules (`LocalStore`, `Theme`, `L10n`). Data only: all copy lives in
/// the extension's views (localized in 3.4).
public struct TimerActivityAttributes: ActivityAttributes, Equatable {
    /// The exact entry text, verbatim. Identity is trimmed exact text
    /// (case-sensitive: `Gym` ≠ `GYM`) — faces truncate to one line but
    /// never normalize.
    public var entryText: String
    /// SF Symbol name of the first-position category icon, or `"timer"`
    /// when the run has no categories (the recents-chip rule: icon or
    /// nothing — never names).
    public var iconSymbol: String

    public init(entryText: String, iconSymbol: String) {
        self.entryText = entryText
        self.iconSymbol = iconSymbol
    }

    /// The live slice. Faces tick from `startedAt` via the system's
    /// `Text(timerInterval:)` — no per-second `update()` calls (D1).
    public struct ContentState: Codable, Hashable {
        /// When the run started.
        public var startedAt: Date
        /// Final duration for the Saved end-card; nil while running.
        public var savedDurationSeconds: Int?

        public init(startedAt: Date, savedDurationSeconds: Int? = nil) {
            self.startedAt = startedAt
            self.savedDurationSeconds = savedDurationSeconds
        }
    }
}
