import Foundation

/// Localized copy for the Live Activity faces (live-activities spec:
/// "Island and banner presentations").
///
/// Lives in the shared `LifioLiveActivityCore` framework (linked by the app
/// and the widget extension). Reads the SHARED `Localizable.strings`
/// (shipped in the extension bundle as resources — single source, no
/// duplication): `NSLocalizedString` resolves against the host's main
/// bundle at runtime in each process (appex bundle in the extension, app
/// bundle in the app). Keys are literals here because the app's `L10n`
/// enum cannot link into the extension (it depends on
/// `CatalogIcon`/UIKit). Extension-safe: Foundation only.
public enum LiveActivityStrings {
    /// Stop button title (shared `timer.stop`: "Stop" / "Стоп").
    public static var stopTitle: String {
        NSLocalizedString("timer.stop", comment: "")
    }

    /// Stop button accessibility label (shared `timer.compactStop`).
    public static var stopAccessibilityLabel: String {
        NSLocalizedString("timer.compactStop", comment: "")
    }

    /// Running-state accessibility label for the faces
    /// (shared `timer.compactRunning`: "%@, timer running").
    public static func runningAccessibilityLabel(text: String) -> String {
        String(format: NSLocalizedString("timer.compactRunning", comment: ""), text)
    }

    /// Saved end-card title (own `activity.savedWithDuration`, also
    /// declared in `L10n` so `LocalizationTests` pins both bundles).
    public static func savedCardTitle(duration: String) -> String {
        String(format: NSLocalizedString("activity.savedWithDuration", comment: ""), duration)
    }
}
