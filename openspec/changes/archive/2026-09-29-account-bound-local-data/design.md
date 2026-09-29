# Design: Account-Bound Local Data

## Context

The app today launches straight into Track with an anonymous local database (`timeoflife.sqlite`, one file in the App Group) and treats sync as an optional bolt-on: `RootView` always renders the app shell, `SessionStore.state` only toggles `SyncController.activate()/deactivate()`, and sign-out preserves everything in that single file. This shape is the root of the anon×A×B merge and cross-account resurrection bugs called out in the proposal: nothing on the device ties local rows to an identity, so a token swap silently re-points the same file at a different account.

On the backend, sessions are single-family: `issueTokens` persists `device_id ""` (auth.go:180), refresh reuse-detection revokes **all** of the user's sessions (auth.go:443–450), and logout revokes **all** sessions (auth.go:482–487). The `refresh_tokens.device_id` column exists (001_init.sql:25) but is never populated, and the 7-day refresh TTL is configured in `TokenService` (server.go:40) yet never enforced against `created_at` — a revoked-then-reused check and a TTL check are the two enforcement points that must become per-device before "every switch re-authenticates" is survivable on a two-phone setup.

The client has no stable device identity at all; `SessionStore` gates an optional feature rather than a gate for the whole app; `LocalStore` is constructed eagerly with a fixed URL (LocalStore.swift:44–64) and `AppContainer` wires it at init. This change re-parents all of that: identity first, one local file per account, per-device session families.

## Goals / Non-Goals

**Goals:**

- Mandatory sign-in gate at the root: signed-out renders the auth flow full-screen; the app shell never appears without a session.
- Per-account local database files (`lifio_<userId>.db`) in the App Group, with an active-file marker keyed on `user_id`; reopen-and-resume (outbox, cursors, timer draft) on re-login of the same account.
- Stable per-device identity (Keychain UUID) sent as `X-Device-Id` on verify/apple/refresh/logout, with per-device refresh families and per-device reuse-detection/logout revocation server-side.
- Refresh TTL actually enforced at the enforcement points that matter (auth-time).
- Revoked/exhausted sessions lock to the auth gate; local files are never wiped on auth failure.
- Sync cycles refuse to run when the bound account no longer matches the session account.
- Logout keeps dormant files intact, including a running timer and dirty outbox rows.

**Non-Goals:**

