# local-first-store Specification (delta)

## MODIFIED Requirements

### Requirement: Durable undo buffer
The system SHALL hold deletions in a durable `undo_buffer` table (not in-memory) with a wall-clock 30-second window computed from `deleted_at + 30s`, not from a Timer. No outbox row is created while a deletion is in the undo buffer. A buffered deletion commits on the next successful sync push (push-then-commit): the sync client sends one `DELETE` per snapshotted record and drops the buffer row only after all its pushes succeed. Cold-launch commit stays as the backstop for rows buffered while signed out or when the process died. While a buffered row's push is in flight, undo of that row is refused (transient guard); otherwise undo restores the records and drops the row with no outbox row ever created, so the backend relay is never notified of the deletion.

#### Scenario: Delete enters buffer atomically
- **WHEN** the user confirms a deletion
- **THEN** the system writes an undo_buffer row (containing a full serialized snapshot of the deleted records) and deletes the records in one transaction; no outbox row is created

#### Scenario: Undo within window restores records
- **WHEN** the user triggers undo before the deletion's push succeeds
- **THEN** the system restores the records from the buffer's payload and deletes the buffer row in one transaction; no outbox row is ever created, so the backend relay is never notified of the deletion

#### Scenario: Push commits the buffer
- **WHEN** a sync cycle pushes every snapshotted record's `DELETE` successfully
- **THEN** the system drops the buffer row in the same step; a later undo finds nothing to restore

#### Scenario: Window elapses in background
- **WHEN** the app is backgrounded during the 30s window and the window elapses while the app is not in the foreground
- **THEN** no commit occurs in the background; on the next foreground, the system detects the expired buffer and commits (deletes the buffer row + inserts outbox rows for the deletion) in one transaction

#### Scenario: Undo after cold launch within window
- **WHEN** the app was killed and relaunched within the 30s window (by wall clock)
- **THEN** the buffer row is still present; the system does not show an unsolicited UndoToast on cold launch, but if the user navigates to the affected screen within the window, the deletion can be undone from the durable buffer

#### Scenario: Supersession
- **WHEN** the user performs a second undoable deletion while a first is still in the buffer
- **THEN** only the most recent deletion is restorable via shake-to-undo / UndoToast (per existing U7); the older deletion commits when its own 30s window elapses

#### Scenario: In-flight push refuses undo
- **WHEN** the user triggers undo for a buffered row while its `DELETE` push is in flight
- **THEN** the undo is refused with the existing persistence error; the push completes and drops the row, or fails and leaves the row undoable for the next cycle
