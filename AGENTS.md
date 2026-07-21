# AGENTS.md

Context for AI agents working in this repository. Read this first. (Requirements `Common.md` S7.)

## What this is
**Time of Life** — a personal time-tracking iOS app. The repo contains the **auth MVP** (passwordless email-OTP sign-up/sign-in) and the first **time-tracking MVP** screen (start/stop timer with offline-first local persistence).

Requirements live in `Requirements/FURPS/` (the FURPS+ table) and `Requirements/Usecases/` (use-case narratives). The auth requirements are `Requirements/FURPS/Sign-up_and_Sign-in.md`.

The **design system** lives in `Design/` — see `Design/README.md`. All visual, component, and interaction decisions for iOS are specified there as Markdown so they can be implemented deterministically.

## Repo layout
```
backend/                 Go backend (chi + pgx/Postgres; sqlite for tests)
  api/openapi.yaml      OpenAPI 3.0 spec (S10 — authoritative API contract)
  cmd/server/main.go     entrypoint (run() int pattern; os.Exit owns lifecycle)
  internal/
    auth/                token service (JWT + rotated refresh) + otp service
    handlers/            HTTP handlers for the 5 endpoints
    server/              chi router + middleware (recoverer, logger, jwtAuth)
    db/                  Store interface + postgres + sqlite impls
    migrations/          embedded SQL migrations (go:embed)
    email/               Sender (console + mailgun) + localized bodies
    ratelimit/           in-memory token bucket
    config/              env config (fail-fast JWT_SECRET ≥32 bytes)
  Dockerfile             Multi-stage Docker build (alpine)
  docker-compose.yml     Local dev: PostgreSQL service
  docker-compose.prod.yml Production: PostgreSQL + backend + nginx (SSL)
  nginx/                 Nginx configs (SSL termination, reverse proxy)
  deploy.sh              CI/CD deploy script
  Makefile               Common commands (build, test, lint, run, deploy)
ios/TimeOfLife/          SwiftUI app (iOS 15+), XcodeGen-managed (project.yml)
  TimeOfLife/Features/Auth/        passwordless flow: EmailEntry → OtpEntry → SignedIn
  TimeOfLife/Features/TimeTracking/  start/stop timer, TimeEntry model, TimerService + LocalTimerStore
  TimeOfLife/Core/                 networking, keychain, reachability, theme, navigation, DI, design components
  TimeOfLife/Localization/         en + ru Localizable.strings + L10n enum
.github/workflows/       CI: backend.yml + ios.yml (mandatory on every PR)
.golangci.yml            Go linters (run from backend/)
ios/TimeOfLife/.swiftlint.yml   Swift linters (run from ios/TimeOfLife/)
```

## Build, test, run
### Backend (Go 1.22+)
```bash
cd backend
go build ./...
go test ./... -cover            # tests use SQLite — no Docker needed
golangci-lint run               # linters (S6)
gofmt -l .                      # must be empty
go vet ./...
# Real run (needs Postgres):
cp .env.example .env            # DATABASE_URL, JWT_SECRET (≥32 bytes), EMAIL_BACKEND=console, OTP_*
docker-compose up -d postgres
go run ./cmd/server             # serves http://127.0.0.1:8080
```
### iOS (Xcode 16+, xcodegen, swiftlint)
```bash
cd ios/TimeOfLife
xcodegen generate
swiftlint lint --strict         # linters (S6); --fix autocorrects
xcodebuild -scheme TimeOfLife \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' build|test
# Magic link for manual testing:
xcrun simctl openurl booted timeoflife://verify?code=123456
```

## API contract (`/api/v1`)

**The authoritative API specification is [`backend/api/openapi.yaml`](backend/api/openapi.yaml) (OpenAPI 3.0, S10).** This table is a summary — always consult the OpenAPI spec for the full schema, error codes, and examples.

Uniform error envelope: `{ "error": { "code": String, "message": String, "details": {} } }`.

| Method | Path | Body | Success | Error codes |
|---|---|---|---|---|
| POST | `/auth/otp/request` | `{email}` | 202 (always) | `invalid_body`, `rate_limited` |
| POST | `/auth/otp/verify` | `{email,code}` | 200 `{access_token,refresh_token,user}` | `invalid_otp`, `otp_expired`, `otp_attempts_exceeded`, `rate_limited`, `invalid_body` |
| POST | `/auth/refresh` | `{refresh_token}` | 200 new pair | `invalid_refresh`, `token_reuse`, `token_expired` |
| POST | `/auth/logout` | (Bearer) | 204 | (401) |
| GET  | `/auth/me` | (Bearer) | 200 `user` | (401) |

The iOS `RemoteAuthRepository` mirrors these paths exactly. If you change an endpoint, change both sides and update [`backend/api/openapi.yaml`](backend/api/openapi.yaml).

