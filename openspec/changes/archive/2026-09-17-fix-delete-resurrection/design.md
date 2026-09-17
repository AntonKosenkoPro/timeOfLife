# Design: fix-delete-resurrection

## Context

Local-first (D1–D6): the device is the source of truth, every mutation writes state + outbox row in one transaction (D2), deletions rest in the durable undo buffer with no outbox row until cold-launch commit (D3), and `SyncController` reconciles via outbox drain + `?modified_since=` delta pulls with LWW on `updated_at` (D4/D5). First-sync is pull-first to let relay ids arrive before local pushes (avoids name collisions).

## The bug, precisely

LWW compares `server.updated_at > local.updated_at` **for the same record id**. A locally deleted record has no local row, so the comparison is vacuous and the merge unconditionally re-inserts the server copy. The three resurrection paths (proposal) all reduce to this: the pull (or the conflict adoption, which is a pull by another name) does not know the absence is intentional.

## Decision: delete-wins via existing tombstones, no new state

**Alternative considered — drain-before-pull everywhere:** would fix path 1 but reintroduces the cross-device name-collision failures that pull-first was built to avoid (server ids must arrive before local pushes), and does nothing for buffered deletions (no outbox row to drain). Rejected.

**Alternative considered — backend tombstones / deleted-since:** the complete fix for cross-device propagation, but a contract + migration + backfill change far beyond this bug (single-device resurrection). Explicitly deferred; the proposal records it as a follow-up.

**Chosen:** treat the outbox DELETE row and the undo-buffer snapshot as the tombstones they already are:

- `LocalStore.hasPendingDelete(resource:recordID:)` — `COUNT(*) FROM outbox WHERE op = 'delete'`.
- `LocalStore.isBufferedForDeletion(resource:recordID:)` — scan `undo_buffer` snapshots for a matching `(resource, recordID)` (activity snapshots carry their entries' records too, so those entry ids are covered).
- `LocalStore.isLocallyDeleted(resource:recordID:)` — either of the above.
- `SyncController.applyServer` (activity/category/entry) returns early on a tombstone hit; `adoptServerVersion` skips the merge on a hit (the caller still clears the conflicting row, and the queued DELETE still converges the relay).

No schema change, no migration (pre-release policy untouched), no new tables, no OpenAPI change.

## Why the guard lifts correctly

- **Undo:** `undoBufferRestore` re-inserts the row and deletes the buffer row in one transaction → tombstone gone → later pulls merge newer server versions normally. (Previously the resurrect-then-undo path also broke undo itself: `INSERT OR IGNORE` kept the server version instead of the snapshot.)
- **Successful drain:** the DELETE push clears the outbox row and the relay copy is gone → nothing to skip.
- **Failed drain:** the outbox row stays and the guard keeps skipping → delete-wins across retries instead of flapping.
- **Name collisions:** the guard is per `(resource, id)`, not per name — a genuinely new cross-device record with a different id and the same name still follows the newer-owns-the-name rule. Deleting "Gym" locally does not block a different "Gym" arriving from another device.

## Constraints honored

- `LocalStore` stays the single mutation chokepoint; the new methods are reads.
- Secret-free logging (`privacy: .public` ids only), same as existing pull logs.
- `D10` ownership is irrelevant here (reads only match exact `(resource, recordID)` pairs; no snapshot is claimed or shredded).
