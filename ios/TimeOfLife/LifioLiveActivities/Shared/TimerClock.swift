import Foundation

/// Clock formatting for the Live Activity faces, mirroring
/// `DurationFormatting.clock` grammar exactly (`MM:SS`, `H:MM:SS` past the
/// hour, zero-padded, clamped at zero).
///
/// Lives in Shared (compiled into the widget extension) instead of reusing
/// `DurationFormatting` because that file's sync-age tail depends on
/// `SyncAgeBucket` (Sync feature) — the extension must stay
/// dependency-light (design D4). If the clock grammar ever changes, update
/// both together.
enum TimerClock {
    static func formatted(_ totalSeconds: Int) -> String {
        let total = max(0, totalSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        let paddedMinutes = String(format: "%02d", minutes)
        let paddedSeconds = String(format: "%02d", seconds)
        if hours > 0 {
            return "\(hours):\(paddedMinutes):\(paddedSeconds)"
        }
        return "\(paddedMinutes):\(paddedSeconds)"
    }

    /// Live-style duration with the leftmost unit unpadded (`0:01`,
    /// `12:34`, `1:23:45`) — matches what `Text(timerInterval:)` renders,
    /// so the hidden sizing twin and the live view share one format and
    /// the bordered capsule hugs the digits.
    static func liveStyle(_ totalSeconds: Int) -> String {
        let total = max(0, totalSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        let paddedMinutes = String(format: "%02d", minutes)
        let paddedSeconds = String(format: "%02d", seconds)
        if hours > 0 {
            return "\(hours):\(paddedMinutes):\(paddedSeconds)"
        }
        return "\(minutes):\(paddedSeconds)"
    }
}
