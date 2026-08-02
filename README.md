# Time of Life

A personal time-tracking app for iOS — minimal-effort tracking of where your time goes (widgets, shortcuts, integrations). This repository contains the **auth MVP** (passwordless email + OTP) and the first **time-tracking MVP** screen (start/stop timer with offline-first persistence).

See [`Requirements/FURPS/`](Requirements/FURPS/) for the full requirements, [`AGENTS.md`](AGENTS.md) for context for AI agents, and [`Design/`](Design/) for the text-based design system (colors, components, screen specs, and interaction patterns). This MVP implements **F1** (passwordless email-OTP sign up/in), **F2** (Sign in with Apple), the supporting infrastructure, and the first time-tracking use case. **F3** (restore access by email) is subsumed by the OTP flow (no password to reset).

## Architecture

Monorepo with two subsystems that share a JSON API contract:

```
backend/   Go (chi + pgx/PostgreSQL, sqlite for tests) — REST API under /api/v1
ios/       SwiftUI app (iOS 15+) — MVVM + Repository, keychain token storage
```

### Auth flow (passwordless)
1. **Enter email** → `POST /auth/otp/request` → server upserts the user (created unverified on first request) and emails a 6-digit OTP code. Always 202 (no enumeration).
2. **Enter the code** (autofilled from the email via `.oneTimeCode`, or typed) → `POST /auth/otp/verify` → server marks the user verified and issues an access + refresh token pair. This proves email ownership, so there is no separate "verify email" step.
3. **Refresh** with rotation: each refresh issues a new pair and revokes the old token; reuse of a revoked token revokes *all* the user's sessions (`token_reuse`).

### Auth flow (Sign in with Apple)
1. **Tap "Sign in with Apple"** on the email screen → the app requests an Apple identity token (`ASAuthorizationAppleIDProvider`, `.fullName`/`.email` scopes).
2. **`POST /auth/apple`** `{ identity_token }` → the backend verifies Apple's RS256 JWT against Apple's JWKS (`iss`/`aud`=Bundle ID/`exp`), upserts a user keyed by Apple's stable `sub` claim, and issues the same access + refresh token pair as the OTP flow.
3. The app persists the session and lands on the timer screen — same path as OTP sign-in.

**Config-gated:** the backend registers `/auth/apple` only when `APPLE_CLIENT_ID` is set (the app's Bundle ID). The iOS button renders without the capability; the actual authorization requires the **Sign in with Apple** capability + a paid Apple Developer Program membership (see `project.yml` signing note). Account-deletion token revocation (App Store 5.1.1v) is a follow-up.

### Time tracking flow (MVP)
1. **Signed-in home** shows the timer screen.
2. **Start** an activity: type a name and tap **Start**.
3. **Timer counts up** while running; the device stays awake.
4. **Stop** saves the entry: online → saved locally and synced remotely; offline → queued locally and synced when connectivity returns.
5. Entries are stored in `Application Support/TimeOfLife/timerQueue.json`.

### Security (R1)
- **No passwords anywhere.** Accounts authenticate by proving email ownership via an OTP code (stored only as a **SHA-256 hash**, 10-min expiry, max 5 attempts).
- **JWT access token** (HS256, 15 min) + **opaque refresh token** stored as a **SHA-256 hash** in the DB, rotated on every use with reuse detection.
- iOS stores tokens in the **Keychain** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) — never `UserDefaults`, never logged.
- Protected requests refresh an expired access token once; an invalid/reused refresh token clears the local session and returns the app to sign-in, while offline refresh failures keep the cached session.
- ATS scoped to `127.0.0.1` only — never arbitrary loads; production must be HTTPS.
- No user enumeration: `/auth/otp/request` always returns 202.
- In-memory per-IP+email rate limiting on `otp/request` + `otp/verify` (swap for Redis before multi-instance).
- `log/slog` logging never touches codes, tokens, or request bodies.

