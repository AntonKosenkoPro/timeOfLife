import Foundation

/// The built bundle's marketing version + build number for the Profile
/// version row (add-version-label-release): `1.0.0 (3)` on Release builds,
/// `1.0.0 (3) • Debug` on Debug builds. Version truth lives in
/// `project.yml` (`info.properties` + `CURRENT_PROJECT_VERSION`) — XcodeGen
/// merges it into `Info.plist` at generation time, so this helper only reads
/// the built bundle (same pattern as `AppConfig` reading `API_BASE_URL`).
enum AppVersion {
    /// Pure formatting core with explicit inputs, so tests can cover both
    /// configurations without depending on the running build's bundle keys.
    /// Missing bundle keys fall back to `"?"` (defensive only — a built app
    /// bundle always carries both keys).
    static func formatted(marketing: String?, build: String?, isDebug: Bool, debugSuffix: String) -> String {
        let base = "\(marketing ?? "?") (\(build ?? "?"))"
        guard isDebug else { return base }
        return "\(base) • \(debugSuffix)"
    }

    /// The version label for this build. Whether the `Debug` suffix is
    /// appended is a compile-time fact (`#if DEBUG`, matching the repo's
    /// `SWIFT_ACTIVE_COMPILATION_CONDITIONS: DEBUG` pattern), not a runtime
    /// config lookup.
    static var text: String {
        let marketing = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif
        return formatted(
            marketing: marketing,
            build: build,
            isDebug: isDebug,
            debugSuffix: L10n.profileVersionDebugSuffix.text
        )
    }
}
