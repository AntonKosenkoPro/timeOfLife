import Foundation

/// Localized copy for the Live Activity faces (live-activities spec:
/// "Island and banner presentations").
///
/// Lives in the shared `LifioLiveActivityCore` framework (linked by the app
/// and the widget extension). Reads the SHARED `Localizable.strings`
/// (shipped in the extension bundle as resources — single source, no
/// duplication): the parameterless accessors resolve against the host's
/// main bundle at runtime in each process (appex bundle in the extension,
/// app bundle in the app) — system locale. The `localeIdentifier:`
/// overloads resolve against that locale's `.lproj` in the host bundle
/// explicitly: widget faces MUST use them with
/// `TimerActivityAttributes.localeIdentifier`, because the appex process
/// never sees the app's in-process request-locale override and may cache
/// a prior run's language. Keys are literals here because the app's `L10n`
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

    /// Request-locale Stop title: explicit `.lproj` lookup, falling back
    /// to the system `stopTitle` when the locale bundle or key is missing
    /// (never returns the raw key).
    public static func stopTitle(localeIdentifier: String, in hostBundle: Bundle = .main) -> String {
        LiveActivityLocale.localizedString("timer.stop", localeIdentifier: localeIdentifier, in: hostBundle)
            ?? stopTitle
    }

    /// Request-locale Stop accessibility label, same fallback rule.
    public static func stopAccessibilityLabel(localeIdentifier: String, in hostBundle: Bundle = .main) -> String {
        LiveActivityLocale.localizedString("timer.compactStop", localeIdentifier: localeIdentifier, in: hostBundle)
            ?? stopAccessibilityLabel
    }

    /// Request-locale running-state accessibility label, same fallback rule.
    public static func runningAccessibilityLabel(text: String, localeIdentifier: String, in hostBundle: Bundle = .main) -> String {
        if let format = LiveActivityLocale.localizedString("timer.compactRunning", localeIdentifier: localeIdentifier, in: hostBundle) {
            return String(format: format, text)
        }
        return runningAccessibilityLabel(text: text)
    }

    /// Request-locale Saved end-card title, same fallback rule.
    public static func savedCardTitle(duration: String, localeIdentifier: String, in hostBundle: Bundle = .main) -> String {
        if let format = LiveActivityLocale.localizedString("activity.savedWithDuration", localeIdentifier: localeIdentifier, in: hostBundle) {
            return String(format: format, duration)
        }
        return savedCardTitle(duration: duration)
    }
}

/// Explicit-locale bundle resolution for the widget faces (Foundation
/// only, extension-safe). The host bundle is `Bundle.main` in each
/// process (appex bundle in the extension, app bundle in the app and in
/// tests) — both ship the same five `.lproj` resources (pinned by
/// `LocalizationTests.appexShipsAllLocales`).
public enum LiveActivityLocale {
    /// The request locale's `.lproj` bundle, or nil when unresolvable
    /// (callers fall back to system resolution — never crash).
    public static func bundle(for localeIdentifier: String, in hostBundle: Bundle = .main) -> Bundle? {
        guard let path = hostBundle.path(forResource: localeIdentifier, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return nil }
        return bundle
    }

    /// Request-locale string for `key`, or nil to keep system behavior
    /// (unresolvable bundle or missing key — a value equal to the key
    /// counts as missing, mirroring `L10n` fallback).
    public static func localizedString(_ key: String, localeIdentifier: String, in hostBundle: Bundle = .main) -> String? {
        guard let bundle = bundle(for: localeIdentifier, in: hostBundle) else { return nil }
        let value = NSLocalizedString(key, bundle: bundle, comment: "")
        return value == key ? nil : value
    }
}
