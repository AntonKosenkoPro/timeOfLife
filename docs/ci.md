# CI Pipeline Guide

GitHub Actions carries the mandatory PR checks (Requirements S6); Xcode Cloud is archive-only (TestFlight distribution + signed-dSYM symbolication). Rationale: PR-frequency Cloud builds burned the 25h/month free quota (Oct 2026: 24h 9m used, 137 builds), so iOS verification moved back to allowance-bound GitHub `macos-15` runners.

- **GitHub Actions** — `backend.yml` (Go), `ios.yml` (iOS: xcodegen, SwiftLint, warnings-as-errors build, tests), `backend-release.yml` (pinned backend images on `backend/*` tags), `openspec.yml` (spec gate), advisory `ai-review.yml`
- **Xcode Cloud** — tag workflows only (`internal/*` + `release/*` tags: Archive → TestFlight upload, with `ci_post_xcodebuild.sh` uploading the signed archive's dSYMs to Sentry staging + release; see below). No PR/push verification runs on Cloud (quota).

Workflows and their scope (`ios.yml` carries the iOS PR lint/build/test bar with unfiltered `pull_request` + path-filtered `push`-to-`main` triggers; the tag-triggered Cloud Archive covers the signed Release build + TestFlight upload):

- **`backend.yml`** — Go: gofmt, go vet, golangci-lint, race tests, OpenAPI contract gate, coverage gate, deploy
- **`ios.yml`** — iOS: unfiltered `pull_request` + path-filtered `push`-to-`main`; xcodegen via `xcodegen generate`, SwiftLint `lint --strict`, warnings-as-errors build (per-target `SWIFT_TREAT_WARNINGS_AS_ERRORS`/`GCC_TREAT_WARNINGS_AS_ERRORS` — the Analyse bar, no separate analyzer step), unit tests. dSYMs for shipped builds come from Cloud's signed tag archives (`ci_post_xcodebuild.sh`), not from CI.

## Required gates (ruleset)

Path-filtered workflows report nothing on non-matching PRs, and GitHub leaves those required checks Pending forever (observed: PR #211 blocked with only `validate` reporting). So neither workflow is path-filtered on `pull_request` anymore — instead each has an in-workflow ubuntu `changes` job (`git diff --name-only base...HEAD`, fail-closed to true) gating its lane job, plus an always-run gate job (`ios-gate` / `backend-gate`, `if: always()`) that passes iff the lane ∈ {success, skipped}. The ruleset requires the **gates**, never the lanes: a docs-only PR gets both gates green in seconds with both lanes skipped; a matching PR must pass its lane. Cost of a non-matching PR: two ubuntu jobs, seconds. Detection failures resolve to running the lane (minutes, never a silent skip).
- **`openspec.yml`** — spec-integrity gate: `openspec validate --all --strict` (CLI pinned 1.8.0) on every PR and push to `main`

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

## Releases — manual signed tags

The owner's signed tag push is the single release act — no bot writes to `main`, and tags never move. (The `release.yml` bump workflow was retired in `manual-tag-releases`; tags are the release act.) Tags are SSH/GPG-signed (`-s`), created only on `main`, and never moved or deleted. Tag grammar:

| Tag | Who cuts | What triggers | Where it ships |
|---|---|---|---|
| `internal/vM.m.p[.n]` | owner only (you-only ruleset) | Cloud "iOS Internal Release": Archive | TestFlight Internal (dogfood) |
| `release/vM.m.p[.n]` | owner only (you-only ruleset) | Cloud "iOS Public Release": Archive | TestFlight External / App Store |
| `backend/vM.m.p` | owner only (you-only ruleset) | `backend-release.yml` tag build + push (no `paths:` filter — tag-only pushes carry no commits to match) | GHCR pinned image `backend-<tag>` (pinned only; `:latest` advances on main pushes alone); `/health` reports the tag + short SHA |

The optional fourth-dot sequence (`.n`) re-uploads under the same marketing version without moving a tag: the bare tag is the base (N=0) and explicit re-uploads start at `.1`, so the first re-upload of `internal/v0.3.0` is `internal/v0.3.0.1` — highest sequence wins deterministically. Explicit `.0` is rejected; equal sequences abort as ambiguous. `project.yml` keeps a checked-in dev dummy (e.g. `0.0.0-dev`) so local/simulator builds compile; it never ships — the Cloud stamp parses the tag into `MARKETING_VERSION` / build (channel-banded `(N*2+chanbit)*STRIDE+RUN`: internal and public are separate Cloud workflows with independent run counters, so the public half-band always orders above internal for one marketing line as long as tags are cut dogfood-first) / `CHANNEL`, stamps every target in lockstep after `xcodegen generate`, and fails the archive on skew. Profile shows the channel: internal builds render `v0.2.8 (abc1234) • Internal`, public builds keep `v0.3.0 (e4f5a6b)`, local builds read the dummy.

You-only tag rulesets guard the three namespaces with the owner as the sole bypass actor, so even a compromised workflow cannot cut a release. Branch protection on `main` is untouched.

Runbook:

- **Typo → no build (fail-closed, by design).** A mistyped tag matches no workflow and builds nothing. If nothing builds: check the tag spelling against the grammar table above, then check the Cloud build list (iOS) or the Actions runs (backend).
- **Signing-key loss blocks all releases by design.** Keep the signing key in two places from day one. If it is lost: generate a new key, register it as a signing key, verify with `git tag -v` on a recent release tag, and cut future releases with the new key. Existing tags stay verifiable under the old key (signatures persist) — never move or re-cut an old tag; cut a new tag instead.
- **Rollback is revert-forward.** iOS: never move a tag — `git revert` the offending commit and cut a new tag through the internal channel first (installed apps can't downgrade; App Store Connect retains every build; halt a phased rollout while verifying). Backend: dispatch `backend.yml` **from `main`** with `environment: backend-prod` (or `stage`), `image_tag: backend-vX.Y.Z`, **and `skip_checks: true`** — lint/test and the source rebuild are skipped so a rollback never blocks on the red tree it escapes; the VM pulls the pinned image instead. Rollback dispatches run in their own concurrency group, but a concurrent normal deploy on the VM is prevented by procedure (single operator — never dispatch both at once), not by locking. Never hand-edit deploy-managed files on the VM.

GH environments: `backend-prod` exists (wait timer + main-only branch policy); `testflight-internal` / `testflight-public` with a wait timer are Phase 3 (approval gate + deployment timeline). Until then Cloud status is reconciled manually.

Cloud tag-workflow names are pinned — the stamp script maps `CI_WORKFLOW` to the release channel, and same-commit promotion (`internal/vX` + `release/vX`) depends on these exact names: **"iOS Internal Release"** cuts internal, **"iOS Public Release"** cuts public. Keep them in sync with `ci_post_clone.sh` if they ever change.

## New-target checklist (extensions, widgets, watch apps)

Adding an Xcode target with its own `info.properties` versions or `Info.plist` (e.g. the `LifioLiveActivities` widget extension, which broke the `0.2.1` release with a duplicate-key guard failure) MUST update the pipelines in the same PR:

1. **Stamp script + `project.yml` lockstep** — keep the target's `CFBundleShortVersionString`/`CFBundleVersion` in `project.yml` equal to the app's (App Store rejects skewed bundles) and add the target to the version-stamp list in `ci_post_clone.sh` (the single source of truth — the build-time unanimity assert fails the archive on skew). A target with a *generated* plist (`GENERATE_INFOPLIST_FILE: YES`, e.g. the `LifioLiveActivityCore` framework) has no plist to stamp — wire `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` build settings instead (missing keys fail App Store validation with ITMS-90057). Debug (`Info-Debug.plist`, unmanaged) stays pinned — stamping never touches it.
2. **Scheme coverage on both providers** — confirm the `TimeOfLife` scheme builds/tests cover the new target: the `ios.yml` `lint-build-test` job builds the same scheme (gaps weaken every PR) and the tag-triggered Cloud Archive ships it (gaps weaken releases); the stamp-list wiring in item 1 runs Cloud-side. No per-target dSYM wiring is needed — `ci_post_xcodebuild.sh` uploads the whole Cloud archive's dSYMs.
3. **Path filters** — if the target introduces a new top-level directory, extend the `on:` path filters of every affected GitHub workflow AND the Cloud workflow's file filters so PRs touching it still trigger CI.

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
| `SENTRY_DSN` | Xcode Cloud shared secret env, threaded into the Cloud archive (value migrated from the `SENTRY_IOS_DSN` key still declared in `ios.yml`'s `secrets:` block) + backend deploy (rendered into VM `.env`) | only when Sentry wired; absent = shipped binary ships with reporting off |
| `HC_PING_URL` | backend deploy (installs the every-minute dead-man's-switch cron pinger) | only when Healthchecks wired; absent = install skips with a warning |

Non-secret variables: `EMAIL_BACKEND`, `AWS_REGION`, `SES_FROM` (set as repository variables).

## Troubleshooting

- **PostgreSQL behavior needs verification** — run `make test:pg` locally after starting PostgreSQL; parity is not currently a CI job.
- **Coverage gate fails** — total coverage dropped below the floor; add/keep tests. Raise the floor in `backend.yml` as coverage grows.
- **Workflow not triggering** — `push` runs keep their `on:` path filters (`backend/**`, `ios/**`); `pull_request` is unfiltered by design so the gates always report — lane path selection happens in the `changes` job.
- **Cloud build fails on version assert** (`expected XCODEGEN_PIN/SWIFTLINT_PIN`) — Homebrew drifted: confirm the new version locally (`xcodegen generate` diff clean + `swiftlint lint --strict` green), then bump the pin in `ci_scripts/` and the pin table above in the same PR.
- **PR stuck on Pending checks** — a required check that never reports means its workflow was path-skipped: the fix is the gate model above (require `ios-gate`/`backend-gate`, never the lanes). If gates are required and still pend, the gate job itself failed to run — check the workflow run list, not the paths.
- **GitHub `ios` check missing on a PR** — the lane runs only when the PR diff touches `ios/**` (in-workflow filter); the `ios-gate` check must report on every PR regardless. Ruleset must require `ios-gate` (Settings → Rulesets → `main protection`), not `lint-build-test`.
- **Pushed a tag but nothing builds** — the tag matches no workflow (fail-closed by design): check the spelling against the release grammar table above, then check the Cloud build list (iOS) or the Actions runs (backend).
- **AI review missing after /review** — check the `OLLAMA_API_KEY` secret exists (Ollama Cloud key from ollama.com → Settings → Keys) and the job didn't skip (the comment must be on a PR, contain `/review`, and not come from a bot). Rules/tuning per `docs/review-process.md` and `.opencodereview/rule.json`.

## Worktrees and rebase discipline

Code work runs in an isolated worktree (`timeOfLife.wt/<change-name>`, one branch per worktree); the main checkout stays clean. Worktrees change where you run CI-local checks, not what runs: `make lint` / `make test:race` (backend) and `xcodegen` / `swiftlint` / `xcodebuild` (iOS) execute inside the worktree. `git fetch origin` + rebase onto `origin/main` happens before implementing and again before opening the PR — re-run the affected subsystem's checks after each rebase (a rebase can silently invalidate a green run).
