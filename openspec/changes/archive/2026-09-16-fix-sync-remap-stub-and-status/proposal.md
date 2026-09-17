## Why

Physical-device testing of first sync surfaced three defects, one corrupting user data: (1) after a `*_exists` name-collision 409, a failed winner-fetch synthesizes a stub record named with the losing record's UUID — and last-write-wins then immortalizes it, so categories (and potentially activities) are permanently renamed to GUIDs with no self-heal; (2) while syncing, Profile shows two identical "Syncing…" rows (status row + retitled Sync Now button); (3) sync failures are undiagnosable — `SyncStatus.error(message)` is captured but Profile drops it for a generic string, and the cycle logs nothing. The stub corruption spreads on every failed fetch and never heals: this must not wait.

## What Changes

- **No more synthesized names**: conflict recovery never invents record content. When the winning-record fetch fails during `activity_exists`/`category_exists` remapping, the recovery rethrows — the outbox row stays queued and the next cycle retries — instead of merging a stub named with a UUID. Local records keep their real names until the real winner arrives.
- **Single syncing indicator**: while `status == .syncing`, the Sync Now button keeps its "Sync now" title (disabled) and the status row remains the only "Syncing…" surface.
- **Failures name themselves**: Profile's error row surfaces the captured error message (localized, secret-free by construction — codes and server messages only) beneath the generic title, and the sync cycle logs start/finish/failure-with-code via `Logger` (no tokens, bodies, or emails) so the next failure is diagnosable from Console.
- Poisoned locals (UUID-named stubs already merged) are repaired by renaming the category/activity to its real name in place — the rename bumps `updated_at`, LWW accepts the push, both sides heal. Verified as a task, not assumed.

Non-goals: no sync-protocol changes (pull-first, LWW, outbox, idempotency untouched); no retry/backoff policy (existing trigger model stays); no in-app log viewer; no server changes (the relay's winner `{id, name}` details are correct); no migration (no schema touch).

## Capabilities

### New Capabilities
(none — all three tighten existing behavior)

### Modified Capabilities
- `sync-client`: conflict recovery gains the never-synthesize rule (fetch-or-retry); the syncing indicator is single; failure status carries its message to the surface and to the log.

## Impact

- iOS only: `SyncController.remapReferences` (+ `resolveConflict` error path), `ProfileView` sync rows (button title + error subtitle), `Logger` cycle logging. SwiftTesting coverage for fetch-fails-keeps-row, no-stub-merged, and message surfacing, following existing `SyncControllerTests` patterns (fakes + temp store).
- No backend, OpenAPI, store-schema, or auth changes. Users with UUID-named rows heal via in-app rename (documented in tasks); no destructive repair.
