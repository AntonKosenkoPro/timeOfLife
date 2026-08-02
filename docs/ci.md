# CI Pipeline Guide

GitHub Actions quality pipeline for the Time of Life backend. Two workflows are mandatory PR checks (Requirements S6):

- **`backend.yml`** — Go: gofmt, go vet, golangci-lint, race tests, OpenAPI contract gate, coverage gate, PostgreSQL parity, nightly burn-in, deploy
- **`ios.yml`** — Swift: xcodegen, swiftlint `--strict`, warnings-as-errors build, unit tests

## Stages (`backend.yml`)

| Stage | Trigger | What runs |
|---|---|---|
| `lint-and-test` | PR + push | gofmt, vet, golangci-lint, `go test ./... -race -coverprofile`, coverage gate (floor 45%, no-regression; ratchets up) |
| `postgres-parity` | PR + push | Real PostgreSQL (service container) + `go test ./internal/db -run Postgres` (R-007: SQLite-only CI cannot mask production behavior drift) |
| `nightly-burn-in` | cron `0 2 * * *` | `go test ./... -race -count=3` — flake detection (R-012); failure artifacts uploaded; no retry-to-green |
| `deploy` | push to main, workflow_dispatch | requires `lint-and-test` + `postgres-parity` green |

The OpenAPI contract gate runs inside `go test ./...` (`internal/contract/openapi_test.go`) — a spec/handler drift fails every PR automatically.

## Running CI locally

The Makefile mirrors CI exactly (no Docker needed except parity):

```bash
cd backend
make lint          # gofmt + vet + golangci-lint  (matches CI lint stage)
make test:race     # go test ./... -race          (matches CI test step)
make test:pg       # PostgreSQL parity            (needs Docker, matches CI parity job)
make test:cover    # coverage + per-function report
```

## Secrets checklist

Required GitHub Actions secrets (configured in repo Settings → Secrets and variables → Actions):

| Secret | Used by | Required |
|---|---|---|
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

- **Parity job fails but local tests pass** — you only ran SQLite tests. Run `make test:pg` locally; the failure is real PostgreSQL behavior drift (R-007).
- **Coverage gate fails** — total coverage dropped below the floor; add/keep tests. Raise the floor in `backend.yml` as coverage grows.
- **Burn-in finds a flake** — don't retry it into green (policy). Investigate the timing-sensitive test (R-012: inject clocks, await state, add barriers).
- **Workflow not triggering** — workflow file paths must match the `on:` path filters (`backend/**`, `.github/workflows/backend.yml`).
