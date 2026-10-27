## Why

The `main protection` ruleset requires the `lint-and-test` (backend) and `lint-build-test` (iOS) checks, but both workflows are path-filtered — PRs touching neither `backend/**` nor `ios/**` never produce those checks, and GitHub leaves path-skipped workflow checks Pending forever, so such PRs can never merge. Live repro: PR #211 (docs/openspec-only) is merge-BLOCKED with only `validate` + Cloudflare reporting. This is the round-1 AI-review finding from #209 coming true — the waive was wrong and is corrected here.

## What Changes

- `ios.yml`: `pull_request` trigger loses its path filter; a new ubuntu `changes` job diffs `base...HEAD` for `ios/**` + the workflow file (fail-closed to true on detection failure); `lint-build-test` runs only when the diff matches (or on non-PR events, where the kept `push` path filter already matched); new always-run `ios-gate` job (`if: always()`, ubuntu) passes iff `lint-build-test` ∈ {success, skipped}. `sentry-dsym` untouched (still release-path-only via `upload_dsyms`).
- `backend.yml`: same shape — new `changes` job (`backend/**` + workflow file), `lint-and-test` gated on it for pull_request, new always-run `backend-gate`. `deploy` untouched (`needs: lint-and-test`, push/dispatch only).
- Ruleset (manual operator step on merge day): require `ios-gate` + `backend-gate` instead of `lint-build-test` + `lint-and-test`.
- Docs: `docs/ci.md` gains a required-gates section (gate semantics, operator swap, fail-closed rule); troubleshooting updated for the Pending-checks symptom.

## Capabilities

### New Capabilities

None — pure CI/tooling fix, no product behavior changes. This change sets `skip_specs: true` in its `.openspec.yaml` (validated: zero deltas expected).

### Modified Capabilities

None — no baseline spec requirements change.

## Impact

- Affected systems: GitHub Actions (`ios.yml`, `backend.yml`), ruleset `main protection` (manual context swap), `docs/ci.md`.
- Affected baseline capabilities: none behaviorally; FURPS S6 rows are provider-neutral and this restores their enforceability on every PR.
- Authoritative docs / research bundle: `/websites/github_en_actions` — "required status checks skipped workflows path filters always run gate job" (path-skipped workflows leave checks Pending and block PRs that require them; `always()` + `needs` dependent-job pattern for gates); `/websites/developer_apple_xcode` — no Cloud changes in this diff (waiver reason recorded, not silence). Pin: Xcode 27.x Cloud / local 27.0; xcodegen 2.46.0, SwiftLint 0.65.1. Waivers: HIG N/A — CI-only diff, no user-facing surface; Apple app-framework API N/A — diff is workflow YAML + ruleset toggle + docs.
- Repro (bugfix rule, recorded pre-implementation): PR #211 `mergeState: BLOCKED`, check-runs on head = only `validate` + Cloudflare Pages success; ruleset requires `lint-and-test` + `lint-build-test` which never report on that tree.
- Non-goals: no `required_workflows` (same skip problem), no removal of path filters (would burn a macOS run per docs PR), no fork-PR support beyond fail-closed detection, no pin/toolchain changes, no app/backend/contract changes.
