import Foundation

/// Cross-process "the timer stopped elsewhere" signal (live-activities
/// Stop path). The Stop intent runs in the widget extension process and the
/// app (foreground or background-alive) must react promptly: Darwin
/// notifications need no entitlements and cross the process boundary where
/// neither suite `UserDefaults` reads (cfprefsd detaches) nor `ActivityKit`
/// enumeration can be relied on — the extension's `activities` is always
/// empty even with a unified attributes type (device-proven: the daemon
/// scopes enumeration by calling process, so ending stays app-side).
///
/// Name-only: Darwin notifications ignore `object`/`userInfo` (Apple docs:
/// "If center is a Darwin notification center, this value is ignored"), so
/// no duration rides along — the app resolves the Saved duration from the
/// saved entry itself (entry-recency heuristic in `TimerService`).
///
/// Lives in the shared framework so both processes resolve one symbol.
public enum LiveActivitySignal {
    public static let name = "com.antonkosenko.timeoflifeapp.timer-stopped-externally"

    /// Posts the signal from the Stop intent after a successful save.
    public static func post() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(rawValue: name as CFString),
            nil,
            nil,
            true
        )
    }
}
