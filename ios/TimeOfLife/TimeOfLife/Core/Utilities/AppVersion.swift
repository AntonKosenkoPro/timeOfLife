import Foundation

/// The built bundle's marketing version + commit SHA + release channel for
/// the Profile version label (manual-tag-releases): `v0.3.0 (a1b2c3d)` on
/// public Release builds, `v0.2.7 (a1b2c3d) • Internal` on internal-channel
/// builds, `v0.0.0-dev (a1b2c3d) • Debug` on Debug builds (the channel and
/// debug suffixes stack when both apply). The `v` prefix marks the digits as
/// build metadata. Marketing-version truth lives in `project.yml`
/// (`info.properties`, stamped at build time by `ci_post_clone.sh` from the
/// release tag); the SHA is stamped at build time by the
/// `Stamp GIT_COMMIT_SHA` Run Script Phase (`git rev-parse --short=7 HEAD`,
/// fallback `"?"`) into the built bundle's `GIT_COMMIT_SHA` key — same
/// read-the-built-bundle pattern as `AppConfig` reading `API_BASE_URL`.
/// `CFBundleVersion` / `CURRENT_PROJECT_VERSION` keep incrementing for App
/// Store Connect uploads but are no longer displayed.
enum AppVersion {
    /// Pure formatting core with explicit inputs, so tests can cover every
    /// configuration without depending on the running build's bundle keys.
    /// Missing bundle keys fall back to `"?"` (defensive only — a built app
    /// bundle always carries the marketing key, and the stamp script leaves
    /// `"?"` in `GIT_COMMIT_SHA` when git is unavailable). Only the
    /// `"internal"` channel badges; `""`/nil/anything else renders bare.
    static func formatted(
        marketing: String?,
        build: String?,
        isDebug: Bool,
        debugSuffix: String,
        // No defaults on either tail parameter: every call site must
        // consciously choose the channel and the badge string, so neither
        // an untranslated literal nor a silently bare channel can slip into
        // the localized version label.
        channel: String?,
        internalSuffix: String
    ) -> String {
        var text = "v\(marketing ?? "?") (\(build ?? "?"))"
        if channel == "internal" {
            text += " • \(internalSuffix)"
        }
        if isDebug {
            text += " • \(debugSuffix)"
        }
        return text
    }

    /// The version label for this build. Whether the `Debug` suffix is
    /// appended is a compile-time fact (`#if DEBUG`, matching the repo's
    /// `SWIFT_ACTIVE_COMPILATION_CONDITIONS: DEBUG` pattern), not a runtime
    /// config lookup; the channel comes from the `RELEASE_CHANNEL` bundle
    /// key (empty default locally, stamped by `ci_post_clone.sh` on tags).
    static var text: String { text(bundle: .main) }

    /// Bundle-injectable core so tests can exercise the positive (internal
    /// channel) path, which the Debug test bundle itself never carries.
    static func text(bundle: Bundle) -> String {
        let marketing = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let sha = bundle.object(forInfoDictionaryKey: "GIT_COMMIT_SHA") as? String
        let channel = bundle.object(forInfoDictionaryKey: "RELEASE_CHANNEL") as? String
        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif
        return formatted(
            marketing: marketing,
            build: sha,
            isDebug: isDebug,
            debugSuffix: L10n.profileVersionDebugSuffix.text,
            channel: channel,
            internalSuffix: L10n.profileVersionInternalSuffix.text
        )
    }
}
