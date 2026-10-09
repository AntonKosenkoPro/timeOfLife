import Foundation

/// The Live Activity deep-link contract (live-activities D5): every face
/// navigates to Track on tap. Single source of truth shared by the widget
/// (constructs `trackURL` for `widgetURL`) and the app (`DeepLink.parse`
/// matches against the same scheme/host) — a hand-synced string literal
/// on each side would silently kill every tap on drift.
public enum LiveActivityDeepLink {
    public static let trackScheme = "lifio"
    public static let trackHost = "track"

    public static var trackURL: URL? {
        URL(string: "\(trackScheme)://\(trackHost)")
    }
}
