## Why

TestFlight distribution is the next step (signed Release archives uploaded to App Store Connect), but today the repo has no version label in the app, no tags, and a static `1.0 (1)` stamped in two places. Once a build leaves the developer's machine there is no way to answer "which code is this?" — testers cannot report their build and the repo cannot point at it. Issue #63 makes this mandatory for TestFlight: show the running build inside the app and automate version bumps with tags.

## What Changes

- Profile displays a version row at the bottom (separate trailing row, right-aligned): `1.0.0 (3)` on Release builds, `1.0.0 (3) • Debug` on Debug builds.
- `project.yml` becomes the single version source of truth (`CFBundleShortVersionString` + `CFBundleVersion` / `CURRENT_PROJECT_VERSION`); the `Info.plist` statics remain only as fallback.
- A manually-triggered GitHub Actions workflow (`workflow_dispatch` with a `version` input, e.g. `1.0.0`, plus an optional `build_only` flag for TestFlight re-uploads) validates the input (canonical semver `X.Y.Z`, strictly greater than current — or equal in rebuild mode — main branch, clean tree), bumps the marketing version (skipped in rebuild mode), auto-increments the build number by +1, commits, and pushes an annotated `vX.Y.Z` tag (a genuinely missing tag is recovered by pushing just the tag).
- First bump also normalizes the two-component `1.0` to three-component semver.

Non-goals (explicit):
- No TestFlight upload automation, no App Store Connect API integration, no fastlane — archiving/uploading stays manual.
- No build-number input on the workflow — build always auto-increments; marketing version is the only manual parameter.
- No in-app update prompts, no backend version endpoint, no version-gating of sync.
- No change to signing, xcconfigs, API base URLs, or the pre-release no-migration policy (the first tag *marks* the point the policy flips, it does not implement migrations).

## Capabilities

### New Capabilities

- `release-versioning`: version source of truth, marketing/build numbering rules, manual-trigger bump flow with guards, and `vX.Y.Z` annotated tag convention.

### Modified Capabilities

- `app-shell`: Profile (which owns secondary destinations) SHALL display the running app version in a trailing version row.

## Impact

- iOS: `ProfileView` (+ version row, `L10n` key, `en`+`ru` strings), `project.yml` version fields (the bump script also mirrors the values into the `Info.plist` statics so the tracked file never reads stale); `Theme` secondary color + caption styling only, no new dependencies.
- CI: new `.github/workflows/release.yml` with `contents: write` permission; existing `ios.yml` unchanged — pushes made with `GITHUB_TOKEN` do not trigger it, so the bump commit is not CI-verified (verify with a local build/archive before uploading).
- Repo history: bump commits + annotated tags on `main` only; no existing tags to migrate (none exist).
