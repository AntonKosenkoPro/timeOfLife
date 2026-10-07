import Foundation

/// Cross-process "the timer stopped elsewhere" signal (live-activities
/// Stop path). The Stop intent runs in the widget extension process and the
/// app (foreground or suspended) must react instantly: Darwin notifications
/// need no entitlements and cross the process boundary where neither
/// `UserDefaults` suite reads (cfprefsd detaches) nor `ActivityKit`
/// enumeration (module-distinct attributes type — see `StopTimerIntent`)
/// can be relied on.
///
/// Compiles into BOTH targets (app posts nothing here — it observes; the
/// intent only posts). Payload is property-list-safe.
enum LiveActivitySignal {
    static let name = "com.antonkosenko.timeoflifeapp.timer-stopped-externally"
    static let durationKey = "durationSeconds"

    /// Posts the signal from the Stop intent after a successful save.
    static func post(durationSeconds: Int) {
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
