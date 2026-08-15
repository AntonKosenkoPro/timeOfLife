# Time of Life

A personal time-tracking app for iOS — minimal-effort tracking of where your time goes (widgets, shortcuts, integrations). **Local-first:** your device is the source of truth; the Go backend is an optional sync relay you can enable later.

Current scope: **auth MVP** (passwordless email-OTP + Sign in with Apple) and the **Track experience** — a three-tab shell (Track/History/Insights) with a centered numeric timer, platform-native Activity search with quick-create, a Refine action for editing the selected Activity, a Profile destination, and a compact cross-tab running timer.

| Doc | What it's for |
|---|---|
| [`docs/project-context.md`](docs/project-context.md) | Canonical architecture + repo context (for AI agents, S7) |
| [`AGENTS.md`](AGENTS.md) | Concise AI-agent entrypoint |
| [`Requirements/FURPS/`](Requirements/FURPS/) | Requirements (FURPS+ table + use cases) |
| [`Design/`](Design/) | Text-based design system (colors, components, screens) |
| [`backend/api/openapi.yaml`](backend/api/openapi.yaml) | Authoritative API contract (OpenAPI 3.0, S10) |

## The app in one minute

1. **Launch into Track** — no sign-in required; auth is an optional "Enable Sync" action in Profile.
2. **Choose an activity** — pick a recent one, or use native search to browse, filter, or quick-create (selection never starts timing). Tap **Refine** beside the Activity to edit its name, notes, or Categories in place.
3. **Start** — the centered numeric timer counts up while the device stays awake.
4. **Stop** — saves the entry to the local GRDB database and enqueues an outbox row; if signed in, the `SyncController` drains the outbox and pulls deltas on foreground/connectivity/manual "Sync now".
5. **Switch tabs freely** — a running timer stays visible above the tab bar on History and Insights with return-to-Track and in-place Stop.

Entries, activities, categories, the running timer state, the outbox, and the undo buffer live in the App Group shared container (`group.com.antonkosenko.timeoflife`), ready for future cross-process system integrations.

### Local-first architecture

The device is the source of truth; the backend is an **optional relay**; sync is a transport feature that activates on sign-in. Everything works offline with no account. Writes go through a transactional **outbox** (deletes are first-class), deletions sit in a durable **undo buffer** with a wall-clock 30 s window (committed on next foreground), and `SyncController` syncs via `?modified_since=` delta pulls with last-write-wins on `updated_at`. Specs: `openspec/changes/local-first-sync-architecture/` and `openspec/changes/add-category-management/`. Categories are seeded once per local dataset and managed from Profile; category deletion has a scoped countdown UndoToast and system Undo. App-wide activity/history undo UI, the "Enable Sync" sign-in sheet, "via <Source>" labels, and the iOS 18 lock-screen Control remain **incomplete** — see `docs/project-context.md` → "Incomplete / deferred".

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
- Code signing is disabled in `project.yml` so simulator/CI builds need no Apple Developer account. TestFlight/App Store distribution is deferred (see the comment in `project.yml`).
- Tests & lint:

```bash
swiftlint lint --strict     # --fix autocorrects
xcodebuild -scheme TimeOfLife -destination 'generic/platform=iOS Simulator' build
xcodebuild test -scheme TimeOfLife \
  -destination 'platform=iOS Simulator,name=<available simulator>'
```

Warnings are treated as errors on the app and test targets through `project.yml`. Do not pass the flags globally on the command line; that also applies them to GRDB, which uses `-suppress-warnings`.

Unit tests cover the auth flow (validators, API client incl. 401→refresh→retry, repositories, auth service + view models) and the local-first layer (GRDB `LocalStore`, `UndoBufferStore`, `SyncController`, provenance). Out of scope: SwiftUI snapshot and on-device keychain tests.

## CI (S6)

`.github/workflows/backend.yml` (gofmt, go vet, golangci-lint, test + coverage) and `ios.yml` (xcodegen, swiftlint, warning-as-error build, test) are **mandatory PR checks**. See [`docs/ci.md`](docs/ci.md) for the full pipeline guide.

## Deployment (S4)

The backend deploys to a **GCP Compute Engine VM** (`timeoflife-backend`, us-east1-b) via Docker Compose: PostgreSQL 15, the Go backend, and Nginx (Let's Encrypt SSL). Every push to `main` touching `backend/` lints, tests, builds, and deploys automatically. Manual deploys use the `backend` GitHub Actions workflow dispatch. Production URL: `https://timeoflife-api.antonkosenko.pro`.

## Deferred / out of scope

- **Sign in with Apple follow-ups** — account-deletion token revocation via Apple `/auth/revoke`, nonce replay defense, credential-state observation.
- **iOS History list/edit UI** — the shell's History/Insights empty states landed; the full list UI is not implemented yet.
- **App-wide Undo UI, "Enable Sync" sheet, "via <Source>" labels, lock-screen Control** — local-first storage/sync foundations are done; these UI surfaces are open tasks in `openspec/changes/local-first-sync-architecture/tasks.md`. Category-scoped undo in Manage Categories is implemented separately.
- **Kafka** — deferred (S1 names it; not needed yet). **Rate-limit store** — in-memory; Redis before multi-instance.
- **SwiftUI snapshot / on-device keychain tests** — not automated; verified manually in the simulator.
