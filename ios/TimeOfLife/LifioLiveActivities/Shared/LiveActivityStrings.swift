import Foundation

/// Localized copy for the Live Activity faces (live-activities spec:
/// "Island and banner presentations").
///
/// Reads the SHARED `Localizable.strings` (shipped in the extension bundle
/// as resources — single source, no duplication): `NSLocalizedString`
/// resolves against the extension's bundle at runtime in each process.
/// Keys are literals here because the app's `L10n` enum cannot compile
/// into the extension (it depends on `CatalogIcon`/UIKit).
enum LiveActivityStrings {
    /// Stop button title (shared `timer.stop`: "Stop" / "Стоп").
    static var stopTitle: String {
        NSLocalizedString("timer.stop", comment: "")
    }

    /// Stop button accessibility label (shared `timer.compactStop`).
    static var stopAccessibilityLabel: String {
        NSLocalizedString("timer.compactStop", comment: "")
    }

    /// Running-state accessibility label for the faces
    /// (shared `timer.compactRunning`: "%@, timer running").
    static func runningAccessibilityLabel(text: String) -> String {
        String(format: NSLocalizedString("timer.compactRunning", comment: ""), text)
    }

    /// Saved end-card title (own `activity.savedWithDuration`, also
    /// declared in `L10n` so `LocalizationTests` pins both bundles).
    static func savedCardTitle(duration: String) -> String {
        String(format: NSLocalizedString("activity.savedWithDuration", comment: ""), duration)
    }
}
