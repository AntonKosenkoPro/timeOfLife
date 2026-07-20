import Foundation

/// Formats `TimeInterval` values into user-facing duration strings.
enum TimeFormatter {
    /// Formats a duration as `HH:MM:SS` when an hour or more has elapsed,
    /// otherwise `MM:SS`. Always zero-pads each segment.
    static func formattedDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        let paddedMinutes = String(format: "%02d", minutes)
        let paddedSeconds = String(format: "%02d", seconds)

        if hours > 0 {
            return "\(hours):\(paddedMinutes):\(paddedSeconds)"
        }
        return "\(paddedMinutes):\(paddedSeconds)"
    }
}
