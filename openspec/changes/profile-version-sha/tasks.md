## 1. Build-time SHA stamping

- [x] 1.1 Confirm XcodeGen `postBuildScripts` phase syntax against the repo's installed xcodegen version (`xcodegen --version`, minimal scaffold probe if needed)
- [x] 1.2 Add trailing Run Script Phase in `project.yml` stamping `git rev-parse --short=7 HEAD` (fallback `"?"`) into the built `Info.plist` as `GIT_COMMIT_SHA`
- [x] 1.3 Declare `GIT_COMMIT_SHA: "?"` default in `project.yml` `info.properties` and mirror into source `Info.plist` + `Info-Debug.plist`
- [x] 1.4 Run `xcodegen generate` and verify the phase lands in the project and a build's plist carries the current HEAD's 7-char SHA

## 2. Display source swap

- [x] 2.1 Switch `AppVersion.text` to read `GIT_COMMIT_SHA` (fallback `"?"`) instead of `CFBundleVersion`; leave `formatted(...)` signature and `• Debug` logic untouched
- [x] 2.2 Update `AppVersion.swift` doc comments (SHA footer examples, `project.yml` + stamp-script as truth)

## 3. Tests

- [x] 3.1 Update `AppVersionTests` fixtures to SHA values (`v0.1.0 (a1b2c3d)`, Debug variant) and keep the missing-keys placeholder test (`v? (?)`)
- [x] 3.2 Cover the runtime path: stamped SHA renders in `AppVersion.text`; unstamped bundle falls back to `?`

## 4. Docs and contract

- [x] 4.1 Re-check `Requirements/FURPS/*.md` rows touching version/reporting; fix conflicts if any
- [x] 4.2 Update `docs/project-context.md` (deployment/release paragraph) and `README.md` (Profile version-row examples) from `1.0.0 (3)`-style to SHA-style, noting the integer build survives for App Store Connect only

## 5. Verification

- [x] 5.1 `swiftlint lint --strict` green and `xcodebuild -scheme TimeOfLife -destination '<available simulator>'` build + full `test` green (one `xcodebuild` at a time per `docs/ios-test-loop.md`)
- [x] 5.2 `openspec validate --all --strict` green for the change
