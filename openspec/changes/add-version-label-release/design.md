## Context

See proposal.md (Why) for motivation. Current state shaping the approach:

- `ios/TimeOfLife/project.yml` stamps `CFBundleShortVersionString: "1.0"` + `CFBundleVersion: "1"` via `info.properties` and `CURRENT_PROJECT_VERSION: "1"`; `Info.plist` carries static `"1.0"`/`"1"` duplicates. The project is XcodeGen-managed (CI regenerates via `xcodegen generate`), so generation-time values win. **Verified 2026-09-28** (spike 1.1): `xcodegen generate` emits no `INFOPLIST_KEY_*` overrides; instead its "Generating plists…" step rewrites the tracked `Info.plist` from `info.properties` (proven on a scratch copy bumped to `9.9`/`99`), and `CURRENT_PROJECT_VERSION` lands in the pbxproj — hence the `Info.plist` mirror in D1.
- `ProfileView` (`Features/AppShell/Views/ProfileView.swift`) is a `NavigationStack { List { accountSection + onDeviceSection } }` presented as a sheet from `AppShellView`; `onDeviceSection` already owns a footer, so the version row needs its own trailing section.
- Debug builds set `SWIFT_ACTIVE_COMPILATION_CONDITIONS: DEBUG` (used pervasively as `#if DEBUG`); Release carries the signing team for TestFlight archives. No version helper, no `L10n` version key, no tags exist yet.
- CI (`ios.yml`) is PR/push-only with `contents: read`; the new workflow is the first with write access.

## Goals / Non-Goals

**Goals:**
- One writer for version truth, readable in-app and in CI with no drift.
- Zero-typing build uniqueness for TestFlight re-uploads.
- A tag convention chosen once (first tag sets precedent).

**Non-Goals:**
- No upload automation (App Store Connect / fastlane), no backend version endpoint, no update prompts — see proposal.md non-goals.

## Decisions

1. **Single writer: `project.yml` only.** The workflow edits `info.properties.CFBundleShortVersionString`, `info.properties.CFBundleVersion`, and `settings.base.CURRENT_PROJECT_VERSION`, keeping `CFBundleVersion == CURRENT_PROJECT_VERSION`. The bump script additionally mirrors the two values into the tracked `Info.plist` statics (spike result: `xcodegen generate` rewrites that file from `project.yml` on every run, so an unmirrored commit would leave it reading stale until the next generate; generation remains authoritative, the mirror is consistency only). Alternative (edit both files by hand each release) doubles drift surface; alternative (move versions into `xcconfig`) is cleaner long-term but drags signing/config plumbing into this change. Task zero verifies post-`xcodegen generate` values come from `project.yml`.
2. **Label reads the built bundle at runtime** (marketing + build keys, same pattern as `AppConfig` reading `API_BASE_URL`), with the `• Debug` suffix compiled in under `DEBUG` only. Alternative (runtime config detection via `Info.plist` flag) adds a config knob for what is a compile-time fact. The word "Debug" stays universal in `en`+`ru` (config name, not prose) but still ships as an `L10n` key per the U4 both-locales rule.
3. **Row presentation: own trailing `Section` with a right-aligned caption in `Theme.textSecondary`, non-tappable, stable accessibility identifier.** Alternative (reuse `onDeviceSection` footer) collides with `profileOnDeviceFooter` styling; alternative (pinned overlay below `List`) leaves `List` semantics and VoiceOver order.
4. **Workflow: `workflow_dispatch` with `version` (canonical `X.Y.Z`, no leading zeros) + optional `build_only` flag, guarded in-job (ref == main via env-passed ref — never interpolated — canonical-semver regex, clean tree, python edit of `project.yml`), build `+1`, `chore(release)` commit, single atomic `git push` of commit + tag with `contents: write`, SHA-compare landed-check.** Modes (resolved in one guard step): `release` (strictly greater → bump marketing + build, new annotated tag), `rebuild` (`build_only` with VERSION exactly equal to the stored canonical string and the tag already on origin → build +1 only, no tag — the spec's re-upload scenario), `recover` (requested == current but the tag is missing on origin → push just the tag onto the bump commit located by fixed-string grep and verified against its `project.yml` snapshot, with the tag message's build read from that snapshot, never the live tree). Alternative (manual build input) was rejected in exploration — auto-increment removes the re-upload scramble. Alternative (run-number builds) breaks monotonicity across re-runs. Pushes made with `GITHUB_TOKEN` trigger no workflows on their own, so the run chains `ios.yml` (which exposes `workflow_call` for this) as a `verify` job on the pushed head — see R below.
5. **No backend/OpenAPI impact.** Versioning is client + CI only; the relay never sees it.

## Risks / Trade-offs

- [Risk] `Info.plist` statics silently win over generated values → built label shows stale `1.0 (1)` → Mitigation: task-zero spike asserts the built bundle's keys after `xcodegen generate` before writing the label.
- [Risk] `CFBundleVersion` and `CURRENT_PROJECT_VERSION` drift (edited one, forgot the other) → archive/build-number mismatch → Mitigation: single script edits all three fields and asserts equality before commit.
- [Risk] `GITHUB_TOKEN` cannot push to protected `main` → workflow fails at push → Mitigation: verify branch-protection + token permissions on first dry run with an invalid version (exercises guards without side effects).
- [Risk] `GITHUB_TOKEN` pushes trigger no workflows → the bump commit would reach App Store Connect on the strength of a manual local build (found in AI review of PR #64) → Mitigation (round 2): the run chains `ios.yml` via `workflow_call` as a `verify` job on the pushed head; do not upload until it is green.
- [Risk] Partial push (commit lands, tag doesn't) leaves the release stuck — the greater-than guard rejects every re-run → Mitigation: commit + tag go out in a single `git push`, and a `recover` mode re-pushes a genuinely missing tag onto the recorded bump commit (found in AI review of PR #64).
- [Trade-off] Annotated `v`-prefixed tags vs bare Apple-style versions: `v1.0.0` chosen for GitHub/releases-tooling convention; the in-app label stays bare (`1.0.0`) — one documented translation, no mixing afterward.

## Migration Plan

1. Land spike (source-of-truth verification) + label + workflow in one PR; no migration (no tags, no shipped data, pre-release policy still in effect).
2. First manual run bumps `1.0` → requested version (normalization moment); confirm `ios.yml` green on the bump commit, tag visible, TestFlight archive shows matching label.
3. Rollback: revert the bump commit and delete the tag locally + remote before any archive references it; after an archive exists, never move the tag — cut a patch version instead.
