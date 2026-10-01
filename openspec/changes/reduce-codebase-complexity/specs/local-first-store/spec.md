## MODIFIED Requirements

### Requirement: Durable undo buffer
The system SHALL hold deletions in a durable `undo_buffer` table (not in-memory) with no wall-clock window: a buffered deletion stays restorable until the app restarts. No outbox row is created while a deletion is in the undo buffer. A buffered deletion commits on cold launch (the backstop that inserts the outbox rows) or on the next successful sync push (push-then-commit): the sync client sends one `DELETE` per snapshotted record and drops the buffer row only after all its pushes succeed. While a buffered row's push is in flight, undo of that row is refused (transient guard); otherwise undo restores the records and drops the row with no outbox row ever created, so the backend relay is never notified of the deletion. Only the most recent buffered deletion is restorable (supersession); older rows stay buffered until undone or the app restarts. Entries and categories share this buffer.

#### Scenario: Delete enters buffer atomically
- **WHEN** the user confirms deletion of an entry or category
- **THEN** the system writes an undo_buffer row (containing a full serialized snapshot of the deleted records) and deletes the records in one transaction; no outbox row is created

#### Scenario: Undo within window restores records
- **WHEN** the user triggers undo while the process is still alive (no wall-clock window — restorable until restart)
- **THEN** the system restores the records from the buffer's payload and deletes the buffer row in one transaction; no outbox row is ever created, so the backend relay is never notified of the deletion

#### Scenario: Push commits the buffer
- **WHEN** a sync cycle pushes every snapshotted record's `DELETE` successfully
- **THEN** the system drops the buffer row in the same step; a later undo finds nothing to restore

#### Scenario: Window elapses in background
- **WHEN** the app is backgrounded or foregrounded while the process stays alive (no wall-clock window exists)
- **THEN** no commit occurs on any time boundary; buffered rows remain restorable until restart or a successful push

#### Scenario: Undo after cold launch within window
- **WHEN** the app was killed and relaunched with the buffered row still present (no wall-clock window — commit-on-restart replaces the window)
- **THEN** the system commits the buffered deletion (drops the buffer row and inserts the outbox rows) with no restore path afterwards; no unsolicited UndoToast is shown on cold launch

#### Scenario: Supersession
- **WHEN** the user performs a second undoable deletion while a first is still in the buffer
- **THEN** only the most recent deletion is restorable; the older deletion stays buffered until undone or the app restarts

#### Scenario: In-flight push refuses undo
- **WHEN** the user triggers undo for a buffered row while its `DELETE` push is in flight
- **THEN** the undo is refused with the existing persistence error; the push completes and drops the row, or fails and leaves the row undoable for the next cycle
