## Why

Deleting an activity (or category/entry) and then syncing brings the deleted record back: the pull-merge upserts every server record by id with no knowledge of local deletions, so any server copy that has not converged yet is re-inserted locally. Three paths resurrect:

1. **First-sync is pull-first** with a pending outbox DELETE: the pull runs before the drain pushes the DELETE, merges the still-present server copy (the local row is gone, so LWW has nothing to compare), and the drain then deletes it on the relay while the resurrected local copy stays — permanently, with no outbox row to ever remove it.
2. **Buffered (undoable, not yet committed) deletions** have no outbox row at all: any pull that returns the server copy (always, for the full category snapshot; when the cursor admits it, for activities/entries) re-inserts it. The later cold-launch commit then enqueues a DELETE for a record that is live again locally, and the drain deletes it on the relay while the zombie stays.
3. **Push-conflict adoption** (`409 conflict` → adopt server version) merges the server copy even when the conflicting row was superseded by a local delete queued behind it in the same drain.

## What Changes

- Pull-merge becomes delete-wins: `applyServer` for activities, categories, and entries skips any server record the user deleted locally — a committed outbox DELETE or a buffered undoable deletion — with a secret-free log. The queued DELETE still converges the relay on drain.
- Push-conflict adoption (`adoptServerVersion`) skips the merge under the same condition; the outbox row still clears and the queued DELETE still runs.
- New `LocalStore` tombstone reads (no schema change): `hasPendingDelete`, `isBufferedForDeletion`, and the combined `isLocallyDeleted` guard.
- Undo and successful drains lift the guard automatically (buffer row / outbox row gone), so newer server versions merge normally afterwards.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `sync-client`: delete-wins on pull-merge and on conflict adoption.
- `local-first-store`: tombstone reads over the existing outbox + undo-buffer tables.

## Impact

- `SyncController.applyServer` × 3 + `adoptServerVersion`; `LocalStore` gains three read-only queries (no migration — the tables already exist).
- No OpenAPI changes; no backend changes (hard DELETE + idempotent replay already converge the relay once the drain pushes).
- Out of scope: cross-device delete propagation for activities/entries (the relay hard-deletes with no tombstones, and delta pulls only return live records, so a second device keeps its copy — categories already reconcile via the full snapshot; entries/activities need a deleted-since contract first). Tracked as a follow-up, not claimed here.
