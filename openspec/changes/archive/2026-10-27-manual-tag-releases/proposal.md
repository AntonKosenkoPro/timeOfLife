## Why

The release flow assumed the `release.yml` bot could push bump commits to `main`. Branch protection (`main protection` ruleset, PR-only, zero bypass actors) proved that model dead: dry run `40211312698` failed with `GH013 — Changes must be made through a pull request`. Releases need a long-term system that is manual (owner-only trigger), verifiable (tag → commit → build → store), rollback-able, and low-effort — covering the git workflow, not just CI pipelines.

## What Changes

- **Manual signed tags are the only release act.** Namespaces `internal/*` (dogfood), `release/*` (public), `backend/*` (relay). Tags are SSH/GPG-signed (`-s`), created only on `main`, and never moved. A mistyped tag matches no workflow and builds nothing (fail-closed).
- **You-only tag rulesets.** New rulesets targeting the three namespaces with the owner as the sole bypass actor, so even a compromised workflow cannot cut a release. Branch protection on `main` is untouched.
- **No bump commits.** `release.yml`'s bump/mirror/push machinery (unanimity guards, `RELEASE_PLISTS`, rebuild/recover modes, `verify` job) is deleted. `project.yml` keeps a checked-in dev dummy (e.g. `0.0.0-dev`) so local/simulator builds compile; it never ships.
- **Cloud stamps versions at build time.** Two tag-triggered workflows (`internal/*` → TestFlight Internal, `release/*` → TestFlight External/App Store) share an extended `ci_post_clone.sh`: parse tag → `MARKETING_VERSION` / build (Cloud per-workflow run number, monotonic per marketing line for ASC) / `CHANNEL`, stamp all targets in lockstep, assert unanimity or fail the archive.
- **Profile shows the channel.** Internal builds render `v0.2.8 (abc1234) • Internal`; public builds keep `v0.3.0 (e4f5a6b)`; local builds read the dummy.
- **Backend gains an identity (new).** `backend/*` tags produce pinned image tags (`backend-<tag>`, `:latest` keeps floating); `/health` gains `{version, sha}` stamped via `ldflags`; fix the `stage`-vs-`prod` env skew (`backend.yml:92` defaults to `stage` while the comment promises `prod`).
- **Rollback is revert-forward.** iOS: never move a tag — `git revert` + new tag through the internal channel first (installed apps can't downgrade; ASC keeps every build; halt phased rollout while verifying). Backend: redeploy the previous pinned image; migrations adopt expand-contract so rollback is never blocked by schema.
- **Environments for the timeline (deferred to Phase 3).** `testflight-internal` / `testflight-public` (+ `backend-prod`) GH environments with a wait timer give an approval gate and a deployment timeline. Cloud status reports back manually until/unless a webhook exists.

- **Non-goals:** no auto-cut releases on green `main`; no release branches by default (hotfix branches only when `main` has moved past a public tag); no App Store submit automation; no iOS↔backend version coupling (ship independently; Profile relay-version display is observability only); no Cloud→GitHub status back-reporting in this change; no OTel/SLO telemetry.

## Capabilities

### New Capabilities

- `backend-release-identity`: pinned backend image tags plus `/health` `{version, sha}` build identity, so any tester can identify both ends of the system from the Profile row plus one endpoint.

### Modified Capabilities

- `release-versioning`: the bump-commit model (single commit on `main` + `vX.Y.Z` tag on the bump commit + rebuild/recover modes) is replaced by the tag model (signed `internal/*` / `release/*` tags as the release act, Cloud-stamped marketing/build/channel, revert-forward rollback). Semver and tag-immutability requirements are kept.

## Impact

- Affected systems: `.github/workflows/release.yml` (bump machinery deleted), `backend.yml` (tag trigger, `stage`/`prod` split), `ios/TimeOfLife/ci_scripts/` (extended stamp script), `project.yml` (dev dummy) + `AppVersion`/Profile (channel badge), backend `/health` + `Dockerfile` + `openapi.yaml` health schema, GitHub tag rulesets (manual operator step), docs (`ci.md`, `project-context.md`, `README.md`, `AGENTS.md`, `review-process.md`).
- Relationship: `migrate-ios-ci-to-xcode-cloud` is being archived without merging (its GH→Cloud-cutover premise was reversed by #209, which restored GH PR checks and made Cloud archive-only). This change owns the tag model + backend identity; the doc edits land here.
- Authoritative docs (research bundle, re-verify at apply time): `/websites/developer_apple_xcode` — "Xcode Cloud custom build script ci_post_clone" (script names, `ci_scripts/` discovery, shebang, automatic execution); `/websites/github_en_actions` — "environment protection rules required reviewers deployment" (required reviewers, wait timer, deployment objects). Pin: iOS 18 SDK via Xcode 16+. Waivers: HIG N/A — release tooling, no user-facing surface; SwiftUI/ActivityKit N/A — no app-framework API touched (CI scripts + workflow YAML + docs + tag rulesets).
