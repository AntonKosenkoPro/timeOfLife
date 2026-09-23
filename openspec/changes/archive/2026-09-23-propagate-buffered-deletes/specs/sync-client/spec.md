# sync-client Specification (delta)

## MODIFIED Requirements

### Requirement: Delete-wins for entries and categories
On pull, the sync client SHALL NOT apply a server entry or category the user deleted locally — a deletion sitting in the durable undo buffer or a committed deletion with a pending outbox DELETE row. Such records SHALL be skipped with a secret-free log; the queued DELETE converges the relay on drain. In addition, every sync cycle SHALL push buffered (undoable) deletions to the relay before draining the outbox (push-then-commit): one `DELETE` per snapshotted record; on success the buffer row is dropped and undo ends for that deletion. A 404 on a buffered push is success (already gone); any other push error fails the cycle loudly with the row still buffered and undoable.

#### Scenario: Buffered entry deletion survives a pull
- **WHEN** an entry deletion sits in the undo buffer and a pull returns the relay's copy
- **THEN** the pull skips the record and the buffer row stays restorable

#### Scenario: First-sync with a pending entry delete
- **WHEN** the outbox holds an entry DELETE and the relay still returns that entry
- **THEN** the pull skips the record, the drain pushes the DELETE, and the entry stays deleted locally

#### Scenario: Buffered deletion pushes on the next cycle
- **WHEN** the user deletes an entry (or category) and a sync cycle runs while signed in and online
- **THEN** the cycle pushes the `DELETE` for every snapshotted record before draining the outbox; on success the buffer row is dropped, the relay holds a tombstone, and other devices converge on their next sync — no app restart required

#### Scenario: Failed buffered push stays undoable
- **WHEN** a buffered `DELETE` push fails with a non-404 error (network, 5xx)
- **THEN** the cycle fails loudly, the buffer row is kept, and the deletion can still be undone or retried on the next cycle

#### Scenario: Undo ends at push success
- **WHEN** a buffered deletion's pushes all succeeded and the buffer row was dropped
- **THEN** a later undo finds nothing to restore (same as undo after a restart today)
