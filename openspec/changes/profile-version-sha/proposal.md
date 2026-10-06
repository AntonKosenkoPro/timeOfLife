## Why

Every TestFlight build must be traceable from the Profile version footer back to a single repo commit (`release-versioning` purpose). Today the footer shows an integer build (`v0.1.3 (4)`), which identifies the commit only indirectly via the `chore(release)` message + tag. Showing the commit's short SHA directly (`v0.1.3 (a1b2c3d)`) removes the lookup step for testers reporting builds.

## What Changes

- Profile version footer displays `v<marketing> (<7-char-SHA>)` instead of `v<marketing> (<integer-build>)`. Debug builds keep the suffix: `v0.1.3 (a1b2c3d) • Debug`.
- The SHA is the current commit at build time (`git rev-parse --short=7 HEAD`), stamped into the bundle by a Run Script Phase. No dirty-tree marker: a dirty tree still reports its base commit's SHA (explicit user decision).
- `CFBundleVersion` / `CURRENT_PROJECT_VERSION` keep auto-incrementing by +1 per release/rebuild exactly as today — they remain the App Store Connect upload identifier but are no longer displayed. `release.yml` is unchanged.
- When the SHA is unavailable at build time (no `.git`, script failure), the parenthetical falls back to `"?"` (`v0.1.3 (?)`), matching the existing defensive placeholder shape.
- Formatting core (`AppVersion.formatted`) is unchanged — only the data source for the parenthetical changes (new `GIT_COMMIT_SHA` bundle key instead of `CFBundleVersion`).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `release-versioning`: the Profile label's trace key changes from integer build number to 7-char commit SHA. Tag convention, semver rules, and the +1 build-increment requirement are unchanged; the integer build's role narrows to upload acceptance.

## Impact

- iOS: `Core/Utilities/AppVersion.swift` (read stamped SHA key), `project.yml` (new Run Script Phase via XcodeGen + `xcodegen generate`), `Configuration/Info.plist` + `Info-Debug.plist` (new `GIT_COMMIT_SHA` key), `TimeOfLifeTests/AppVersionTests.swift`.
- Specs/docs: delta on `release-versioning`; `docs/project-context.md` + `README.md` version-row wording (`v0.1.3 (4)` examples become SHA examples).
- No backend, OpenAPI, localization (format unchanged), or signing changes. No `release.yml` logic change.

### Non-goals

- Tap-to-copy full SHA, long-press actions, or showing the full 40-char hash anywhere.
- Displaying both identifiers (`4, a1b2c3d`) — SHA-only (explicit user decision).
- Dirty-tree marking (`-dirty` / `+` / `*`) — out of scope by decision.
- Changing upload semantics: integer builds keep incrementing; tags keep pointing at bump commits.
- Touching `CFBundleVersion` semantics — Apple sees the same increasing integers as today.

### External docs

No new external dependency. Build stamping uses only Apple-stable Run Script Phases and stable git CLI (`git rev-parse --short=7 HEAD`, stable since git 2.x). XcodeGen `preBuildScripts` shape is verified at implementation time against the repo's installed xcodegen version (tasks task 0); no version pin to cite in this proposal.
