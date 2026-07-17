import Foundation

/// App-wide configuration sourced from `Info.plist` / `Config.xcconfig`.
///
/// `API_BASE_URL` is injected into `Info.plist` via the `Config.xcconfig`
/// file and read here. The production build can point at a different host.
enum AppConfig {
    /// Base URL for the API (no trailing slash). Defaults to the dev backend.
    static let baseURL: URL = {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           !raw.isEmpty, let url = URL(string: raw) {
            return url
        }
        return URL(string: "http://127.0.0.1:8080")!
    }()
}