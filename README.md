# Time of Life

A personal time-tracking app for iOS — minimal-effort tracking of where your time goes (widgets, shortcuts, integrations). This repository currently contains the **first MVP: authentication only** — **passwordless** email + OTP.

See [`Requirements/FURPS/`](Requirements/FURPS/) for the full requirements and [`AGENTS.md`](AGENTS.md) for context for AI agents. This MVP implements **F1** (passwordless email-OTP sign up/in) and the supporting infrastructure. **F2** (Sign in with Apple) is **deferred** and stubbed. **F3** (restore access by email) is subsumed by the OTP flow (no password to reset).

## Architecture

Monorepo with two subsystems that share a JSON API contract:

```
backend/   Go (chi + pgx/PostgreSQL, sqlite for tests) — REST API under /api/v1
ios/       SwiftUI app (iOS 15+) — MVVM + Repository, keychain token storage
```

### Auth flow (passwordless)
1. **Enter email** → `POST /auth/otp/request` → server upserts the user (created unverified on first request) and emails a 6-digit OTP code. Always 202 (no enumeration).
2. **Enter the code** (autofilled from the email via `.oneTimeCode`, or typed) → `POST /auth/otp/verify` → server marks the user verified and issues an access + refresh token pair. This proves email ownership, so there is no separate "verify email" step.
3. **Magic link** `timeoflife://verify?code=…` (also in the email) opens the app and pre-fills + submits the code.
4. **Refresh** with rotation: each refresh issues a new pair and revokes the old token; reuse of a revoked token revokes *all* the user's sessions (`token_reuse`).

### Security (R1)
- **No passwords anywhere.** Accounts authenticate by proving email ownership via an OTP code (stored only as a **SHA-256 hash**, 10-min expiry, max 5 attempts).
- **JWT access token** (HS256, 15 min) + **opaque refresh token** stored as a **SHA-256 hash** in the DB, rotated on every use with reuse detection.
- iOS stores tokens in the **Keychain** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) — never `UserDefaults`, never logged.
- Deep link (not a website) for the magic link (+1). ATS scoped to `127.0.0.1` only — never arbitrary loads; production must be HTTPS.
- No user enumeration: `/auth/otp/request` always returns 202.
- In-memory per-IP+email rate limiting on `otp/request` + `otp/verify` (swap for Redis before multi-instance).
- `log/slog` logging never touches codes, tokens, or request bodies.

## Backend (`/backend`) — Go

Stack: Go 1.22+, `go-chi/chi/v5`, `jackc/pgx/v5` (Postgres), `modernc.org/sqlite` (pure-Go, no CGO — for tests), `golang-jwt/jwt/v5`, `joho/godotenv`, `crypto/sha256`. Email via a `Sender` interface — `ConsoleSender` (prints code + magic link to stdout, dev/test) and `MailgunSender` (prod, env-configured). No bcrypt (no passwords).

### Run (with Docker)
```bash
cd backend
cp .env.example .env        # set DATABASE_URL, JWT_SECRET (≥32 bytes), EMAIL_BACKEND=console, OTP_*
docker-compose up -d postgres
go run ./cmd/server         # auto-migrates, serves http://127.0.0.1:8080
```
In dev, watch stdout for the printed OTP code + magic link (e.g. `timeoflife://verify?code=123456`).

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
- Debug `API_BASE_URL=http://127.0.0.1:8080` is set in `Config.xcconfig` — start the backend first.
- On Simulator the host's `127.0.0.1` is reachable directly; a physical device needs your LAN IP instead.
- Test the magic link: `xcrun simctl openurl booted timeoflife://verify?code=123456`

### Tests & lint
```bash
cd ios/TimeOfLife
swiftlint lint --strict     # linters (S6); `--fix` autocorrects. Config: .swiftlint.yml
xcodebuild -scheme TimeOfLife \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' test   # 59 tests, SwiftTesting
```
Unit tests cover the email/OTP validators, deep-link parsing, the API client (incl. 401→refresh→retry and offline mapping via a URLProtocol stub), repositories, the AuthService (keychain/cache/restore-on-offline), and both view-models. Out of scope: SwiftUI snapshot tests and on-device keychain (see smoke checklist below).

## Code quality & CI (S5/S6/S7)
- **Linters (S6):** Go `golangci-lint` (`backend/.golangci.yml`), Swift `swiftlint` (`ios/TimeOfLife/.swiftlint.yml`), plus `.editorconfig`. Both must pass with zero findings before merge.
- **CI on every PR (S6):** `.github/workflows/backend.yml` (gofmt, go vet, golangci-lint, test + coverage) and `.github/workflows/ios.yml` (xcodegen, swiftlint, build, test) run on every PR and on pushes to `main`. Both are mandatory PR checks.
- **Standards + revising process (S5):** code is kept minimal and standardized; every iteration runs linters + tests, re-checks the relevant `Requirements/FURPS/*.md` rows, and updates docs if the architecture changes (see `AGENTS.md`).
- **AI agent context (S7):** [`AGENTS.md`](AGENTS.md) holds repo layout, build/test/run, the API contract, coding standards, the per-iteration revising process, and the decisions log.

## API contract (`/api/v1`)

Errors use a uniform envelope: `{ "error": { "code", "message", "details": {} } }`.

