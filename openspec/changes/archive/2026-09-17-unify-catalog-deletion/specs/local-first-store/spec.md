## ADDED Requirements

### Requirement: Activity deletions enter the durable undo buffer with full snapshots

Confirming an activity deletion SHALL write one undo-buffer row carrying the full activity record (identity, values, ordered category assignments) plus every committed entry of that activity, and remove the activity, its join rows, and its entries in the same transaction. No outbox row SHALL be created while the deletion is buffered. Restoring (at any time before the app restarts) SHALL re-insert the activity, its assignments, and its entries and delete the buffer row in one transaction, with no outbox row ever created. On app restart, the cold-launch commit SHALL enqueue one outbox DELETE row per snapshotted record (the activity plus each entry); entry rows that the relay already removed via cascade resolve as success (404-treats-as-success) and never fail the drain.

#### Scenario: Activity delete enters buffer atomically

- **WHEN** the user confirms an activity deletion
- **THEN** the system writes one undo-buffer row with the activity and all its entries and removes those records in one transaction; no outbox row is created

#### Scenario: Undo restores activity and entries

- **WHEN** the user triggers undo (at any time before restarting the app)
- **THEN** the system restores the activity, its category assignments, and all snapshotted entries from the payload and deletes the buffer row in one transaction; the relay is never notified

#### Scenario: Restarted app commits buffered deletions to the outbox

- **WHEN** the app restarts with buffered activity deletions
- **THEN** the cold-launch commit deletes each buffer row and inserts one outbox DELETE row for the activity and one per entry in one transaction; already-cascaded entry rows succeed as 404s

### Requirement: Running-timer activity deletion is refused at the store boundary

The undoable activity delete SHALL refuse when a timer is running against that activity: nothing is removed, no buffer row is written, and the caller receives a distinct blocked outcome so the UI can explain that the timer must be stopped first. The running `timer_state` row SHALL never reference a deleted activity.

#### Scenario: Delete refused for the running activity

- **WHEN** an undoable delete is requested for the activity with the running timer
- **THEN** the store removes nothing, buffers nothing, and reports the run-blocked outcome
