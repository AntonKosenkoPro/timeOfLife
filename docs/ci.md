# CI Pipeline Guide

GitHub Actions carries the mandatory PR checks (Requirements S6); Xcode Cloud is archive-only (TestFlight distribution + signed-dSYM symbolication). Rationale: PR-frequency Cloud builds burned the 25h/month free quota (Oct 2026: 24h 9m used, 137 builds), so iOS verification moved back to allowance-bound GitHub `macos-15` runners.

- **GitHub Actions** — `backend.yml` (Go), `ios.yml` (iOS: xcodegen, SwiftLint, warnings-as-errors build, tests), `openspec.yml` (spec gate), `release.yml` (manual version bump), advisory `ai-review.yml`
- **Xcode Cloud** — tag workflow only (`v*` tags: Archive → TestFlight upload, with `ci_post_xcodebuild.sh` uploading the signed archive's dSYMs to Sentry staging + release; see below). The `iOS PR Checks` workflow is disabled — no PR/push verification runs on Cloud.

Workflows and their scope (`ios.yml` carries the iOS PR lint/build/test bar with `pull_request` + `push`-to-`main` triggers path-filtered to `ios/**`, and stays callable as release verification via `workflow_call` from `release.yml`; the tag-triggered Cloud Archive covers the signed Release build + TestFlight upload):

- **`backend.yml`** — Go: gofmt, go vet, golangci-lint, race tests, OpenAPI contract gate, coverage gate, deploy
- **`ios.yml`** — iOS: `pull_request` + `push`-to-`main` path-filtered to `ios/**` (plus `workflow_call` from `release.yml verify`); xcodegen via `xcodegen generate`, SwiftLint `lint --strict`, warnings-as-errors build (per-target `SWIFT_TREAT_WARNINGS_AS_ERRORS`/`GCC_TREAT_WARNINGS_AS_ERRORS` — the Analyse bar, no separate analyzer step), unit tests, plus the release-only `sentry-dsym` job (unsigned Release archive purely for dSYMs, skips gracefully without secrets)
- **`openspec.yml`** — spec-integrity gate: `openspec validate --all --strict` (CLI pinned 1.8.0) on every PR and push to `main`
- **`release.yml`** — manual `workflow_dispatch` marketing-version bump: validates semver on `main`, bumps every target's versions in `project.yml` in lockstep, mirrors every Release `Info.plist`, commits + tags `vX.Y.Z` (see checklist below — a new target MUST be wired in or the next release fails)

## Xcode Cloud — tag archives only

| Setting | Value |
|---|---|
| Workflow | Tag workflow in App Store Connect (UI-managed; `ci_scripts/` + this doc are the reviewed source of truth) |
| Start conditions | Tag Changes (`v*` pattern only). The former `iOS PR Checks` workflow (Pull Request Changes + Branch Changes on `main`) is disabled — no PR/push verification runs on Cloud |
| Scheme / config | `TimeOfLife`, Release, Archive action with signing (team `7923U48U87`); Debug simulator builds never run on Cloud |
| Post-clone | `ios/TimeOfLife/ci_scripts/ci_post_clone.sh` — brew-install `xcodegen`, fail-closed `XCODEGEN_PIN` assert, `xcodegen generate` (fires `postGenCommand normalize-system-capabilities.py`), `.xcodeproj` existence check |
| Pre-build | `ios/TimeOfLife/ci_scripts/ci_pre_xcodebuild.sh` — brew-install `swiftlint`, fail-closed `SWIFTLINT_PIN` assert, `swiftlint lint --strict` backstop on the archive path (near-zero cost: tags build from lint-green `main`). Resolves the project dir via the `.swiftlint.yml` marker (Test VMs replay the script from clone-root, not its repo location) |
| Post-build | `ios/TimeOfLife/ci_scripts/ci_post_xcodebuild.sh` — Sentry dSYM upload from Cloud's own signed archive (`$CI_ARCHIVE_PATH/dSYMs`, the exact binary TestFlight ships) to the staging + release projects via `sentry-cli debug-files upload`. Per project skips with a warning when its secrets are absent; upload failures warn but never fail the archive |
| Logs | App Store Connect build page; link the build in the release notes when reporting archive failures |

### Xcode Cloud shared secret env vars (Sentry; tag workflow)

Set in App Store Connect as shared secret env vars on the tag workflow (same names as the former GitHub secrets, so the skip-logic reads the same). All five are optional: any absence skips gracefully with a warning, never a failure.

| Variable | Value | Secret? |
|---|---|---|
| `SENTRY_AUTH_TOKEN` | token with Project write (debug files), consumed by `ci_post_xcodebuild.sh` | yes — absent = upload skips with a warning |
| `SENTRY_ORG` | org slug | yes — absent = upload skips with a warning |
| `SENTRY_PROJECT_STAGING` | staging project slug | yes — absent = staging upload skips |
| `SENTRY_PROJECT_RELEASE` | release project slug | yes — absent = release upload skips |
| `SENTRY_DSN` | iOS DSN (value migrated from the former `SENTRY_IOS_DSN` GitHub secret) | yes — flows into the built Info.plist via the `SENTRY_DSN = $(SENTRY_DSN)` xcconfig self-reference; absent = archived binary ships with the SDK disabled |

Toolchain pins (bump together with the local toolchain; version-skew failures are fixed by pinning, never by relaxing `--strict` or per-target warnings-as-errors):

| Tool | Pinned | Local (2026-10-12) |
|---|---|---|
| `xcodegen` | `2.46.0` (`XCODEGEN_PIN` in `ci_post_clone.sh`) | 2.46.0 |
| `swiftlint` | `0.65.1` (`SWIFTLINT_PIN` in `ci_pre_xcodebuild.sh`) | 0.65.1 |
| Xcode (Cloud selection) | nearest 27.x | 27.0 (27A266a) |

Cloud usage is metered in App Store Connect (Users and Access → Xcode Cloud tab; per-app tab; CSV export). The account holds 25 compute-hours/mo free — archive-only (a few tag builds/month) fits comfortably; the Oct 2026 PR-frequency setup (137 builds / 33h 31m) burned 97% of quota and motivated this move back to GitHub runners. GitHub `macos-15` runners bill at 10× minutes — the `ios/**` path filters (backend-only PRs run nothing iOS-side) are the cost control.

Plus the **advisory, on-demand** stage-1 AI review (`ai-review.yml`, OpenCodeReview on Ollama Cloud's `deepseek-v4.1-flash`; trigger: comment `/review` on a PR) — see `docs/review-process.md`; it posts review comments but never blocks.

## New-target checklist (extensions, widgets, watch apps)

Adding an Xcode target with its own `info.properties` versions or `Info.plist` (e.g. the `LifioLiveActivities` widget extension, which broke the `0.2.1` release with a duplicate-key guard failure) MUST update the pipelines in the same PR:

1. **`release.yml`** — add the target's Release `Info.plist` to `RELEASE_PLISTS` in the Bump step (the single source of truth — "Commit and push" consumes it via step outputs); keep its `CFBundleShortVersionString`/`CFBundleVersion` in `project.yml` equal to the app's (App Store rejects skewed bundles). A target with a *generated* plist (`GENERATE_INFOPLIST_FILE: YES`, e.g. the `LifioLiveActivityCore` framework) has no plist to mirror — wire `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` build settings instead (missing keys fail App Store validation with ITMS-90057); the workflow bumps them in lockstep. Debug (`Info-Debug.plist`, unmanaged) stays pinned — release bumps never touch it.
2. **`ios.yml` scheme** — confirm the `TimeOfLife` scheme builds/tests cover the new target (the `ios.yml` `lint-build-test` job builds the same scheme — gaps weaken every PR and the `verify` job that gates the tag-triggered Archive; the `RELEASE_PLISTS` wiring in item 1 stays GitHub-side). No per-target dSYM wiring is needed — `ci_post_xcodebuild.sh` uploads the whole Cloud archive's dSYMs, and the `sentry-dsym` job archives the same scheme unsigned.
3. **Path filters** — if the target introduces a new top-level directory, extend the `on:` path filters of every affected GitHub workflow so PRs touching it still trigger CI.

## Stages (`backend.yml`)

| Stage | Trigger | What runs |
|---|---|---|
| `lint-and-test` | Backend PR + backend push to `main` + manual dispatch | gofmt, vet, golangci-lint, `go test ./... -race -coverprofile`, coverage gate (floor 45%, ratchets up) |
| `deploy` | Backend push to `main` + manual dispatch | requires `lint-and-test` green; builds/pushes the image and deploys to the selected environment |

The OpenAPI contract gate runs inside `go test ./...` (`internal/contract/openapi_test.go`) — a spec/handler drift fails every PR automatically.

## Running CI locally

The Makefile exposes the CI checks plus optional local diagnostics:

```bash
cd backend
make lint          # gofmt + vet + golangci-lint  (matches CI lint stage)
make test:race     # go test ./... -race          (matches CI test step)
make test:pg       # Optional PostgreSQL parity    (needs Docker; not currently a CI job)
make test:cover    # coverage + per-function report
```

## Secrets checklist

Required secrets — GitHub Actions secrets (repo Settings → Secrets and variables → Actions) plus Xcode Cloud shared secret env vars (App Store Connect; the Sentry rows below):

| Secret | Used by | Required |
|---|---|---|
| `OLLAMA_API_KEY` | ai-review (stage-1 review, Ollama Cloud) | ✅ |
| `VM_HOST` | deploy | ✅ |
| `VM_USER` | deploy | ✅ |
| `VM_SSH_KEY` | deploy | ✅ |
| `DB_PASSWORD` | deploy | ✅ |
| `JWT_SECRET` | deploy | ✅ (≥32 bytes) |
| `AWS_ACCESS_KEY_ID` | deploy (EMAIL_BACKEND=ses) | only when SES |
| `AWS_SECRET_ACCESS_KEY` | deploy (EMAIL_BACKEND=ses) | only when SES |
| `APPLE_CLIENT_ID` | deploy (optional feature) | only when Apple enabled |
| `SENTRY_AUTH_TOKEN` | Xcode Cloud shared secret env (`ci_post_xcodebuild.sh` dSYM upload auth) | only when Sentry wired; absent = upload skips with a warning |
| `SENTRY_ORG` | Xcode Cloud shared secret env (Sentry org slug) | only when Sentry wired; absent = upload skips with a warning |
| `SENTRY_PROJECT_STAGING` | Xcode Cloud shared secret env (staging project slug) | only when Sentry wired; absent = staging upload skips |
| `SENTRY_PROJECT_RELEASE` | Xcode Cloud shared secret env (release project slug) | only when Sentry wired; absent = release upload skips |
| `SENTRY_DSN` | Xcode Cloud shared secret env, threaded into the Cloud archive (value migrated from the `SENTRY_IOS_DSN` key still declared in `ios.yml`'s `workflow_call` secrets) + backend deploy (rendered into VM `.env`) | only when Sentry wired; absent = shipped binary ships with reporting off |
| `HC_PING_URL` | backend deploy (installs the every-minute dead-man's-switch cron pinger) | only when Healthchecks wired; absent = install skips with a warning |

Non-secret variables: `EMAIL_BACKEND`, `AWS_REGION`, `SES_FROM` (set as repository variables).

## Troubleshooting

- **PostgreSQL behavior needs verification** — run `make test:pg` locally after starting PostgreSQL; parity is not currently a CI job.
- **Coverage gate fails** — total coverage dropped below the floor; add/keep tests. Raise the floor in `backend.yml` as coverage grows.
- **Workflow not triggering** — workflow file paths must match the `on:` path filters (`backend/**`, `.github/workflows/backend.yml`); for iOS, the PR must touch `ios/**` or `ios.yml`'s path filter skips it by design.
- **Cloud build fails on version assert** (`expected XCODEGEN_PIN/SWIFTLINT_PIN`) — Homebrew drifted: confirm the new version locally (`xcodegen generate` diff clean + `swiftlint lint --strict` green), then bump the pin in `ci_scripts/` and the pin table above in the same PR.
- **GitHub `ios` check missing on a PR** — verify the PR touches `ios/**` (path filter) and branch protection still requires `ios / lint-build-test` (Settings → branch protection for `main`).
- **AI review missing after /review** — check the `OLLAMA_API_KEY` secret exists (Ollama Cloud key from ollama.com → Settings → Keys) and the job didn't skip (the comment must be on a PR, contain `/review`, and not come from a bot). Rules/tuning per `docs/review-process.md` and `.opencodereview/rule.json`.

## Worktrees and rebase discipline

Code work runs in an isolated worktree (`timeOfLife.wt/<change-name>`, one branch per worktree); the main checkout stays clean. Worktrees change where you run CI-local checks, not what runs: `make lint` / `make test:race` (backend) and `xcodegen` / `swiftlint` / `xcodebuild` (iOS) execute inside the worktree. `git fetch origin` + rebase onto `origin/main` happens before implementing and again before opening the PR — re-run the affected subsystem's checks after each rebase (a rebase can silently invalidate a green run).
