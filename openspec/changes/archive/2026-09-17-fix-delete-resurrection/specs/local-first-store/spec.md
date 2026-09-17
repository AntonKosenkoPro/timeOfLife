## ADDED Requirements

### Requirement: Local deletion tombstone reads

The local store SHALL expose read-only tombstone queries over the existing outbox and undo-buffer tables (no schema change): whether `(resource, record_id)` has a pending outbox DELETE, whether it sits in a buffered deletion snapshot (activity snapshots cover their entries' ids), and the combined exclusion used by the sync client.

#### Scenario: Committed delete is a tombstone until drained

- **WHEN** a deletion commits (outbox DELETE row exists) and has not been drained
- **THEN** the tombstone query reports it deleted; after the drain clears the row, it no longer does

#### Scenario: Buffered delete is a tombstone until undone or committed

- **WHEN** a deletion enters the undo buffer
- **THEN** the tombstone query reports every snapshotted `(resource, record_id)` deleted; after undo (row restored, buffer cleared) or cold-launch commit (buffer cleared, outbox DELETEs queued), the buffered tombstone no longer applies (the outbox one does, until drained)