## Backend (`/backend`) — Go

Stack: Go 1.24, `go-chi/chi/v5`, `jackc/pgx/v5` (Postgres), `modernc.org/sqlite` (pure-Go, no CGO — for tests), `golang-jwt/jwt/v5`, `joho/godotenv`, `crypto/sha256`. Email via a `Sender` interface — `ConsoleSender` (prints the OTP code to stdout, dev/test) and `SESSender` (AWS SES, prod). No bcrypt (no passwords).

### Run (with Docker)
```bash
cd backend
cp .env.example .env        # set DATABASE_URL, JWT_SECRET (≥32 bytes), EMAIL_BACKEND=console, OTP_*
docker-compose up -d postgres
go run ./cmd/server         # auto-migrates, serves http://127.0.0.1:8080
```
In dev, watch stdout for the printed OTP code.

### Tests & lint (no Docker required)
Tests run against an in-memory SQLite store so `go test` is fully self-contained:
```bash
cd backend
gofmt -l .                  # must be empty (formatting)
go vet ./...                # built-in analysis
golangci-lint run           # linters (S6): govet, staticcheck, errcheck, unused, revive, gocritic, bodyclose, nilerr, misspell
go test ./...               # all packages green
go test ./... -cover        # handlers/services ≥90% (auth 93.6%, handlers 93.0%, email 92.6%, ratelimit 90.5%, server 90.2%)
```
Lint config: `backend/.golangci.yml`.

## iOS (`/ios`)

SwiftUI, iOS 15+. Project is generated via **XcodeGen** from `ios/TimeOfLife/project.yml`.

### Run
```bash
cd ios/TimeOfLife
xcodegen generate           # regenerates TimeOfLife.xcodeproj from project.yml
open TimeOfLife.xcodeproj
```
- `API_BASE_URL` is injected into `Info.plist` from a per-configuration xcconfig: `Config.Debug.xcconfig` → `http://127.0.0.1:8080` (start the backend first), `Config.Release.xcconfig` → `https://timeoflife-api.antonkosenko.pro` (production). ATS allows plain HTTP only to `127.0.0.1`; production is HTTPS so no ATS exception is needed.
- Code signing is disabled in `project.yml` (no Apple Developer account required) so simulator and CI builds work out of the box. To ship via TestFlight/App Store later, set `DEVELOPMENT_TEAM` and enable distribution signing (see comment in `project.yml`).
- On Simulator the host's `127.0.0.1` is reachable directly; a physical device needs your LAN IP instead.

### Tests & lint
```bash
cd ios/TimeOfLife
swiftlint lint --strict     # linters (S6); `--fix` autocorrects. Config: .swiftlint.yml
xcodebuild -scheme TimeOfLife \
  -destination 'generic/platform=iOS Simulator' \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  GCC_TREAT_WARNINGS_AS_ERRORS=YES build
```
Use an available simulator destination for `xcodebuild test`; the CI workflow resolves one dynamically.
Unit tests cover the email/OTP validators, the API client (incl. 401→refresh→retry and offline mapping via a URLProtocol stub), repositories, the AuthService (keychain/cache/restore-on-offline), and the auth view-models. Out of scope: SwiftUI snapshot tests and on-device keychain (see smoke checklist below).

## Code quality & CI (S5/S6/S7)
- **Linters (S6):** Go `golangci-lint` (`backend/.golangci.yml`), Swift `swiftlint` (`ios/TimeOfLife/.swiftlint.yml`), plus `.editorconfig`. Both must pass with zero findings before merge; iOS `xcodebuild` compiler warnings are also treated as errors.
- **CI on every PR (S6):** `.github/workflows/backend.yml` (gofmt, go vet, golangci-lint, test + coverage) and `.github/workflows/ios.yml` (xcodegen, swiftlint, warning-as-error xcodebuild build, test) run on every PR and on pushes to `main`. Both are mandatory PR checks.
- **Standards + revising process (S5):** code is kept minimal and standardized; every iteration runs linters + tests, re-checks the relevant `Requirements/FURPS/*.md` rows, and updates docs if the architecture changes (see `AGENTS.md`).
- **AI agent context (S7):** [`AGENTS.md`](AGENTS.md) holds repo layout, build/test/run, the API contract, coding standards, the per-iteration revising process, and the decisions log.

