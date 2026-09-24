## Why

After the account-switch preservation fix, relogging via SiWA (a separate relay identity) wedges sync forever: the drain pushes preserved locals under their original ids, the relay answers `POST /categories → 409 category_exists` with an **empty winner id**, the client then requests `GET /api/v1/categories/` (empty id) which has no route, and the bare 404 fails every cycle with `server(http_404)`. Reproduced locally: a `POST` whose id exists under a *different* user returns `details: {"id": "", "name": ""}` because record ids are a **global** primary key while all pre-checks and the winner re-query are user-scoped.

## What Changes

- Account-switch adoption mints **fresh record ids** for adopted categories/entries (names, texts, icons, notes preserved; entry→category references rewritten), so pushes into a new account can never collide with another user's ids. Stale old-account update rows for adopted records are superseded (dropped); old-account delete rows still drain (404-as-success).
- A drain that hits an unresolvable id collision (409 with missing/empty winner id) **self-heals**: it rewrites the stuck row in place to a fresh id (remapping joins + payloads), retries once, and only then fails loudly with a clear diagnostic.
- The client SHALL NEVER request a winner/route with an empty id; such a response keeps the row queued and fails the cycle with a clear diagnostic instead of a mystery 404.
- The backend SHALL NEVER emit empty-string winner details: when the post-violation winner re-query misses, the 409 carries nil details (documented in `openapi.yaml` as unresolvable-collision). No new error code, no PK schema change, no idempotency change.

## Capabilities

### New Capabilities

(none — all behavior attaches to existing capabilities)

### Modified Capabilities

- `sync-client`: first-pull-after-account-change adoption semantics (fresh ids, no pre-push wipe, tombstones still apply); unresolvable-collision drain handling (self-heal rewrite-in-place, bounded retry, clear diagnostics); never-fetch-empty-winner guard.
- `local-first-store`: per-account sync scope with fresh-id adoption of clean locals in the single mutation chokepoint (cursor reset, supersede stale updates, preserve deletes), outbox invariants preserved.

## Impact

- iOS: `LocalStore` (adoption + entry remap helper), `SyncController` (activate path, drain self-heal, winner guard), `SyncControllerTests` + `LocalStoreTests` (red-first regression tests).
- Backend: `CreateCategory`/`CreateEntry` winner-details valve (nil instead of empty record), `openapi.yaml` 409 documentation (S10), parity tests (sqlite + postgres) using the live repro recipe.
- Non-goals: OTP↔SiWA identity merging; relay PK schema change; idempotency semantic change; touching the populated-winner remap path (proven working).
