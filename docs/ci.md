# CI Pipeline Guide

GitHub Actions quality pipeline for Lifio. Path-filtered workflows provide the applicable mandatory PR checks (Requirements S6):

- **`backend.yml`** — Go: gofmt, go vet, golangci-lint, race tests, OpenAPI contract gate, coverage gate, deploy
- **`ios.yml`** — Swift: xcodegen, swiftlint `--strict`, warnings-as-errors build, unit tests
- **`openspec.yml`** — spec-integrity gate: `openspec validate --all --strict` (CLI pinned 1.8.0) on every PR and push to `main`
- **`release.yml`** — manual `workflow_dispatch` marketing-version bump: validates semver on `main`, bumps every target's versions in `project.yml` in lockstep, mirrors every Release `Info.plist`, commits + tags `vX.Y.Z` (see checklist below — a new target MUST be wired in or the next release fails)

Plus the **advisory, on-demand** stage-1 AI review (`ai-review.yml`, OpenCodeReview on Ollama Cloud's `deepseek-v4.1-flash`; trigger: comment `/review` on a PR) — see `docs/review-process.md`; it posts review comments but never blocks.

## New-target checklist (extensions, widgets, watch apps)

Adding an Xcode target with its own `info.properties` versions or `Info.plist` (e.g. the `LifioLiveActivities` widget extension, which broke the `0.2.1` release with a duplicate-key guard failure) MUST update the pipelines in the same PR:

1. **`release.yml`** — add the target's Release `Info.plist` to `RELEASE_PLISTS` in the Bump step (the single source of truth — "Commit and push" consumes it via step outputs); keep its `CFBundleShortVersionString`/`CFBundleVersion` in `project.yml` equal to the app's (App Store rejects skewed bundles). Debug (`Info-Debug.plist`, unmanaged) stays pinned — release bumps never touch it.
2. **`ios.yml`** — confirm the scheme builds/tests cover the new target (the `verify` job in `release.yml` reuses `ios.yml` via `workflow_call`, so gaps here weaken release verification).
3. **Path filters** — if the target introduces a new top-level directory, extend the `on:` path filters of every affected workflow so PRs touching it still trigger CI.

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

Required GitHub Actions secrets (configured in repo Settings → Secrets and variables → Actions):

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

Non-secret variables: `EMAIL_BACKEND`, `AWS_REGION`, `SES_FROM` (set as repository variables).

## Troubleshooting

- **PostgreSQL behavior needs verification** — run `make test:pg` locally after starting PostgreSQL; parity is not currently a CI job.
- **Coverage gate fails** — total coverage dropped below the floor; add/keep tests. Raise the floor in `backend.yml` as coverage grows.
- **Workflow not triggering** — workflow file paths must match the `on:` path filters (`backend/**`, `.github/workflows/backend.yml`).
- **AI review missing after /review** — check the `OLLAMA_API_KEY` secret exists (Ollama Cloud key from ollama.com → Settings → Keys) and the job didn't skip (the comment must be on a PR, contain `/review`, and not come from a bot). Rules/tuning per `docs/review-process.md` and `.opencodereview/rule.json`.
