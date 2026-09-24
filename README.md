# Lifio

A personal time-tracking app for iOS — minimal-effort tracking of where your time goes (widgets, shortcuts, integrations). **Local-first:** your device is the source of truth; the Go backend is an optional sync relay you can enable later.

Current scope: **auth MVP** (passwordless email-OTP + Sign in with Apple) and the **Track experience** — a three-tab shell (Track/History/Insights) with a centered numeric timer, a plain-text name field with exact-text Recents chips, a live tag selector while running, a Profile destination, and a compact cross-tab running timer. There is no activity entity: entries own their text, ordered categories, and notes.

| Doc | What it's for |
|---|---|
| [`docs/project-context.md`](docs/project-context.md) | Canonical architecture + repo context (for AI agents, S7) |
| [`AGENTS.md`](AGENTS.md) | Concise AI-agent entrypoint |
| [`Requirements/FURPS/`](Requirements/FURPS/) | Requirements (FURPS+ table + use cases) |
| [`Design/`](Design/) | Text-based design system (colors, components, screens) |
| [`backend/api/openapi.yaml`](backend/api/openapi.yaml) | Authoritative API contract (OpenAPI 3.0, S10) |

## The app in one minute

1. **Launch into Track** — no sign-in required; auth is an optional "Enable Sync" action in Profile.
2. **Name it** — type a name or tap a recent chip (exact match inherits that entry's categories; typing never starts timing).
3. **Start** — the centered numeric timer counts up while the device stays awake.
4. **Stop** — saves the entry to the local GRDB database and enqueues an outbox row; if signed in, the `SyncController` drains the outbox and pulls deltas on foreground/connectivity/manual "Sync now".
5. **Switch tabs freely** — a running timer stays visible above the tab bar on History and Insights with return-to-Track and in-place Stop.

Entries, categories, the running timer state, the outbox, and the undo buffer live in the App Group shared container (`group.com.antonkosenko.timeoflifeapp`), ready for future cross-process system integrations.

### Local-first architecture

The device is the source of truth; the backend is an **optional relay**; sync is a transport feature that activates on sign-in. Everything works offline with no account. Writes go through a transactional **outbox** (deletes are first-class), deletions sit in a durable **undo buffer** restorable until the app restarts (committed on cold launch), and `SyncController` syncs via `?modified_since=` delta pulls with last-write-wins on `updated_at`. Specs: `openspec/specs/` baselines (synced from the archived `remove-activities-layer` change). Categories are seeded once per local dataset and managed from Profile; entry and category deletions share the editor-Delete + shake-to-undo system confirmation grammar. The "Enable Sync" sign-in sheet, "via <Source>" labels, and the iOS 18 lock-screen Control remain **incomplete** — see `docs/project-context.md` → "Incomplete / deferred".

## Security (R1)

- **No passwords.** Accounts authenticate by proving email ownership via a 6-digit OTP (stored only as a SHA-256 hash; `otp/request` always returns 202 — no user enumeration).
- **JWT access token** (HS256, 15 min) + **opaque refresh token** stored as a SHA-256 hash, rotated on every use with reuse detection.
- Tokens live in the iOS **Keychain**; `log/slog` never touches codes, tokens, or request bodies.

## Development

### Backend (`/backend`) — Go 1.24

Stack: `chi` router, `pgx`/PostgreSQL (SQLite for tests), JWT, AWS SES email. No Docker needed for tests.

```bash
cd backend
go build ./...
go test ./... -cover        # SQLite in-memory — self-contained
golangci-lint run && gofmt -l . && go vet ./...
# Real run (needs Postgres):
cp .env.example .env        # DATABASE_URL, JWT_SECRET (≥32 bytes), EMAIL_BACKEND=console, OTP_*
docker-compose up -d postgres
go run ./cmd/server         # serves http://127.0.0.1:8080 (watch stdout for OTP codes)
```

### iOS (`/ios/TimeOfLife`) — SwiftUI, iOS 15+

XcodeGen-managed: edit `project.yml`, run `xcodegen generate` — never hand-edit the `.pbxproj`.

```bash
cd ios/TimeOfLife
xcodegen generate
open TimeOfLife.xcodeproj
```

- `API_BASE_URL` is injected per build configuration: Debug → `http://127.0.0.1:8080` (local backend; ATS allows plain HTTP only to `127.0.0.1`), Release → `https://timeoflife-api.antonkosenko.pro`. On a physical device, use your LAN IP instead.
- Code signing is split per configuration: **Debug stays unsigned** (simulator/CI need no Apple Developer account); **Release signs** with team `7923U48U87` (development identity; archives sign distribution automatically) and carries the Sign in with Apple entitlement (App ID `com.antonkosenko.timeoflifeapp` must have the SIWA capability enabled in the Apple Developer portal). The backend needs `APPLE_CLIENT_ID=com.antonkosenko.timeoflifeapp` set or `/auth/apple` returns 503.
- Tests & lint:

```bash
swiftlint lint --strict     # --fix autocorrects
xcodebuild -scheme TimeOfLife -destination 'generic/platform=iOS Simulator' build
xcodebuild test -scheme TimeOfLife \
  -destination 'platform=iOS Simulator,name=<available simulator>'
```

Warnings are treated as errors on the app and test targets through `project.yml`. Do not pass the flags globally on the command line; that also applies them to GRDB, which uses `-suppress-warnings`.

Unit tests cover the auth flow (validators, API client incl. 401→refresh→retry, repositories, auth service + view models) and the local-first layer (GRDB `LocalStore`, `UndoBufferStore`, `SyncController`, provenance). Out of scope: SwiftUI snapshot and on-device keychain tests.

### Sign in with Apple — manual smoke checklist

Unit tests fake the Apple authorization (`AppleAuthorizationProviding`), and Apple's identity-token JWKS is only fetched for real with `APPLE_CLIENT_ID` configured — so the following must be verified manually on a **real device** (the entitlement has no effect in the simulator):

Prerequisites: Release build installed on the device (`Product → Destination → your device`, Release scheme archive or Run with Release config), backend reachable with `APPLE_CLIENT_ID=com.antonkosenko.timeoflifeapp` (local or production), a sandbox/production Apple ID.

1. [ ] **Sheet presents** — Profile → "Enable Sync" → tap *Sign in with Apple*; Apple's native authorization sheet appears (not an error).
2. [ ] **Sign-in succeeds** — complete the sheet (try a *Hide My Email* address); the app lands signed-in in the shell; Profile shows the session and "Sync now".
3. [ ] **Backend verified the token** — backend log shows the Apple sign-in line for the user (JWKS fetched, `aud` matched); the relay address `*@privaterelay.appleid.com` is stored as the email with `email_verified=true`.
4. [ ] **Sync works** — start/stop a timer, run "Sync now"; the entry appears on the relay (check via a second sign-in on another device/simulator, or the backend DB).
5. [ ] **Cancel is silent** — start the Apple flow, dismiss the sheet; no error banner appears.
6. [ ] **Offline gates the button** — airplane mode on; the Apple button is disabled (dimmed); the email path still navigates.
7. [ ] **Idempotent re-sign-in** — sign out, sign in with Apple again; same user (sync history reattaches, no duplicate account).

## CI (S6)

`.github/workflows/backend.yml` (gofmt, go vet, golangci-lint, test + coverage) and `ios.yml` (xcodegen, swiftlint, warning-as-error build, test) are **mandatory PR checks**. See [`docs/ci.md`](docs/ci.md) for the full pipeline guide.

## Deployment (S4)

The backend deploys to a **GCP Compute Engine VM** (`timeoflife-backend`, us-east1-b) via Docker Compose: PostgreSQL 15, the Go backend, and Nginx (Let's Encrypt SSL). Every push to `main` touching `backend/` lints, tests, builds, and deploys automatically. Manual deploys use the `backend` GitHub Actions workflow dispatch. Production URL: `https://timeoflife-api.antonkosenko.pro`.

## Deferred / out of scope

- **Sign in with Apple follow-ups** — account-deletion token revocation via Apple `/auth/revoke`, nonce replay defense, credential-state observation, identity merging between email-OTP and Apple accounts (kept separate by design for now).
- **iOS History list/edit UI** — the History day-grouped list and entry editing (tap a row → unified entry form) have shipped (deferred filtering lives in `docs/history-roadmap.md`); the Insights breakdown v1 (period switch + category/text lenses, mirror-only) is implemented.
- **App-wide Undo UI, "Enable Sync" sheet, "via <Source>" labels, lock-screen Control** — local-first storage/sync foundations are done; these UI surfaces are open tasks in `openspec/changes/local-first-sync-architecture/tasks.md`. Category-scoped undo in Manage Categories is implemented separately.
- **Kafka** — deferred (S1 names it; not needed yet). **Rate-limit store** — in-memory; Redis before multi-instance.
- **SwiftUI snapshot / on-device keychain tests** — not automated; verified manually in the simulator.
