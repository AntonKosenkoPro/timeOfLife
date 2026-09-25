## Why

Anonymous local-first state is the growth engine for sync bugs (anon×A×B merges, cross-account resurrection, first-sync collisions) and blocks monetization (no stable identity for devices, sharing, or paywalls). Making the local database account-bound — mandatory login once, offline-capable after — removes the anonymous axis while keeping the tracker's core promise: the timer works in a tunnel.

## What Changes

- **BREAKING**: App requires sign-in (OTP or Apple) before any Track/History/Insights use. `RootView` gates on `SessionStore`: signed-out renders the auth flow full-screen (not a sheet); signed-in renders the app shell. No anonymous timer, categories, or history.
- **BREAKING**: Local data becomes per-account files (`lifio_<userId>.db` in the App Group). One file per account, one active file at a time. Active marker is `user_id` from day one. Dormant files are kept (no wipe, no eviction in this change); re-login as the same account reopens and resumes (outbox drains, cursors continue, timer draft resumes).
- **BREAKING**: Existing anonymous/dev-install data is discarded on first login under the new model (pre-release: no migration). Starter categories seed per-account-file on first open.
- Auth-gate rewording: Welcome/OTP/Apple copy changes from optional-sync voice ("Enable Sync", "Optional account for your other devices") to required ("Log in to start tracking"). `EnableSyncPresenter`/`EnableSyncSheet`, Profile "Enable Sync" row, and History signed-out/offline banner branches are removed; `OfflineBanner` stays (offline signed-in keeps working).
- Session hardening (prerequisite for mandatory login with 2 phones, quota counting itself deferred to #46): stable client device id (UUID in Keychain, `X-Device-Id` on verify/apple/refresh/logout), per-device refresh families (`device_id` persisted instead of `""`), reuse-detection and logout scoped per-device (not revoke-all), refresh TTL enforced (currently computed but unenforced), revoked/exhausted sessions lock to the auth gate with local files intact (never wipe).
- Sync becomes same-account-only: `SyncController` records the bound `userId` and refuses/skips cycles on account mismatch (never pushes A's outbox under B's token). Pull-first, LWW, tombstones, and outbox ordering are unchanged within one account.
- Logout keeps files (Keychain/cache/session cleared, DBs untouched, dirty outbox stays in the dormant file). Explicit per-account Erase deletes only the active file (+ its Keychain/cache entries). Running timer at logout stays in the dormant file and resumes on that account's return.
- Lock-screen Controls/widgets keep working without their own auth: they read the active account file post-first-unlock (device-unlock is the authorization).

Non-goals: device quota counting + 6th-device picker (tracked in #46, pre-release blocker); device names/models/`last_seen_at` heartbeat UI; multi-session switcher (single active session; every switch re-authenticates); free/paid entitlement split; sharing/ACL model; per-account encryption beyond file protection.

## Capabilities

### New Capabilities
- `account-bound-store`: per-user DB file lifecycle (naming, active marker, open/swap/keep/resume, per-account seeding, per-account erase, dormant timer + dirty-outbox retention).
- `device-sessions`: stable device identity and per-device refresh families (mint/persist/send `X-Device-Id`, per-device issue/refresh/logout/reuse semantics, TTL enforcement, lock-not-wipe on revocation).

### Modified Capabilities
- `app-shell`: launch requires authentication; Enable Sync sheet/row and signed-out branches removed.
- `local-first-store`: source of truth becomes the active account's database; anonymous-use and sign-out-preserves-everything-in-one-file scenarios replaced.
- `sync-client`: sync is session-gated (not optional) and same-account-guarded; unsigned-user scenarios removed.
- `lock-screen-controls`: controls operate on the active account file with no auth of their own.

## Impact

- Backend: `internal/handlers/auth.go` (issue/verify/apple/refresh/logout), `internal/db/{store,sqlite,postgres}.go` (per-device revoke, optional index), `internal/server/server.go` (TTLs), `api/openapi.yaml` (`X-Device-Id`, per-device error semantics; NO `device_limit` — deferred to #46), contract tests.
- iOS: `RootView`, `AppContainer` (lazy/swap `LocalStore`), `LocalStore` (per-user URL), `SessionCache`/`SessionStore`/`AuthService` (gate + lock semantics), `SyncController` (bound-user guard), Profile/History/Track gating + copy (en+ru + `L10n`), `UndoBufferStore` cold-launch ordering post-login.
- Tests: anon-launch, signed-out banner/sheet, single-DB-helper, and refresh-logout tests updated; new per-account and per-device tests added. Both suites + linters green per S5.
