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
/// Lives in the shared framework so both processes resolve one symbol.
/// Payload is property-list-safe.
public enum LiveActivitySignal {
    public static let name = "com.antonkosenko.timeoflifeapp.timer-stopped-externally"
    public static let durationKey = "durationSeconds"

    /// Posts the signal from the Stop intent after a successful save.
    public static func post(durationSeconds: Int) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        // swiftlint:disable:next legacy_objc_type
        let userInfo = [durationKey: NSNumber(value: durationSeconds)] as CFDictionary
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(rawValue: name as CFString),
            nil,
            userInfo,
            true
        )
    }
}
