## Context

See `proposal.md` for motivation. Current state: `project.yml` is the single version truth (`CFBundleShortVersionString` + `CFBundleVersion` / `CURRENT_PROJECT_VERSION`, currently `0.1.3` / `4`); XcodeGen merges it into `Info.plist` at generation time; `AppVersion.text` reads the built bundle's `CFBundleShortVersionString` + `CFBundleVersion` and `ProfileView.versionFooter` renders `v0.1.3 (4)` (`• Debug` under `DEBUG`). `release.yml` auto-increments the integer build by +1 on every release/rebuild and tags `vX.Y.Z`. Constraints from `docs/project-context.md`: XcodeGen-managed (edit `project.yml`, run `xcodegen generate`, never hand-edit `.pbxproj`); app/test warnings are errors; SwiftUI views use `Theme` semantic colors only; user-facing strings via `L10n` in both locales (this change alters no localized string — the `v… (…) • …` format is unchanged, only the parenthetical's data source changes).

## Goals / Non-Goals

**Goals:**
- Profile footer shows the built commit: `v<marketing> (<7-char-SHA>)`, `• Debug` suffix preserved.
- Integer `CFBundleVersion`/`CURRENT_PROJECT_VERSION` keeps incrementing for App Store Connect; `release.yml` untouched.
- Missing-SHA builds degrade to the existing `"?"` placeholder, never crash or blank the footer.

**Non-Goals:**
- No dirty-tree marking, no tap-to-copy, no full-hash surface, no both-identifiers display. No change to tag semantics, upload semantics, signing, sync, storage, or API.

## Decisions

1. **Stamp at build time into a new bundle key `GIT_COMMIT_SHA` (Option A).** A trailing Run Script Phase (`postBuildScripts` in `project.yml`, XcodeGen-managed) runs `git rev-parse --short=7 HEAD` and writes the result into the *built* `Info.plist** (`${TARGET_BUILD_DIR}/${INFOPLIST_PATH}` via PlistBuddy), with `|| echo "?"` fallback. Trailing (not leading): the phase must run after Xcode's Process-Info.plist step so the built file exists on clean builds, and build-phase scripts still run before CodeSign, so the stamped plist is what gets signed. Source `Info.plist` + `Info-Debug.plist` gain the key with placeholder `"?"` so a build that skips the script still reads something. Alternative (record SHA into `project.yml` at release time) rejected: every local Debug build would display the last release's commit instead of the running HEAD. Alternative (CI-env-only stamping) rejected: local simulator builds — the most common Debug surface — would all read `"?"`.
2. **`AppVersion.text` reads `GIT_COMMIT_SHA` instead of `CFBundleVersion` for display; `formatted(marketing:build:isDebug:debugSuffix:)` is unchanged.** The `build:` parameter simply receives the SHA string — existing tests keep their shape, updated with SHA fixtures. Alternative (replace `CFBundleVersion` with the SHA outright) rejected: TestFlight requires unique, increasing build numbers per marketing version; a hex SHA is neither numeric nor monotonic and would break uploads. Alternative (show both `4, a1b2c3d`) rejected by explicit user decision — SHA-only.
3. **Force exactly 7 characters (`--short=7`), not git's auto-scaling `--short`.** Matches the explicit request and GitHub convention. Accepted trade-off: auto-scaling would future-proof uniqueness as the repo grows; forcing 7 can theoretically collide at scale (negligible at this repo size; revisit if git ever warns about ambiguity).
4. **No dirty marker.** Script performs no `git diff`/`git status` check; a dirty tree reports its base commit. Per explicit user decision — keeps the script two lines and the spec testable. Documented consequence: uncommitted edits are invisible in the footer.
5. **Keep the `• Debug` suffix and both `Info.plist` variants.** Debug uses `Info-Debug.plist` (scoped ATS exception); both plists carry the new key so simulator and device builds behave identically.

## Risks / Trade-offs

- [Risk] Archiving from a source export without `.git` (or script-phase ordering issue) → footer shows `vX.Y.Z (?)`. Mitigation: `"?"` fallback is the specified behavior (spec scenario), identical to today's missing-key path.
- [Risk] Next `xcodegen generate` wipes or conflicts with the new key/script. Mitigation: everything lives in `project.yml` (`info.properties` key default + `postBuildScripts` phase); generated output is verified in tasks (rebuild + built-plist SHA check); never hand-edit the `.pbxproj`.
- [Risk] Testers can no longer see the App Store Connect integer build in-app. Mitigation: the integer survives in `chore(release)` commit messages, tags messages, and App Store Connect; `docs/project-context.md` + `README.md` record the mapping (`vX.Y.Z (N)` commit ↔ short SHA in footer).
- [Risk] Forced 7-char SHA ambiguity as history grows. Mitigation: accepted; `git rev-parse --short=7` fails loudly rather than silently truncating if ever ambiguous — the `"?"` fallback surfaces it.

## Migration Plan

No data migration (no on-disk format touched). Land the change, regenerate with `xcodegen generate`, commit `project.yml` + both plists + code + specs. Rollback is a clean revert (footer returns to integer build; the extra plist key is inert). After `openspec archive`, update `docs/project-context.md` (deployment/release paragraph) and `README.md` (version-row examples) so no `1.0.0 (3)`-style example contradicts the SHA footer.

### External docs

No ctx7 fetch constrains this design: no new dependency is introduced. The implementation touches only Apple-stable Run Script Phases, stable git CLI (`rev-parse --short`, stable since git 2.x), and the repo's established XcodeGen flow. The one version-sensitive shape (XcodeGen `postBuildScripts` phase syntax) was verified against the installed xcodegen 2.46.0 with a scaffold probe at implementation time (see `tasks.md` task 1.1) rather than cited from training data.
