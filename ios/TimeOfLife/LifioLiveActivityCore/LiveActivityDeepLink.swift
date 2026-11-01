import Foundation

/// The Live Activity deep-link contract (live-activities D5): every face
/// navigates to Track on tap. Single source of truth shared by the widget
/// (constructs `trackURL` for `widgetURL`) and the app (`DeepLink.parse`
/// matches against the same scheme/host) — a hand-synced string literal
/// on each side would silently kill every tap on drift.
public enum LiveActivityDeepLink {
    public static let trackScheme = "lifio"
    public static let trackHost = "track"
    /// Query flag marking a Track link as an Island-Stop request
    /// (fix-terminated-stop-saved-face Spike D): the widget's Stop pill is
    /// a `Link` here, and the app stops the timer itself on open — the only
    /// mechanism that repaints the activity with the app dead.
    public static let stopQueryKey = "stop"
    public static let stopQueryValue = "1"

    /// Checked construction: these literals are fixed, so a nil here is a
    /// programmer error, not a runtime fallback case.
    public static var trackURL: URL {
        guard let url = URL(string: "\(trackScheme)://\(trackHost)") else {
            preconditionFailure("LiveActivityDeepLink.trackURL is not a valid URL")
        }
        return url
    }

    public static var stopURL: URL {
        guard let url = URL(string: "\(trackScheme)://\(trackHost)?\(stopQueryKey)=\(stopQueryValue)") else {
            preconditionFailure("LiveActivityDeepLink.stopURL is not a valid URL")
        }
        return url
    }
}
