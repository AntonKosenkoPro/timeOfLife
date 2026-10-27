## Context

See proposal.md (Why) for motivation. Current state (post-#147 `move-ios-checks-to-xcode-cloud` + #151 Sentry stage 0): `ios.yml` keeps NO automatic triggers — `on: workflow_call` only, invoked by `release.yml verify` on the pushed head (GITHUB_TOKEN pushes trigger no workflows on their own). All iOS PR verification runs on the Cloud `iOS PR Checks` workflow (Build + Test actions on PRs touching `ios/`, path-filtered `ios/**`, SwiftLint via `ci_pre_xcodebuild.sh`, xcodegen via `ci_post_clone.sh` with fail-closed pins, signed-dSYM upload via `ci_post_xcodebuild.sh` on the tag workflow). The Oct 2026 burn (24h 9m / 25h, 137 builds) shows PR-frequency builds don't fit the free quota. The `verify` job + `sentry-dsym` job + `ci_scripts/` pins are proven infrastructure to keep, not rebuild. Per-user decision: Analyse = the existing warnings-as-errors build, not a new analyzer gate.

## Goals / Non-Goals

**Goals:**
- Restore the exact pre-#147 GitHub PR bar (`--strict` lint + warnings-as-errors build + full `TimeOfLifeTests`) with automatic triggers, so `main` is never without a proven iOS gate.
- Reduce Cloud spend to tag-triggered Archive only (a few builds/month), keeping TestFlight distribution untouched.
- Keep the change atomic: one PR restores GH triggers, documents the ASC operator steps, and updates docs.

**Non-Goals:**
- No `xcodebuild analyze` (clang static analyzer) adoption — new gate, new triage surface, slower runs; the warnings-as-errors build + `--strict` lint is the declared analyze bar (user decision).
- No `ci_scripts/` edits, no pin bumps, no SwiftLint rule changes, no Cloud Environment/Xcode upgrades, no TestFlight group changes, no versioning/signing changes.

## Decisions

- **D1 — Restore pre-#147 `on:` triggers in `ios.yml`, keep `workflow_call`.** The `pull_request` (`paths: ios/**`, `ios.yml`) + `push branches: [main]` (`paths: ios/**`) block returns verbatim; `workflow_call` (+ Sentry secrets block) stays so `release.yml verify` keeps working. Alternative (separate PR-check workflow calling `ios.yml`) rejected: two files for one lane, branch protection would need two required checks.
- **D2 — Analyse = warnings-as-errors build + `swiftlint --strict` (no analyzer step).** Target-scoped `SWIFT_TREAT_WARNINGS_AS_ERRORS` / `GCC_TREAT_WARNINGS_AS_ERRORS` in `project.yml` already fail the GH `build` step on any warning without conflicting with the `-suppress-warnings` flag Xcode adds to SPM targets (GRDB); `lint --strict` elevates style findings to failures via non-zero exit. A new `xcodebuild analyze` step would add minutes per run plus a never-triaged finding backlog on ~130 Swift files. Alternative (add analyze as non-required/advisory) rejected: advisory gates rot; revisit as its own change if clang findings matter.
- **D3 — Disable (not delete) the Cloud `iOS PR Checks` workflow.** Disable preserves the tested config for a future return; delete would force rebuilding start conditions/file filters/scheme from docs. Either stops the spend; disable is reversible in one toggle. The tag workflow keeps Archive (+ post-clone + post-build dSYM upload), drops `Test`.
- **D4 — Keep `ci_pre_xcodebuild.sh` in-repo untouched.** It still gates tag archives (lint runs before Archive). Cost is ~seconds on a lint-green `main`; removing it would drop the only lint check on the archive path. Alternative (delete as GH owns lint now) rejected: archive path would lose its backstop.
- **D5 — Keep the `sentry-dsym` job untouched.** It archives Release unsigned purely for dSYMs when GH secrets exist and skips gracefully otherwise; the Cloud tag workflow uploads signed-archive dSYMs. Overlapping but complementary coverage (GH-verified head vs. shipped binary); unpicking it doubles this change's test matrix. Marked as follow-up, not this cut.
- **D6 — Tag-workflow `Test` removal is safe because GH proves the head twice.** Every tag builds on a `main` head that passed GH PR checks as a PR and passes `release.yml verify` (`workflow_call` into `ios.yml`) on the bump commit. What disappears: Release-configuration test execution. Accepted: the suite runs Debug-only today on both providers; no Release-only test coverage exists to lose.

## Risks / Trade-Offs

- [Risk] GH macOS minutes become the new constraint (`macos-15` = 10× multiplier; cold DerivedData + `brew install` per run) → Mitigation: path filters (`ios/**`) preserved so backend-only PRs cost nothing; `sentry-dsym` stays release-only; follow-up (brew/DerivedData caching) explicitly out of scope.
- [Risk] Branch-protection edit missed → PRs merge without the iOS gate (or block if the stale Cloud check stays required) → Mitigation: merge-day operator task with Settings path + `gh api` verification; proof via a no-op `ios/`-touching PR showing GH check firing and no Cloud PR build.
- [Risk] Cloud PR workflow left enabled by mistake → spend continues alongside GH → Mitigation: verification task requires showing no Cloud PR build for the proof PR (ASC build list).
- [Risk] Tag Archive without `Test` ships an untested Release binary → Mitigation: accepted per D6 (no Release-only coverage exists); GH `verify` on the bump commit is the last green gate before Archive.
- [Risk] Cloud quota (51m left until Nov 16) starves even Archive-only if a release lands before reset → Trade-off accepted; contingency is GH-`verify`-only for one release (Archive retried post-reset), stated in tasks.

## Migration Plan

1. Land this PR: `ios.yml` triggers restored (GH checks go green on the PR itself — self-proving), docs updated.
2. Merge-day operator (human, App Store Connect): disable `iOS PR Checks` workflow; strip `Test` from the tag workflow; (human, GitHub Settings): require `ios / lint-build-test`, drop any required Cloud check.
3. Post-merge proof: no-op `ios/`-touching PR → GH `ios` check required + green, no Cloud PR build fires; next tag → Archive-only → TestFlight.
4. Rollback: re-enable Cloud `iOS PR Checks` start conditions + remove GH `on:` triggers (exact inverse, one PR + two toggles). The pre-change state is fully described by #147's diff.

## Open Questions

None — the Analyse definition (warnings-as-errors, per user) and the disable-vs-delete call (D3) are decided above.
