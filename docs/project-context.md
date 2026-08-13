# Time of Life — Project Context

Durable architecture and repository context for AI agents working in this repo.
This is the **canonical context file** (S7): `AGENTS.md`, `openspec/README.md`,
and `openspec/config.yaml` all point here. If you need to know what this project
is and how it is built, read this file. It is kept accurate against the codebase
and the active OpenSpec change; update it in the same iteration as the code.

## What this is

**Time of Life** — a personal time-tracking iOS app (SwiftUI, iOS 15+, local-first).
The repository contains a **Go backend** (optional sync relay) and an **iOS app**.

Current product scope:
- **Auth MVP** — passwordless email-OTP sign-up/sign-in plus **Sign in with Apple** (config-gated), implemented end-to-end.
- **Track experience** — a three-tab shell (Track / History / Insights) with a centered numeric timer, platform-native Activity search for preparation (browse / filter / quick-create), a **Refine** action beside the selected Activity for in-place editing, a Profile destination, and a compact cross-tab running timer. Categories are optional Activity metadata, seeded locally and managed from Profile. Landing is the result of the archived OpenSpec changes `redesign-track-experience`, `keep-timer-position-on-stop`, `unify-activity-preparation-flow`, `refine-selected-activity-from-track`, and `add-category-management`.

Requirements live in `Requirements/FURPS/` (the FURPS+ table) and `Requirements/Usecases/` (use-case narratives). The design system lives in `Design/` (see `Design/README.md`): all visual, component, and interaction decisions for iOS are Markdown specs so they can be implemented deterministically.

## Architecture: local-first

The device is the **source of truth**; the backend is an **optional relay**; sync is a transport feature that activates on sign-in — not a prerequisite for using the app. The app launches into the Track shell without sign-in; auth is an optional "Enable Sync" action in Profile. The active OpenSpec change is `local-first-sync-architecture` (see "OpenSpec routing" below). The local-first delta specs are the four files in `openspec/changes/local-first-sync-architecture/specs/`; the category-management baseline is in `openspec/specs/category-management/`.

### Data plane

- **GRDB `LocalStore`** (D1): SQLite via GRDB.swift in the App Group shared container `group.com.antonkosenko.timeoflife` (entitlement in `ios/TimeOfLife/TimeOfLife/Configuration/TimeOfLife.entitlements`), data protection `.completeUntilFirstUserAuthentication` (default). State tables (activities, categories, entries, activity_categories, timer_state), the transactional outbox, the durable undo buffer, and per-resource sync cursors. Accessible cross-process (widgets, Screen Time extension, lock-screen Control intents) and after first-unlock-since-boot. `LocalStore` is the **single chokepoint for all mutations** — no raw GRDB writes outside it (lint/review rule).
- **Transactional outbox** (D2): every mutation (create/update/delete) writes the state change + an outbox row in one transaction. Outbox rows hold the *operation* (op, resource, record_id, payload, created_at), so deletes are first-class (the row persists after the record is gone). Survives relaunch; each row maps to one idempotent POST / LWW PATCH / hard DELETE on the relay.
- **Durable undo buffer** (D3): deletions enter an `undo_buffer` table (full serialized snapshots) + remove the records in one transaction; the 30 s window is **wall-clock** (`deleted_at + 30s`), not a `Timer`. No outbox row is created while a deletion is in the buffer. Expired buffers commit on the **next foreground** (never in the background); no background timer. Survives suspension, kill, and cold launch. Supersession (U7): only the most recent undoable deletion is restorable; older ones commit when their own window elapses. Category-specific Manage Categories UndoToast/system Undo is implemented; activity/history Undo UI remains deferred.
- **Running timer state** (D8): a `timer_state` singleton row in GRDB (`activity_id`, `started_at`, `status`); `TimerService` reads/writes it, widgets and Controls read it to render. The running timer survives app crashes.
- **Entry provenance** (D10): entries carry `source` (enum: `manual`, `widget`, `siri`, `control`, `screentime`, `garmin`, `calendar`, `healthkit`; default `manual`) and nullable `source_ref` (external id). `UNIQUE(user_id, source, source_ref)` for non-null `source_ref` prevents duplicate imports (server-enforced). Non-`manual` sources are meant to show a localized "via <Source>" label in entry detail/history; `manual` shows nothing. **Storage is complete; the "via <Source>" label UI is not** — see "Incomplete / deferred".

