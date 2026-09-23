# Design: propagate buffered deletions (Option A)

## Context

D3 (durable undo buffer) keeps deletions local-only until cold launch so an
undone deletion never touches the relay. That guarantee is what makes undo
clean — and it is also what delays propagation indefinitely while the
process lives. Option A keeps the guarantee and moves the commit trigger
from "cold launch" to "next successful push."

## Decisions

### D1 — Push-then-commit, not enqueue-then-drain

The cycle pushes buffered deletions directly (`DELETE` per snapshotted
record) and drops each buffer row only after its push succeeds. The
alternative — moving buffer rows into outbox DELETE rows first, then
draining — would end undo at cycle *start* rather than at push *success*,
and would route deletes through outbox machinery (ordering, 404-resurrect)
built for queued writes rather than undoable ones. Direct push keeps the
window maximal and the semantics ("relay never sees an undone deletion")
exact.

### D2 — Step order in the cycle: tombstones → buffered pushes → drain → pull

Buffered pushes go right after `applyTombstones()` and before
`drainOutbox()`:

- Tombstones-first is unchanged: a tombstone for a buffered id drops the
  local row's conflicts the same way, and a buffered deletion whose record
  the relay already tombstoned pushes a DELETE that 404s — treated as
  success (already gone), same as the drain's 404-as-success.
- Buffered pushes run before the drain so a delete and a stale queued
  update for the same id cannot reorder: the delete lands first, and the
  drain's existing "drop stale update for missing record" rule then clears
  the update without pushing.
- The steady-state pull stays last and converges everything via LWW.

### D3 — In-flight undo guard, not compensating writes

While a buffered row's DELETE is in flight, undo of that row is refused
(transient; the push takes ~100ms). Rationale: the failure mode without a
guard — user restores locally, relay deletes remotely, no outbox row left
to repair the divergence — can only be fixed by a compensating recreate,
which is exactly the complexity Option A was chosen to avoid. The guard is
a single store-level check (`undoBufferPushInFlight` flag, set around the
push loop); undo paths check it and surface the existing persistence-error
copy when set.

### D4 — Per-record commit, category associations excluded

A buffer row's snapshot can hold several records (entry + joins are inline
in the entry payload; a category snapshot holds the category plus the
internal `category_associations` pseudo-record). The push step sends one
DELETE per real record (`entry`/`category`), skips the pseudo-record (same
exclusion as `undoBufferCommitAll`), and drops the buffer row only when
*all* its records pushed successfully. A partial failure keeps the whole
row buffered (and undoable) for the next cycle — never half-committed.

### D5 — Copy describes the window honestly

`entry.deleteMessage` and `delete.category.message` change from "shake to
undo until you restart the app" to "shake to undo until it syncs" (en +
ru + `L10n`, no new keys). The window is: until the next successful push
while signed in and online; indefinitely while offline or signed out.

### D6 — Cold-launch commit stays

`commitAll()` on cold launch is unchanged: deletes buffered while signed
out or while the process died mid-push still finalize on restart. The new
step and the old backstop converge — whichever runs first commits, the
other finds an empty buffer.

## Consequences

- Deletions propagate on the next sync (seconds when online) instead of the
  next restart. The reported issue is fixed with no relay changes.
- Undo is unchanged mechanically but shorter-lived online; the UI copy is
  the only user-visible change besides faster propagation.
- One new failure surface: a relay 5xx/validation error on a buffered
  DELETE fails the cycle loudly (status row) with the row still buffered —
  same treatment as any drain failure, retries next cycle.