## Auth model (passwordless)
Enter email → `otp/request` (always 202, account auto-created unverified) → server emails a 6-digit code → `otp/verify` → marks verified + issues JWT access (15 min) + rotated refresh. The OTP proves email ownership — there is no separate "verify email" step and no password anywhere (R1). OTP codes and refresh tokens are stored only as **SHA-256 hashes**; tokens live in the iOS **Keychain**. `otp/request` and `otp/verify` are rate-limited per IP+email. The email body puts the 6-digit code on its own line for iOS `.oneTimeCode` autofill (U5); the template is configurable via `OTP_EMAIL_TEMPLATE` and may need empirical tuning.

## Coding standards (Requirements S5)
Keep code **minimal and standardized**, following modern best practices.
- **Backend (Go):** idiomatic Go; `gofmt`-formatted (tabs); table-free errors via the domain error types in `internal/`; `context.Context` first param; no `panic` in request paths; `log/slog` only (never log codes/tokens/bodies/emails at info). No new deps without strong justification (S1: mainstream).
- **iOS (Swift):** SwiftUI, MVVM + Repository, all dependencies injected via `AppContainer`; every layer replaceable in tests; `@MainActor` on view models; views use only `Theme` semantic colors (no raw `Color` literals); user-facing strings via `L10n`/`Localizable.strings` (never hard-coded); iOS 15+ only with availability guards for iOS 16+ APIs.
- **Tests (S3):** logic layer ~100% covered. Backend `go test` (SQLite, no Docker); iOS SwiftTesting. Don't leave failing tests; don't lower coverage by deleting tests.
- **Security (R1):** never persist/log passwords, OTP codes, or tokens in plaintext. Secrets from env. Keep user-enumeration closed (`otp/request` always 202).
- **Locales (U4):** every new user-facing string must be added to **both** `en.lproj` and `ru.lproj`, and to the `L10n` enum's `allCases` in `LocalizationTests` if enumerated.

## Per-iteration revising process (Requirements S5)
On every iteration (feature/fix PR) the author MUST:
1. Run both linters and fix every finding: `golangci-lint run` (backend), `swiftlint lint --strict` (iOS); `gofmt -l .` must be empty.
2. Run both test suites green (`go test ./...`; `xcodebuild test`).
3. Re-read the relevant `Requirements/FURPS/*.md` rows and confirm the change aligns; correct the requirements doc if rows conflict (see the passwordless correction as precedent).
4. Update this `AGENTS.md`, the README, the relevant `Design/*.md` files, and [`backend/api/openapi.yaml`](backend/api/openapi.yaml) if architecture/contract/run steps or visual design changed. The OpenAPI spec is the authoritative API contract — keep it in sync with the handlers.
5. Prefer reusing existing utilities/patterns over new code; remove dead code.

## CI (Requirements S6)
`.github/workflows/backend.yml` (Go: gofmt, go vet, golangci-lint, test + coverage) and `.github/workflows/ios.yml` (xcodegen, swiftlint, build, test) run on every PR and on pushes to `main`. Both are **mandatory** PR checks — a PR is not mergeable until both are green.

## Deployment (S4)
The backend is deployed to a **Google Cloud Compute Engine VM** (`timeoflife-backend`, us-east1-b). The production stack runs via Docker Compose:

- **PostgreSQL 15** — database
- **Backend** — Go API server (container image from GHCR)
- **Nginx** — reverse proxy with SSL termination (Let's Encrypt)

### CI/CD pipeline
On every push to `main` that touches `backend/`, the CI/CD pipeline:
1. Runs lint + test (same as PR checks)
2. Builds the Docker image and pushes to `ghcr.io/antonkosenko/time-of-life/backend:latest`
3. SSHs into the VM, pulls the new image, and restarts the backend container

### Manual deploy
```bash
cd backend
make deploy   # or push to main and let CI/CD handle it
```

### Production URL
`https://api.timeoflife.antonkosenko.pro` (once DNS + SSL are configured)

### Required GitHub Actions secrets
| Secret | Description |
|--------|-------------|
| `VM_HOST` | VM external IP |
| `VM_USER` | SSH user (`deploy`) |
| `VM_SSH_KEY` | SSH private key for deployment |

## Deferred / out of scope
- **F2 Sign in with Apple** — stubbed in `ios/TimeOfLife/TimeOfLife/Features/AppleSignIn/` (`// DEFERRED: F2`); not wired into `AppContainer`.
- **Kafka** — deferred (S1 names it but auth MVP doesn't need an MQ).
- **Rate-limit store** — in-memory; swap for Redis before multi-instance deploy.
- **History/list UI for time entries** — local queue exists but no list view yet.
- **Remote time-tracking endpoint** — backend endpoint not implemented; `StubTimerRepository` is used.
- SwiftUI snapshot/on-device keychain tests — manual smoke checklist in README.

## Decisions log (precedents to respect)
- Backend language is **Go** (+3); mobile is **Swift** (+4). Do not reintroduce Swift/Vapor in the backend.
- Auth is **passwordless** — do not reintroduce passwords.
- Tests use **SQLite in-memory** so they run without Docker (S4 local + cloud).
- The Xcode project is **XcodeGen-managed** — edit source, then `xcodegen generate`; do not hand-edit the `.pbxproj`.