- Device quota counting + 6th-device picker (#46 follow-up; no `device_limit` error in the API).
- Device names/models/`last_seen_at` heartbeat and any device-management UI.
- Multi-session switcher — one active session per device; every account switch re-authenticates.
- Free/paid entitlement split; sharing/ACL model.
- Per-account encryption beyond file protection; migration of anonymous data (pre-release discard instead).
- Changes to sync mechanics (pull-first, LWW, tombstones, outbox ordering) within one account.

## Decisions

### D1 — Single change, not stacked changes

The auth-gate, per-user files, per-device sessions, and sync guard ship as one change because they are mutually prerequisite: a mandatory gate without per-user files still leaves the anon file re-pointable; per-device revocation without the gate has no second device to protect. Stacking would put the repo in intermediate states where the specs contradict the shipped behavior (e.g. `local-first-store` still describing a single shared file while the gate is live).

*Alternatives considered:* a stacked series (gate → files → sessions) was attractive for review size, but each intermediate stage is a broken promise to the user (forced login that still merges anon data into A) or to the spec (files renamed before the session semantics exist to guard them). The delta specs here split cleanly by capability (`account-bound-store`, `device-sessions` + modified ones), which gives the same review granularity without the broken intermediate states.

### D2 — Per-user files, not a `user_id` column in one file

Local data becomes `lifio_<userId>.db` — one file per account, one active file at a time, active marker stored as the bound `user_id`.

*Rationale:* a `user_id` column in a single shared file would put cross-account rows in one SQLite file, which resurrects exactly the collision surface we are deleting: any query or sync path that forgets the predicate mixes A and B; a tombstone from A can collide with B's row for the same key; cursors and outbox need per-account partitioning anyway, so every table gains a partitioning key and every query a filter. Separate files make isolation physical — swapping accounts swaps the whole database, and a bug in one account's file cannot read another's. File-per-account also matches the lifecycle we actually want (dormant keep, explicit per-account Erase) without row-level GC.

*Alternatives considered:* `user_id` column + composite indexes was cheaper to implement (no swap machinery, existing tests mostly work) but pushes the isolation invariant into every call site forever — the failure mode is silent data mixing, which is the bug class this change exists to kill. It also makes "erase account A" a delete-by-predicate instead of a file unlink, which is slower and leaves vacuum/wal residue.

### D3 — Keep dormant files; no evict, no auto-wipe

Dormant files are kept indefinitely in this change. Re-login as the same account reopens its file and resumes (outbox drains, cursors continue, timer draft resumes). Erase is explicit, per-account, and only for the **active** file.

*Rationale:* the tracker's core promise is that data is never lost locally. Logout is routine (troubleshooting, privacy theater) and deleting data on it would be a data-loss bug; a running timer mid-logout must survive and resume. Eviction policy (LRU disk budget) is a monetization-adjacent decision (#46 device/quota world) and premature without telemetry.

*Alternatives considered:* evict-on-logout (delete at sign-out) is simplest but destroys the resume promise and makes logout destructive; evict-LRU with a disk cap needs a policy surface (cap size, eviction UX, "data removed" copy) that belongs with the device-quota work in #46, where a budget story already exists.

### D4 — Keychain UUID for device identity, not `identifierForVendor`

The client mints a UUID v4 on first need, stores it in the Keychain (survives uninstall on iOS 10.3+-style behavior differences aside — see Risks), and sends it as `X-Device-Id` on verify/apple/refresh/logout.

*Rationale:* `identifierForVendor` is not stable: it changes when every apps from the vendor are uninstalled (a reinstall of Lifio alone resets it on a vendor-of-one), and it is not controllable in tests. A Keychain UUID is stable across reinstalls while the Keychain persists, is under our control, and lets the backend treat "same device" as the semantic we define rather than Apple's. It is also the same mechanism needed later for quota counting (#46) — the identity must exist before the quota.

*Alternatives considered:* `identifierForVendor` is zero-setup but resets on the vendor-of-one reinstall case — precisely the reinstall scenario where a user's sessions would be orphaned; device-name-derived ids are spoofable and not stable; UDID-style vendor ids are unavailable. Keychain UUID costs a small storage/read path we already have (`Core/Keychain`).

### D5 — Per-device revocation, not revoke-all

With `device_id` persisted on mint (replacing `""`), reuse-detection and logout revoke only that device's refresh family. Reuse-detection keeps its revoke-the-family semantic (the rotated descendants of the reused token) but scoped to the device; logout revokes only the calling device's tokens.

*Rationale:* revoke-all on logout is correct only for a single-device world. With mandatory login on 2+ phones, logging out of one phone must not kill the other's session — that is the daily behavior this hardening exists for. Reuse-detection stays per-device because a stolen token implies compromise of that device's family, not the user's other devices; cross-device attack correlation (same IP, same hour) is a detection problem, not a blast-radius decision for this change.

*Alternatives considered:* keeping revoke-all everywhere is the current code and is safe but makes mandatory-login multi-device unusable (each login kills the sibling); reuse-detection scoped per-device slightly weakens the "attacker with the whole user's tokens" case, accepted because refresh tokens never leave the device that minted them.

### D6 — Lock, never wipe, on 401/revocation

A revoked or exhausted session (TTL exceeded, reuse detected, logout elsewhere, refresh 401) transitions `SessionStore` to a locked state that renders the auth gate; local files, outbox, and cursors are untouched. Only explicit Erase deletes data.

*Rationale:* 401 is an auth fact, not a data fact. Wiping on revocation would convert a server-side security event (or a transient clock/TTL edge) into client data loss — the worst possible trade for a local-first tracker. The dormant file also remains recoverable: a successful re-login reopens and resumes it, so lock-not-wipe loses nothing even in the worst case.

*Alternatives considered:* wipe-on-401 (defensive deletion) protects nothing real — the tokens were already compromised server-side — and permanently destroys the user's data on a false-positive revocation; prompt-to-reauthenticate-with-erase-option adds a destructive decision to an error path users hit mid-tunnel.

### D7 — Enforcement at auth time, not sync time (auth-time chosen)

TTL enforcement, revocation checks, and the account-bound guard fire in the auth/session layer (refresh path, session restore, cycle entry checks), not lazily during a sync cycle's data writes.

*Rationale:* sync-time enforcement means invalid state is discovered mid-write — an outbox drain already pushing under a stale token, a pull writing rows for the wrong account — and requires compensating logic at every write site. Auth-time enforcement makes the invalid state structurally unreachable: `SessionStore` is the single gate `RootView` and `SyncController` consult, and `SyncController` additionally records the bound `userId` at activation and refuses/skips cycles on mismatch. The refresh handler is where TTL is cheap: one `created_at` comparison against the stored token, no extra round-trip, and the 401 the client already knows how to handle (lock, re-auth).

*Alternatives considered:* sync-time enforcement (check `exp`/`user_id` inside `runCycle` before each push/pull) spreads the invariant across the sync code and still admits races between check and write; backend-per-request enforcement alone would let a client push A's outbox under B's token for one full cycle before the 401 lands. Auth-time chosen: gate early, gate once, and the same-account guard (D2's physical isolation) backstops it.

### D8 — Discard anonymous data on first login; no import

Existing anonymous/dev-install local data is discarded when the new model first activates. No migration from the anon file into `lifio_<userId>.db`. Starter categories seed per-account-file on first open.

*Rationale:* pre-release there is no real anonymous user data worth a migration path, and importing it buys permanent complexity (an import path, its own failure modes, its own spec rows) for zero users. The anon file's schema-shape drift over the pre-release window would make any import code a bug farm. Discard is also the honest semantic: the anon data was never bound to the account being logged into.

*Alternatives considered:* import-on-first-login (copy the anon file to the account's file) was rejected — it silently attributes anonymous junk/dev data to a real account and creates a one-time code path that must be tested forever; a "was using anonymously, keep this?" prompt adds UX and a merge problem (the anon data may collide with pulled server rows) for a population that does not exist pre-release.

## Risks / Trade-offs

- **[Reinstall ghost slots]** Keychain persists across uninstall, so a reinstall presents the *old* device UUID; combined with per-device families this means the reinstall inherits the previous slot's session state server-side (and, once #46 lands, consumes the old slot rather than a fresh one). → Mitigation: on reinstall-with-same-UUID, verify/apple/refresh treat it as the same device (this is the desired resume behavior for data-keep reinstalls); #46's device picker is the explicit escape hatch for slot hygiene. Document that Erase + logout clears device-scoped Keychain entries but the UUID itself intentionally survives.
- **[Backup-restore id collision]** A Keychain UUID restored from a device backup (or two devices restored from the same backup) can collide: two physical devices presenting one `X-Device-Id`, interleaving refresh rotations into one family and tripping each other's reuse-detection. → Mitigation: reuse-detection revoking the family will lock one of them to the auth gate (lock-not-wipe, D6, so no data loss); the user re-authenticates and a fresh mint (only when no session exists) or #46's picker resolves it. Keep family revocation scoped (D5) so the blast radius is one device's sessions, not the user's.
- **[Concurrent-refresh race — non-atomic read-then-revoke]** The refresh path reads the token, checks `revoked`, then revokes+re-mints in separate statements (auth.go:435–468). Two concurrent refreshes with the same token can both pass the revoked check and mint two children (family fork), or a refresh racing reuse-detection can mint after revocation. → Mitigation: make the rotate conditional — `UPDATE ... SET revoked WHERE id = ? AND revoked = false` returning rows-affected, minting only on `rowsAffected == 1` — first-writer-wins, loser gets `invalid_refresh`; same condition used by the reuse branch. No new locking primitives needed; both SQLite and Postgres backends express this as a single conditional UPDATE.
- **[Shared-iPad dormant-file privacy]** On a shared device, dormant account files sit in the App Group readable by any process under the app's sandbox — another family member's account data remains on disk after logout. → Mitigation: accept for this change (per-account encryption is a stated non-goal); files already use default file protection (encrypted at rest while the device is locked). The explicit per-account Erase is the user's control; device-passcode protection is the boundary. Revisit if multi-user iPad becomes a real support case.
- **[AppContainer eager `LocalStore` init must go lazy]** `AppContainer` currently constructs `LocalStore` at init (fixed URL), which cannot work when the URL depends on the not-yet-known `userId`. If left eager, the app crashes or opens an orphan anon file before auth. → Mitigation: make the store lazy/swappable — a store-provider that opens `lifio_<userId>.db` on first access post-login and swaps on account change; timer/undo/sync services resolve the store through the provider (or the container rebuilds its service graph on account change). Cold-launch ordering (`UndoBufferStore` commit, first sync cycle) moves behind the signed-in gate in `RootView` so nothing touches a store before an account is bound.
- **[Test-helper single-DB churn]** Existing iOS tests construct `LocalStore(url:)` directly and assume one database; per-account files plus the lazy provider mean most storage/sync tests need a store-provider seam (or per-test URLs under unique accounts). → Mitigation: keep `LocalStore.init(url:)` as the test constructor and put the per-user naming/swap in the provider layer, so tests pin a URL as today; add focused tests for the provider (naming, active-marker, swap, resume) rather than rewriting every existing test. Backend tests need per-device family cases added to the contract-test suite; the shared sqlite test DB stays as-is except for device_id coverage.

## Migration Plan

- **Pre-release discard, no data migration.** The app is pre-release; per D8 the anon file is discarded at first login under the new model. There is no user data to preserve and no rollback of data to support.
- **No rollback beyond revert.** The change is self-contained (no schema change to ship, no server data reshaped — `device_id` is populated but was always a column). Rolling back = reverting the commit; an app that reverted would read its old single-file model, and any `lifio_*.db` files created meanwhile are simply ignored (no format fork of the shared schema, so no cleanup contract).
- **Backend first, additive:** persist `device_id` on mint, per-device revoke paths, TTL enforcement at refresh, `X-Device-Id` accepted and echoed in error semantics — all behind endpoints the current client already calls, so backend can land and verify before the iOS gate flips.
- **iOS sequencing:** session/device-id plumbing → per-user store provider (lazy) + seeding per file → RootView gate + copy changes (en/ru + `L10n`) → SyncController bound-user guard → remove Enable Sync surfaces and signed-out branches → tests.
- **Seed per file:** starter categories seed on first open of each account file (existing marker logic, now per-account), not once per device.
- **#46 follow-up:** device quota counting, 6th-device picker, and any device-management UI build on the `device_id` this change makes real; the API intentionally ships **without** `device_limit` so #46 owns that contract change.

## Open Questions

- **Free/paid split:** where the entitlement boundary sits (which features are gated, how the gate reads) is deferred until the account-bound world exists to measure against. The auth gate itself is free-tier-agnostic.
- **Sharing model:** whether dormant files are ever shared/merged across devices of one account via sync (today: sync per account, one active file per device) and any ACL shape for shared trackers — deferred; `account-bound-store` spec deliberately does not presume an answer.
- **Device heartbeat fields:** whether we ever want `device_name`/`model`/`last_seen_at` on `refresh_tokens` for support/quota UX (the column set is trivially extensible, but every field is privacy surface + retention question). Deferred to #46's design; this change stores only the opaque id.