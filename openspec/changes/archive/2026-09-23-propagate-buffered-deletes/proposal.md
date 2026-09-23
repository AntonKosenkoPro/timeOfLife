# Propagate buffered deletions on the next sync (Option A)

## Why

Deleting an entry (or category) on one device does not delete it on another
until the deleting device's app restarts. The deletion sits in the durable
`undo_buffer` with no outbox row (D3), so every sync cycle has nothing to
push; only the cold-launch `commitAll()` moves it to the outbox. Users
experience this as "delete doesn't sync," compounded by the History list
itself going stale after a delete (fixed separately by
`fix-history-sync-refresh`).

## What Changes

- Each sync cycle pushes buffered deletions to the relay **before draining
  the outbox**: for every `undo_buffer` row, send the corresponding
  `DELETE /entries/{id}` / `DELETE /categories/{id}`; on success drop the
  buffer row (the deletion is committed — undo ends there, exactly as it
  does today after a restart).
- Undo stays purely local: shake/toast restores the snapshot and drops the
  buffer row; the relay never sees an undone deletion (no compensating
  writes, ever). The undo window changes from "until restart" to "until the
  next successful push" — offline, the push cannot succeed, so undo stays
  available indefinitely.
- A deletion already pushed is no longer undoable (buffer row gone); a shake
  after that finds nothing, same as shaking after a restart today. The
  delete-confirm copy is updated to the new window (en + ru).
- Guard: while a buffered-delete push is in flight, undo of that row is
  refused (the push takes ~100ms); this closes the restore-vs-DELETE race
  where the relay deletes a record the user just restored with no outbox row
  left to repair the divergence.
- Cold-launch `commitAll()` stays as the backstop (e.g. deletes buffered
  while signed out), unchanged.
- No backend / OpenAPI changes: the relay already records tombstones on
  DELETE and serves `/deletions`.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `sync-client`: every sync cycle pushes buffered deletions before draining
  the outbox; on success the buffer row is dropped (undo ends).
- `local-first-store`: the durable-undo-buffer requirement gains the
  push-then-commit trigger and the in-flight undo guard; delete-confirm copy
  describes the "until synced" window instead of "until restart".

### Non-goals

- No soft-delete migration, no tombstone removal, no new endpoints.
- No UndoToast/shake-to-undo UI completion (still an incomplete surface).
- No change to delete-wins pull skips, LWW, R1, or drain ordering.
