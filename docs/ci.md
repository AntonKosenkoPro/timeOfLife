# CI Pipeline Guide

GitHub Actions quality pipeline for Time of Life. Two path-filtered workflows provide the applicable mandatory PR checks (Requirements S6):

- **`backend.yml`** — Go: gofmt, go vet, golangci-lint, race tests, OpenAPI contract gate, coverage gate, deploy
- **`ios.yml`** — Swift: xcodegen, swiftlint `--strict`, warnings-as-errors build, unit tests

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
