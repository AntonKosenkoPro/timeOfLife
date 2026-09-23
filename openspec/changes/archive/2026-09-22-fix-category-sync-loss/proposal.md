## Why

Syncing a manually created entry strips its categories: the entry push 422s on a relay-unknown category id, the heal path prunes and retries, and the trailing pull converges the local row to the pruned version — while re-assigned categories fork silently forever (relay PATCH prunes with 200 + LWW tie skips the pull). Users lose saved categories with no error and no recovery.

## What Changes

- Drain ensures referenced categories exist on the relay BEFORE pushing each entry create/update (create missing ones from local rows, idempotent; 409 remaps to the winner and the entry push uses it). The 422-prune-and-retry heal stays as a last resort only.
- Pull adopts relay-known-but-locally-unknown category ids instead of stripping them: merge the snapshot row, or remap the join to a same-name local rival (local-only rewrite, never enqueued — avoids cross-device id ping-pong).
- Pull heals existing forks: when the server version is not newer but the local category set is a strict superset via existing clean local rows, enqueue an entry update with a bumped `updatedAt` (second-truncation safe) so the full set reconverges instead of diverging forever.
- Backend doc-only corrections: stale `store.go` comment (create prunes — it strictly rejects) and the `openapi.yaml` `EntryUpdate.category_ids` 422 text (PATCH prunes on merge). No backend behavior change.
- Non-goals: no snapshot-reconciliation change (tombstone/spec tension documented as follow-up), no same-second user-edit 409 papercut fix, no realtime sync, no visual or copy changes.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `sync-client`: entry pushes ensure categories exist first; entry pull adopts-or-remaps snapshot ids and heals superset forks; prune-and-retry remains last-resort only.

## Impact

- Affected code: `SyncController` (drain ensure step, pull merge + join-heal), `LocalStore` (helpers as needed; single mutation chokepoint preserved), `SyncControllerTests` + History/Insights VM tests (new coverage), `backend/internal/db/store.go` comment + `backend/api/openapi.yaml` text (doc-only).
- No API, schema, entitlement, or localization impact; no new strings.
