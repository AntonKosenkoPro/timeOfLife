import Foundation

/// Deep links into the app (live-activities change: every Live Activity
/// face taps `lifio://track`). Pure parsing — navigation effects live in
/// `AppNavigationStack` (`requestTrack`) so this stays unit-testable with
/// no SwiftUI dependency.
enum DeepLink: Equatable {
    /// Select the Track tab (the running timer lives there).
    case track

    /// Parses an incoming URL, or nil when it is not a known link
    /// (unknown links are ignored — never routed, never crashed on).
    static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme == "lifio", url.host == "track" else { return nil }
        return .track
    }
}
