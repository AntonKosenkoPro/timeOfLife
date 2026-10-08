import Foundation

/// Clock formatting for the Live Activity faces.
///
/// Lives in Shared (compiled into the widget extension) instead of reusing
/// `DurationFormatting` because that file's sync-age tail depends on
/// `SyncAgeBucket` (Sync feature) — the extension must stay
/// dependency-light (design D4). If the clock grammar ever changes, update
/// both together.
enum TimerClock {
    /// Clock duration: `HH:MM:SS` past the hour, else `MM:SS`, zero-padded.
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
    /// `12:34`, `1:23:45`) — matches what `Text(timerInterval:)` renders.
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

    /// Coarse Always-on-style reading (`0:--`, `12:--`, `1:23:--`): the
    /// live style with the seconds masked. Mirrors Apple Timer's AoD face,
    /// which likewise shows hours/minutes statically rather than ticking
    /// seconds the dimmed renderer cannot sustain.
    static func maskedCoarse(_ totalSeconds: Int) -> String {
        let live = liveStyle(totalSeconds)
        return String(live.dropLast(2)) + "--"
    }
}