### Sync plane

**`SyncController`** (D6): `@MainActor`, long-lived, optional, session-gated — `activate()` on `.signedIn`, `deactivate()` on `.signedOut`; observes `SessionStore` and `Connectivity`. Wired in `AppContainer` and `RootView`. Triggers: foreground, connectivity restored (`.satisfied`), manual "Sync now".

- **First-sync is pull-first** (D4): full pull + server-wins merge, then drain the outbox.
- Delta pulls use `?modified_since=` (per-resource cursor advanced to max `updated_at` received).
- Conflicts resolve **LWW on `updated_at`** (D5): on pull, apply only if `server.updated_at > local.updated_at`; on push, 409 `conflict` → adopt server version (keep-latest) and clear the outbox row. 409 `activity_exists`/`category_exists` → re-map local references to the winning id. 404 on DELETE → treat as success.
- Outbox drain is idempotent (one HTTP call per row, in `created_at` order).
- Exposes `@Published status` ("Last synced" / "Syncing…" / error) + manual "Sync now" in Profile, visible only when signed in.
- Sign-out preserves local data and the outbox; an explicit "Erase local data" action wipes them.

### Incomplete / deferred (per active OpenSpec tasks and current code)

Do not claim these are done. The following remain open in the active changes:

- **App-wide Undo UI**: activity/history `UndoToast` rollout, supersession UX, and the bulk-delete cap (local-first tasks 3.3–3.6). Manage Categories has its category-scoped countdown, durable restore, and system Undo registration (archived `add-category-management`).
- **Enable Sync presentation**: the Profile "Enable Sync" row currently calls `authService.restoreSession()` (silent restore) instead of presenting `AuthFlowView` as a sheet (task 5.2); `AuthFlowView` copy still frames sign-in as required rather than as "Enable cross-device sync" (task 5.5); launch-into-timer auth tests are pending (task 5.6).
- **"via <Source>" labels** in entry detail/history (task 6.2).
- **Lock-screen Controls** (iOS 18+ WidgetKit `ControlWidget` toggle via an `alwaysAllowed` AppIntent): no ControlWidget target exists in `ios/TimeOfLife/project.yml`; storage/sync/provenance foundations are in place (tasks 7.1–7.6).
- **History/list UI for time entries** — backend `/entries` resource + sync landed; the shell's History/Insights empty states landed; the iOS History list/edit UI is not implemented yet.
- **Sign in with Apple follow-ups** — account-deletion token revocation via Apple `/auth/revoke` (App Store 5.1.1v, needs `.p8` + `APPLE_TEAM_ID`/`APPLE_KEY_ID`), nonce replay defense, Apple credential-state/revocation observation.
- **Kafka** — deferred (S1 names it but auth MVP doesn't need an MQ). **Rate-limit store** is in-memory; swap for Redis before multi-instance deploy.
- **SwiftUI snapshot / on-device keychain tests** — manual smoke checklist in `README.md`.

## OpenSpec routing

The repo is **spec-driven** (`openspec/config.yaml`, `schema: spec-driven`). Baseline specs, active deltas, and archives play different roles — know which one you are reading:

- **Baseline specs** (`openspec/specs/<capability>/spec.md`): the current merged contract, in force. Four baselines exist today: `app-icon`, `app-shell`, `timer-capture-experience`, and `category-management`. They were synced from archived changes. **Rule: never edit a baseline spec directly** — behavior changes go through a change with a delta spec.
- **Active deltas** (`openspec/changes/<change>/specs/<capability>/spec.md`): proposed ADDED/MODIFIED requirements not yet in the baseline. The active change is `local-first-sync-architecture` (four local-first delta specs). Read the relevant `tasks.md` or run `openspec status --change <change>` for live progress.
- **Archives** (`openspec/changes/archive/<change>/`): completed changes. Their delta specs were folded into the baselines by `openspec archive`; the folder is history. Today: `redesign-track-experience`, `keep-timer-position-on-stop`, `unify-activity-preparation-flow`, `refine-selected-activity-from-track`, `add-category-management`, `integrate-app-icon`.
- **Routing**: before touching a behavior, check the active change's tasks and delta specs (`openspec validate --all`, `openspec list`, `openspec status --change <change>`). When implementing, mark tasks in the relevant `tasks.md`. Archive each change only after its own tasks and verification are complete, then update this context.

## Repo layout

```
backend/                 Go backend (chi + pgx/Postgres; sqlite for tests) — optional sync relay
  api/openapi.yaml      OpenAPI 3.0 spec (S10 — authoritative API contract)
  cmd/server/main.go     entrypoint (run() int pattern; os.Exit owns lifecycle)
  internal/
    auth/                token service (JWT + rotated refresh) + otp service
    handlers/            HTTP handlers (auth + activity catalog/entries)
    server/              chi router + middleware (recoverer, logger, jwtAuth)
    db/                  Store interface + postgres + sqlite impls
    migrations/          embedded SQL migrations (go:embed)
    email/               Sender (console + AWS SES) + localized bodies
    ratelimit/           in-memory token bucket
    config/              env config (fail-fast JWT_SECRET ≥32 bytes)
  Dockerfile, docker-compose.yml, docker-compose.prod.yml, nginx/, deploy.sh, Makefile
ios/TimeOfLife/          SwiftUI app (iOS 15+), XcodeGen-managed (project.yml)
  TimeOfLife/Features/Auth/        passwordless flow: Welcome → EmailEntry → OtpEntry; AppleSignIn
  TimeOfLife/Features/AppShell/    three-tab shell (Track/History/Insights) + Profile destination
  TimeOfLife/Features/TimeTracking/  Track state machine, Activity search interaction state, numeric/compact timers, TimerService
  TimeOfLife/Features/Catalog/     Models/CatalogModels.swift, ActivityDraft.swift, ActivityName.swift, Repositories/RemoteCatalogRepository.swift, ActivityEditor (edit-from-Track refinement)
  TimeOfLife/Features/Sync/        SyncController.swift (outbox drain + delta pull)
  TimeOfLife/Core/Storage/         LocalStore.swift (GRDB), UndoBufferStore.swift, SessionCache.swift
  TimeOfLife/Core/                 networking, keychain, reachability, theme, navigation, DI, design components
  TimeOfLife/Localization/         en + ru Localizable.strings + L10n enum
  project.yml              XcodeGen spec — edit this, then `xcodegen generate`; never hand-edit the .pbxproj
.github/workflows/       CI: backend.yml + ios.yml (mandatory on every PR)
.golangci.yml            Go linters (run from backend/)
ios/TimeOfLife/.swiftlint.yml   Swift linters (run from ios/TimeOfLife/)
docs/                    Durable repo documentation (this file, docs/ci.md)
openspec/                Spec-driven change workflow (see openspec/README.md)
```

Note: `RemoteCatalogRepository` exists only as the SyncController's relay client; the catalog UI reads the local store.

## Build, test, run

### Backend (Go 1.24)
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
  -destination 'generic/platform=iOS Simulator' build
```

`project.yml` sets warnings-as-errors on the app and test targets. Do not pass those settings globally on the command line because GRDB intentionally compiles with `-suppress-warnings`.

## API contract (`/api/v1`)

[`backend/api/openapi.yaml`](../backend/api/openapi.yaml) is the sole authoritative endpoint and schema reference (OpenAPI 3.0, S10). Do not duplicate its endpoint table in project documentation.

Durable invariants: the error envelope is `{ "error": { "code", "message", "details": {} } }`; catalog and entry routes are Bearer-protected; IDs are client-generated UUID v7; creates are idempotent on ID; updates use last-write-wins on `updated_at`; suggestions and default-category seeding are client-side; delta pulls use `modified_since`; entry provenance uses `source` and nullable `source_ref`. If an endpoint changes, update the server, iOS relay client, OpenAPI document, and contract tests together.

## Auth model (passwordless)

Enter email → `otp/request` (always 202, account auto-created unverified) → server emails a 6-digit code → `otp/verify` → marks verified + issues JWT access (15 min) + rotated refresh. The OTP proves email ownership — there is no separate "verify email" step and no password anywhere (R1). OTP codes and refresh tokens are stored only as **SHA-256 hashes**; tokens live in the iOS **Keychain**. `otp/request` and `otp/verify` are rate-limited per IP+email. The client IP for rate limiting is resolved by `Handler.clientIP`, which honours `X-Forwarded-For`/`X-Real-IP` **only** when the direct TCP peer is in `TRUSTED_PROXIES` (comma-separated IPs/CIDRs; empty = trust nobody, the safe default that prevents rate-limit bypass via spoofed headers). The email body puts the 6-digit code on its own line for iOS `.oneTimeCode` autofill (U5); the template is configurable via `OTP_EMAIL_TEMPLATE` and may need empirical tuning.

The iOS `APIClient` retries protected requests once after a 401 using the single-flight refresh path. A rejected or reused refresh token clears the Keychain/cache/session so the session returns to signed-out; offline or transport failures are preserved and do not sign the user out (the app shell stays up — auth no longer gates the root view).

## Coding standards (Requirements S5)

Keep code **minimal and standardized**, following modern best practices.
- **Backend (Go):** idiomatic Go; `gofmt`-formatted (tabs); table-free errors via the domain error types in `internal/`; `context.Context` first param; no `panic` in request paths; `log/slog` only (never log codes/tokens/bodies/emails at info). No new deps without strong justification (S1: mainstream).
- **iOS (Swift):** SwiftUI, MVVM + Repository, all dependencies injected via `AppContainer`; every layer replaceable in tests; `@MainActor` on view models; views use only `Theme` semantic colors (no raw `Color` literals); user-facing strings via `L10n`/`Localizable.strings` (never hard-coded); iOS 15+ only with availability guards for iOS 16+ APIs.
- **Tests (S3):** logic layer ~100% covered. Backend `go test` (SQLite, no Docker); iOS SwiftTesting. Don't leave failing tests; don't lower coverage by deleting tests.
- **Security (R1):** never persist/log passwords, OTP codes, or tokens in plaintext. Secrets from env. Keep user-enumeration closed (`otp/request` always 202).
- **Locales (U4):** every new user-facing string must be added to **both** `en.lproj` and `ru.lproj`, and to the `L10n` enum's `allCases` in `LocalizationTests` if enumerated.

## Per-iteration revising process (Requirements S5)

On every iteration (feature/fix PR) the author MUST:
1. Run both linters and fix every finding: `golangci-lint run` (backend), `swiftlint lint --strict` (iOS); run the iOS build and inspect/fix every `xcodebuild` warning (app/test warnings are errors through `project.yml`); `gofmt -l .` must be empty.
2. Run both test suites green (`go test ./...`; `xcodebuild test -scheme TimeOfLife -destination '<available simulator>'`).
3. Re-read the relevant `Requirements/FURPS/*.md` rows and confirm the change aligns; correct the requirements doc if rows conflict (see the passwordless correction as precedent).
4. Update `AGENTS.md`, `README.md`, `docs/project-context.md`, the relevant `Design/*.md` files, and [`backend/api/openapi.yaml`](../backend/api/openapi.yaml) if architecture/contract/run steps or visual design changed. The OpenAPI spec is the authoritative API contract — keep it in sync with the handlers. Advance or archive the active OpenSpec change as appropriate.
5. Prefer reusing existing utilities/patterns over new code; remove dead code.

## CI (Requirements S6)

`.github/workflows/backend.yml` (Go: gofmt, go vet, golangci-lint, test + coverage) and `.github/workflows/ios.yml` (xcodegen, swiftlint, warning-as-error xcodebuild build, test) run on pull requests that touch their subsystem and on similarly path-filtered pushes to `main`. Both are **mandatory** PR checks when triggered — a PR is not mergeable until the applicable checks are green. See `docs/ci.md` for the full pipeline guide.

## Deployment (S4)

The backend is deployed to a **Google Cloud Compute Engine VM** (`timeoflife-backend`, us-east1-b). The production stack runs via Docker Compose:

- **PostgreSQL 15** — database
- **Backend** — Go API server (container image from GHCR)
- **Nginx** — reverse proxy with SSL termination (Let's Encrypt)

**CI/CD pipeline**: on every push to `main` that touches `backend/`, CI runs lint + test, builds the Docker image and pushes to `ghcr.io/antonkosenkopro/timeoflife/backend:latest`, then SSHs into the VM, pulls the new image, and restarts the backend container.

**Manual deploy**: dispatch the `backend` workflow in GitHub Actions and select the target environment.

**Production URL**: `https://timeoflife-api.antonkosenko.pro`.

**Required GitHub Actions secrets**: `VM_HOST` (VM external IP), `VM_USER` (SSH user `deploy`), `VM_SSH_KEY` (SSH private key for deployment).

**iOS production config**: `API_BASE_URL` is per build configuration, injected into `Info.plist` via xcconfig: `Debug` → `Config.Debug.xcconfig` → `http://127.0.0.1:8080` (local backend; ATS allows plain HTTP to `127.0.0.1` only); `Release` → `Config.Release.xcconfig` → `https://timeoflife-api.antonkosenko.pro` (production, HTTPS — no ATS exception needed). `AppConfig` reads it at runtime and falls back to the dev URL if missing/malformed. Unit tests run under `Debug`, so they keep asserting `127.0.0.1:8080`.

Code signing is disabled in `project.yml` (`DEVELOPMENT_TEAM: ""`, `CODE_SIGNING_REQUIRED: NO`) so simulator/CI builds need no Apple Developer account. **TestFlight/App Store distribution is deferred** — to enable it later: set `DEVELOPMENT_TEAM`, switch `CODE_SIGNING_REQUIRED`/`CODE_SIGN_IDENTITY` to distribution values, supply a provisioning profile, and add a fastlane/gym archive + upload CI job (needs an App Store Connect API key secret). The comment in `project.yml` marks the exact lines.

## Pre-release policy

The app is unreleased; there is no on-disk data in the wild. **No backward compatibility / migration for local on-disk formats is needed before release.** Do not add legacy-decode branches, `legacy*` fields, or `migrateIfNeeded` paths to local stores. On-disk schema changes are applied by editing the `Codable` shape in place; existing test fixtures and dev devices simply start fresh. Revisit this policy once a build ships to TestFlight or any external tester.

## Sign in with Apple (F2)

- iOS: `Features/AppleSignIn/` — `AppleSignInService` wraps an injectable `AppleAuthorizationProviding` (real `ASAuthorizationAppleIDProvider`-backed impl + a fake in tests). The `AppleSignInButton` (UIControl wrapper) lives on `WelcomeView` and triggers `WelcomeViewModel.signInWithApple()`, which obtains Apple's identity token and posts it via `AuthService.signInWithApple` → `POST /api/v1/auth/apple`. Success reuses `AuthService.persist` → `SessionStore` flips → the app shell (Track) remains the root (no new navigation wiring).
- Backend: `POST /api/v1/auth/apple` (`internal/handlers/auth.go` `AppleSignIn`) verifies Apple's RS256 identity-token JWT via `internal/apple` (JWKS fetched with `github.com/MicahParks/keyfunc/v3`, pinned `RS256`, `iss`/`aud`=Bundle ID/`exp`), upserts a user keyed by Apple's `sub` (`Store.UpsertUserByAppleSubject`, migration `002_apple.sql` adds `users.apple_subject`), and issues the same token pair as OTP verify.
- **Config-gated**: the route is always registered. When `APPLE_CLIENT_ID` is absent, the handler returns `apple_not_configured` (503); when configured, the Bundle ID is validated against the identity token's `aud`. `APPLE_JWKS_URL` defaults to `https://appleid.apple.com/auth/keys`.
- Running end-to-end requires the **Sign in with Apple** capability (entitlements file + portal App ID) and code signing enabled — both currently off. Unit tests run without them.

## Decisions log (precedents to respect)

- Backend language is **Go** (+3); mobile is **Swift** (+4). Do not reintroduce Swift/Vapor in the backend.
- Auth is **passwordless** — do not reintroduce passwords.
- Tests use **SQLite in-memory** so they run without Docker (S4 local + cloud).
- The Xcode project is **XcodeGen-managed** — edit `ios/TimeOfLife/project.yml`, then `xcodegen generate`; do not hand-edit the `.pbxproj`.
- **Sign in with Apple** (F2) verifies Apple's RS256 identity-token JWT with `github.com/MicahParks/keyfunc/v3` (JWKS) on the backend and is **config-gated** by `APPLE_CLIENT_ID` (Bundle ID); it reuses the OTP session machinery rather than a separate token type. Account-deletion revocation is deferred (App Store 5.1.1v).
