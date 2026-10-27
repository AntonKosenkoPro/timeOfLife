## Why

Xcode Cloud PR checks (landed in #147, `move-ios-checks-to-xcode-cloud`) burned 24h 9m of the 25h/month free quota (97% used, 51m left until Nov 16 reset; 137 builds / 33h 31m in the last 30 days). GitHub `ios.yml` currently keeps no automatic triggers and runs only as release verification, so every iOS PR verification consumes metered Cloud minutes. Restoring GitHub runners as the PR gate and keeping Xcode Cloud for tag-triggered Archive → TestFlight only returns iOS CI to unmetered (allowance-bound) runners and reserves Cloud minutes for releases.

## What Changes

- Restore automatic triggers in `.github/workflows/ios.yml`: `pull_request` (`paths: ios/**`, `ios.yml`) + `push` to `main` (`paths: ios/**`) alongside the existing `workflow_call` (kept for `release.yml verify`). Job contents unchanged: xcodegen + `swiftlint lint --strict` + warnings-as-errors Debug simulator build + `xcodebuild test` + the existing `sentry-dsym` job.
- Analyse stays defined as the warnings-as-errors build (per-target `SWIFT_TREAT_WARNINGS_AS_ERRORS` / `GCC_TREAT_WARNINGS_AS_ERRORS` in `project.yml`, which fail the `build` step on any warning) plus `swiftlint lint --strict`. No new `xcodebuild analyze` step: the clang analyzer is a new, slow, unproven gate on a codebase that never ran it.
- Disable the Xcode Cloud `iOS PR Checks` workflow in App Store Connect (PR Changes + Branch Changes start conditions off) so `ios/` pushes stop consuming Cloud minutes. No in-repo Cloud config exists to edit — this is a manual operator step.
- Slim the Cloud tag workflow (`v*`) to Archive only: strip the `Test` action (the head was already proven by GH `ios.yml` via PR checks + `release.yml verify`), keep `ci_post_clone.sh` (xcodegen, pinned), Release signing, and `ci_post_xcodebuild.sh` (signed-dSYM Sentry upload). `ci_pre_xcodebuild.sh` (lint) stays in-repo untouched — it still gates tag archives at near-zero cost since tags build from lint-green `main`.
- Re-require the `ios / lint-build-test` check in branch protection for `main` (manual operator step on merge day; `gh api` currently reports the branch as unprotected).
- Update docs that describe Cloud-owned iOS CI: `docs/ci.md` (provider split → GH-owned iOS checks, Cloud archive-only; new-target checklist scheme coverage back to `ios.yml`), `README.md` (CI + release paragraphs), `docs/project-context.md` (CI paragraphs), `AGENTS.md` (workflows listing), `docs/review-process.md` (mandatory-checks line).

## Capabilities

### New Capabilities

None — pure CI/tooling migration, no product behavior changes. This change sets `skip_specs: true` in its `.openspec.yaml` (validated: zero deltas expected).

### Modified Capabilities

None — no baseline spec requirements change.

## Impact

- Affected systems: GitHub Actions (restore `ios.yml` triggers), Xcode Cloud (disable PR workflow + strip tag `Test` in App Store Connect; `ci_scripts/` untouched), branch protection rules (manual Settings edit), docs listed above.
- Affected baseline capabilities: none behaviorally; `release-versioning` docs-adjacent (release flow description changes back, requirements untouched).
- Authoritative docs / research bundle: `/websites/github_en_actions` — "workflow triggers pull_request paths workflow_call" (path-filtered `pull_request`/`push` triggers, reusable `workflow_call` for `release.yml verify`); `/websites/developer_apple_xcode` — "Xcode Cloud custom build script ci_scripts" (`ci_post_clone.sh` / `ci_pre_xcodebuild.sh` naming, `chmod +x`, shebang, no `sudo`; Cloud config lives in App Store Connect, not the repo). Pin: Xcode 27.x Cloud / local 27.0; xcodegen 2.46.0, SwiftLint 0.65.1 (pins recorded in `docs/ci.md` + `ci_scripts/`). Waivers: HIG N/A — CI-only diff, no user-facing surface; Apple app-framework API N/A — diff is workflow YAML + ASC toggles + docs, no app code.
- Non-goals: no app, backend, OpenAPI, signing, entitlement, versioning, or TestFlight-distribution changes; no Cloud Environment/Xcode-version changes; no SwiftLint rule changes (`.swiftlint.yml` untouched); no `MARKETING_VERSION`/lockstep logic changes; no `xcodebuild analyze` adoption; no `ci_scripts/` edits; no `sentry-dsym` job changes.
- Risk: first month back on GH macOS runners shifts cost to Actions minutes (`macos-15` bills at 10×); mitigated by path filters (`ios/**`) and the release-only `sentry-dsym` residue. Direct pushes to `main` keep the `verify` gate via `workflow_call` (unchanged).