## Deployment

The backend is deployed to a **Google Cloud Compute Engine VM** (`timeoflife-backend`, us-east1-b). The production stack runs via Docker Compose with three services: PostgreSQL 15, the Go backend, and Nginx (reverse proxy with Let's Encrypt SSL).

### CI/CD
On every push to `main` that touches `backend/`, the CI/CD pipeline (`.github/workflows/backend.yml`) runs lint + test, builds the Docker image, pushes to `ghcr.io`, and deploys to the VM.

### Production URL
`https://timeoflife-api.antonkosenko.pro`

> **Hostname note:** the API lives at a single-label subdomain (`timeoflife-api.antonkosenko.pro`) rather than `api.timeoflife.antonkosenko.pro` so it is covered by Cloudflare's Universal SSL edge certificate (`*.antonkosenko.pro`). Deeper subdomains like `api.timeoflife.…` are *not* covered by Universal SSL and cause an edge TLS `handshake_failure` (alert 40).

### Local production-like test
```bash
cd backend
docker compose -f docker-compose.prod.yml up -d
```

## API contract (`/api/v1`)

**The authoritative API specification is [`backend/api/openapi.yaml`](backend/api/openapi.yaml) (OpenAPI 3.0, S10).** This table is a summary — always consult the OpenAPI spec for the full schema, error codes, and examples.

Errors use a uniform envelope: `{ "error": { "code", "message", "details": {} } }`.

| Method | Path | Body | Success | Error codes |
|---|---|---|---|---|
| POST | `/auth/otp/request` | `{email}` | 202 (always) | `invalid_body`, `rate_limited` |
| POST | `/auth/otp/verify` | `{email,code}` | 200 `{access_token,refresh_token,user{id,email,email_verified}}` | `invalid_otp`, `otp_expired`, `otp_attempts_exceeded`, `rate_limited`, `invalid_body` |
| POST | `/auth/apple` | `{identity_token}` | 200 `{access_token,refresh_token,user}` | `invalid_body`, `invalid_apple_token`, `rate_limited`, `apple_not_configured` |
| POST | `/auth/refresh` | `{refresh_token}` | 200 new pair | `invalid_refresh`, `token_reuse`, `token_expired` |
| POST | `/auth/logout` | (Bearer) | 204 | (401) |
| GET  | `/auth/me` | (Bearer) | 200 `user{id,email,email_verified}` | (401) |
| GET  | `/activities` | (Bearer) | 200 `[{activity}]` (recency; `?q=` typeahead) | (401) |
| POST | `/activities` | `{id,name,color,icon,notes?,category_ids?}` | 201/200 `{activity}` (idempotent on `id`) | `validation_error`, `activity_exists`, `conflict` |
| GET/PATCH/DELETE | `/activities/{id}` | (PATCH) `{…,updated_at}` | 200 / 204 | `not_found`, `conflict`, `activity_exists` |
| GET  | `/categories` | (Bearer) | 200 `[{category}]` | (401) |
| POST | `/categories` | `{id,name,color}` | 201/200 `{category}` (idempotent on `id`) | `validation_error`, `category_exists`, `conflict` |
| PATCH/DELETE | `/categories/{id}` | (PATCH) `{…,updated_at}` | 200 / 204 | `not_found`, `conflict`, `category_exists` |
| GET  | `/entries` | (Bearer) | 200 `{items,next_cursor?}` (`?from=&to=&activity_id=&category_id=&limit=&cursor=`) | (401) |
| POST | `/entries` | `{id,activity_id,started_at,ended_at?}` | 201/200 `{entry}` (idempotent on `id`; `activity_id` required) | `validation_error`, `activity_not_found`, `conflict` |
| GET/PATCH/DELETE | `/entries/{id}` | (PATCH) `{started_at?,ended_at?,updated_at}` | 200 / 204 | `not_found`, `conflict` |

**Epic 1 (activity catalog & entries):** all `/activities`, `/categories`, `/entries` routes are Bearer-protected. Ids are **client-generated UUID v7** and `POST` is **idempotent on `id`** (offline create-then-sync). Writes use **last-write-wins on `updated_at`** (stale → 409 `conflict` with the server's version in `details`); deletes are hard (the client holds the 30 s undo buffer). Validation failures are 422 `validation_error` with `details` = `{field: message}`. **Suggestions are client-side** (F5) — there is no `/activities/suggestions` endpoint; the client ranks its synced activities by `last_used_at`. See the OpenAPI spec (v1.1.0) for full schemas.

## Manual smoke checklist

### Production deploy smoke test
1. Push to `main` → CI/CD pipeline runs (check GitHub Actions).
2. Pipeline builds Docker image, pushes to GHCR, deploys to VM.
3. `curl -s https://timeoflife-api.antonkosenko.pro/health` → `{"status":"ok"}`
4. `curl -s -X POST https://timeoflife-api.antonkosenko.pro/api/v1/auth/otp/request -H 'Content-Type: application/json' -d '{"email":"test@example.com"}'` → 202
5. Check VM logs: `gcloud compute ssh timeoflife-backend --zone=us-east1-b --command="cd /opt/timeoflife && sudo docker compose logs backend --tail=20"`

Backend (Docker Postgres running):
1. `POST /api/v1/auth/otp/request` `{email}` → 202; console sender prints the code.
2. `POST /api/v1/auth/otp/verify` `{email, code}` (wrong code) → 401 `invalid_otp`.
3. `POST /api/v1/auth/otp/verify` with the correct code → 200 + tokens.
4. Repeat the wrong code 5+ times → `otp_attempts_exceeded`.
5. `POST /api/v1/auth/refresh` → rotated pair; reusing the old refresh → 401 `token_reuse` and all sessions revoked.
6. `GET /api/v1/auth/me` with the Bearer access token → 200 user.
7. `POST /api/v1/activities` `{id:<uuidv7>,name:"Gym",color:"blue",icon:"figure.run"}` → 201; replay the same body → 200 (idempotent).
8. `PATCH /api/v1/activities/{id}` with a stale `updated_at` → 409 `conflict` (LWW); with a newer `updated_at` → 200.
9. `GET /api/v1/activities` → 200 `[{activity}]`; `POST /api/v1/entries` `{id:<uuidv7>,activity_id:<id>,started_at:"…"}` → 201 (omit `activity_id` → 422 `validation_error`).

iOS (Simulator, backend running):
1. Enter email → request OTP → enter/autofill the 6-digit code → timer screen.
2. Switch device language to Russian and toggle dark mode — UI localized + themed.
3. Turn off network (Simulator features) → offline banner, disabled submit, cached session persists across relaunch.

## Requirements coverage (MVP)

`Requirements/FURPS/Common.md` requirements (app-wide):

| Req | Status |
|---|---|
| U1 Minimalistic design | ✅ `Form`-based SwiftUI views, system tokens only |
| U2 Dark/light theme | ✅ `Theme` semantic colors from asset-catalog light/dark sets; follows system |
| U3 Offline-correct | ✅ `NetworkMonitor` + offline banner, disabled submit, cached session restore, logout works offline |
| U4 EN + RU localization | ✅ `en.lproj`/`ru.lproj` + `L10n`; tests assert all keys resolve in both |
| U5 Apple HIG compliance | ✅ Native SwiftUI components, `.submitLabel`, field-focus chaining, interactive keyboard dismiss, semantic colors, Dynamic Type |
| R1 Secure auth storage | ✅ No passwords; OTP + refresh stored as SHA-256 hashes; tokens in Keychain on device |
| S1 Mainstream tech | ✅ Go (chi + PostgreSQL) backend; Kafka deferred |
| S2 Native UI SDK | ✅ SwiftUI |
| S3 Test coverage | ✅ Go tests ≥90% on handlers/services + 277 iOS unit tests; logic-layer ~100%; coverage gating documented |
| S4 Run locally + cloud | ✅ docker-compose local, Dockerfile (Go multi-stage) for cloud deploy; deployed to GCP Compute Engine VM |
| S5 Minimal + standardized code, revising each iteration | ✅ `.editorconfig`; standards + per-iteration checklist in `AGENTS.md` |
| S6 Linters + analyzers guarantee quality | ✅ `golangci-lint` + `swiftlint` + `.editorconfig`; both pass with zero findings |
| S6 Tests + linters run on every GitHub PR (mandatory) | ✅ `.github/workflows/backend.yml` + `ios.yml` — mandatory PR checks |
| S7 `AGENTS.md` for AI agents | ✅ `AGENTS.md` with repo layout, build/test/run, contract, standards, revising process |
| S10 OpenAPI documentation for every backend API | ✅ [`backend/api/openapi.yaml`](backend/api/openapi.yaml) (OpenAPI 3.0) |
| +1 No website | ✅ Pure mobile client + API; no website required |
| +2 iOS 15+ all devices | ✅ Deployment target 15.0; nav polyfill for iOS 15; adaptive layouts |
| +3 Backend in Golang | ✅ Go backend (replaced the earlier Swift/Vapor prototype) |
| +4 Mobile app in Swift | ✅ SwiftUI / Swift |

`Requirements/FURPS/Sign-up_and_Sign-in.md` requirements (auth-specific):

| Req | Status |
|---|---|
| F1 Passwordless email-OTP sign up/in | ✅ |
| F2 Sign in with Apple | ✅ Implemented — config-gated (`APPLE_CLIENT_ID`); requires the Apple capability + signing to run end-to-end |
| F3 Restore access by email | ✅ Subsumed — the email-OTP sign-in flow restores access (no password to reset) |
| U1 Email + OTP validation | ✅ Email format + ≤254 (mirrored backend + iOS `AuthValidator`); OTP exactly 6 digits |
| U2 Errors below editors | ✅ Each field renders its single error directly beneath the editor (`FieldErrorLabel`) |
| U3 Autofill | ✅ Email field `.emailAddress` (Hide my Email); OTP field `.oneTimeCode` + `.numberPad` |
| U4 Unified error messages | ✅ Multiple failed email rules collapse into one sentence via `AuthValidator.unified*Message` + localized `and`-join |
| U5 OTP code from email | ✅ The email shows the 6-digit code on its own line; the iOS OTP field uses `.textContentType(.oneTimeCode)` for QuickType autofilling. Deep links / magic links were removed because custom URL schemes only work in Apple Mail. |

## Deferred / out of scope for this MVP
- **Kafka** — deferred until event-driven needs arise.
- **Rate-limit backing store** — in-memory now; Redis before multi-instance deploy.
- **OTP email template** — current format targets iOS autofill detection; `OTP_EMAIL_TEMPLATE` makes it swappable for tuning.
- **Multi-device session management UI** — `device_id` is captured but no list/revoke UI.
- **Sign in with Apple follow-ups** — account-deletion token revocation via Apple `/auth/revoke` (App Store 5.1.1v), nonce replay defense, and Apple credential-state/revocation observation. The `POST /auth/apple` shape won't change when these land.
- SwiftUI snapshot/UI tests and on-device keychain tests — covered by the manual smoke checklist.