| Method | Path | Body | Success | Error codes |
|---|---|---|---|---|
| POST | `/auth/otp/request` | `{email}` | 202 (always) | `invalid_body`, `rate_limited` |
| POST | `/auth/otp/verify` | `{email,code}` | 200 `{access_token,refresh_token,user{id,email,email_verified}}` | `invalid_otp`, `otp_expired`, `otp_attempts_exceeded`, `rate_limited`, `invalid_body` |
| POST | `/auth/refresh` | `{refresh_token}` | 200 new pair | `invalid_refresh`, `token_reuse`, `token_expired` |
| POST | `/auth/logout` | (Bearer) | 204 | (401) |
| GET  | `/auth/me` | (Bearer) | 200 `user{id,email,email_verified}` | (401) |

## Manual smoke checklist

Backend (Docker Postgres running):
1. `POST /api/v1/auth/otp/request` `{email}` → 202; console sender prints the code + magic link.
2. `POST /api/v1/auth/otp/verify` `{email, code}` (wrong code) → 401 `invalid_otp`.
3. `POST /api/v1/auth/otp/verify` with the correct code → 200 + tokens.
4. Repeat the wrong code 5+ times → `otp_attempts_exceeded`.
5. `POST /api/v1/auth/refresh` → rotated pair; reusing the old refresh → 401 `token_reuse` and all sessions revoked.
6. `GET /api/v1/auth/me` with the Bearer access token → 200 user.

iOS (Simulator, backend running):
1. Enter email → request OTP → enter/autofill the 6-digit code → signed-in placeholder.
2. Magic link `xcrun simctl openurl booted timeoflife://verify?code=123456` pre-fills + submits the code.
3. Switch device language to Russian and toggle dark mode — UI localized + themed.
4. Turn off network (Simulator features) → offline banner, disabled submit, cached session persists across relaunch.

## Requirements coverage (MVP)

`Requirements/FURPS/Common.md` requirements (app-wide):

| Req | Status |
|---|---|
| U1 Minimalistic design | ✅ `Form`-based SwiftUI views, system tokens only |
| U2 Dark/light theme | ✅ `Theme` semantic colors from asset-catalog light/dark sets; follows system |
| U3 Offline-correct | ✅ `NetworkMonitor` + offline banner, disabled submit, cached session restore, logout works offline |
| U4 EN + RU localization | ✅ `en.lproj`/`ru.lproj` + `L10n`; tests assert all keys resolve in both |
| U5 Apple HIG compliance | ✅ `Form`/`Section` structure, `.borderedProminent` primary actions, `.controlSize(.large)`, `.submitLabel`, field-focus chaining, interactive keyboard dismiss, semantic colors, Dynamic Type |
| R1 Secure auth storage | ✅ No passwords; OTP + refresh stored as SHA-256 hashes; tokens in Keychain on device |
| S1 Mainstream tech | ✅ Go (chi + PostgreSQL) backend; Kafka deferred |
| S2 Native UI SDK | ✅ SwiftUI |
| S3 Test coverage | ✅ Go tests ≥90% on handlers/services + 59 iOS unit tests; logic-layer ~100%; coverage gating documented |
| S4 Run locally + cloud | ✅ docker-compose local, Dockerfile (Go multi-stage) for cloud deploy |
| S5 Minimal + standardized code, revising each iteration | ✅ `.editorconfig`; standards + per-iteration checklist in `AGENTS.md` |
| S6 Linters + analyzers guarantee quality | ✅ `golangci-lint` + `swiftlint` + `.editorconfig`; both pass with zero findings |
| S6 Tests + linters run on every GitHub PR (mandatory) | ✅ `.github/workflows/backend.yml` + `ios.yml` — mandatory PR checks |
| S7 `AGENTS.md` for AI agents | ✅ `AGENTS.md` with repo layout, build/test/run, contract, standards, revising process |
| +1 No website | ✅ Magic-link deep link; pure mobile client + API |
| +2 iOS 15+ all devices | ✅ Deployment target 15.0; nav polyfill for iOS 15; adaptive layouts |
| +3 Backend in Golang | ✅ Go backend (replaced the earlier Swift/Vapor prototype) |
| +4 Mobile app in Swift | ✅ SwiftUI / Swift |

`Requirements/FURPS/Sign-up_and_Sign-in.md` requirements (auth-specific):

| Req | Status |
|---|---|
| F1 Passwordless email-OTP sign up/in | ✅ |
| F2 Sign in with Apple | ⏳ Deferred — stubbed (`AppleSignInButton`/`AppleSignInService`, marked `// DEFERRED: F2`) |
| F3 Restore access by email | ✅ Subsumed — the email-OTP sign-in flow restores access (no password to reset) |
| U1 Email + OTP validation | ✅ Email format + ≤254 (mirrored backend + iOS `AuthValidator`); OTP exactly 6 digits |
| U2 Errors below editors | ✅ Each field renders its single error directly beneath the editor (`FieldErrorLabel`) |
| U3 Autofill | ✅ Email field `.emailAddress` (Hide my Email); OTP field `.oneTimeCode` + `.numberPad` |
| U4 Unified error messages | ✅ Multiple failed email rules collapse into one sentence via `AuthValidator.unified*Message` + localized `and`-join |
| U5 OTP autofill from email | ✅ `.textContentType(.oneTimeCode)`; email body formats the code on its own line for iOS detection (template configurable via `OTP_EMAIL_TEMPLATE`; may need empirical tuning) |

## Deferred / out of scope for this MVP
- **F2 Sign in with Apple** — stubbed only.
- **Kafka** — deferred until event-driven needs arise.
- **Rate-limit backing store** — in-memory now; Redis before multi-instance deploy.
- **OTP email template** — current format targets iOS autofill detection; `OTP_EMAIL_TEMPLATE` makes it swappable for tuning.
- **Multi-device session management UI** — `device_id` is captured but no list/revoke UI.
- SwiftUI snapshot/UI tests and on-device keychain tests — covered by the manual smoke checklist.