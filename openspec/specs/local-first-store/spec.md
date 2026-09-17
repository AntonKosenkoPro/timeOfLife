# local-first-store Specification

## Purpose

The on-device source of truth for the user's time-tracking data — a SQLite database in the App Group shared container that the app, widgets, extensions, and lock-screen Controls all read and write cross-process.
## Requirements
### Requirement: Device is the source of truth
The system SHALL treat the local SQLite database in the App Group shared container as the authoritative source of the user's activities, categories, entries, and running timer state. All app features (timer, catalog, history, insights) SHALL operate against this local database and SHALL function fully with no network connectivity and no signed-in account.

#### Scenario: App launches with no account
- **WHEN** the app is installed and launched for the first time, with no signed-in session and no network connectivity
- **THEN** the user can start and stop a timer, create activities and categories, and view the catalog, with all data persisted to the local database

#### Scenario: Sync is unavailable
- **WHEN** the user is not signed in, or is signed in but offline
- **THEN** all app features continue to work against the local database; no feature is gated on the presence of a backend connection

### Requirement: App Group shared container
The system SHALL store the local database in an App Group shared container (`group.com.antonkosenko.timeoflife`) so that the main app, widget extensions, Screen Time extension, and lock-screen Control intents can read and write the same data cross-process.

#### Scenario: Widget reads catalog
- **WHEN** a home-screen widget renders and reads the activities table from the shared container
- **THEN** it sees the same records the main app wrote, without a separate copy or IPC handshake

#### Scenario: Extension writes entry
- **WHEN** the Screen Time extension writes an entry to the shared container database
- **THEN** the main app observes that entry on its next foreground, without an explicit IPC call

### Requirement: Data protection level
The system SHALL store the local database with iOS data protection `.completeUntilFirstUserAuthentication` (the App Group container default), so that the database is accessible to lock-screen Control intents after the device has been unlocked at least once since boot.

#### Scenario: Lock-screen Control after first unlock
- **WHEN** the device was unlocked at least once since boot and is now locked, and a lock-screen Control intent runs with `alwaysAllowed` authentication policy
- **THEN** the intent can open and write to the shared container database successfully

#### Scenario: Database inaccessible after cold boot
- **WHEN** the device was just rebooted and has never been unlocked since boot, and a lock-screen Control intent runs
- **THEN** the intent fails gracefully (catches the database-open error), returns a "please unlock" state to the Control, and does not crash or leave the data in an inconsistent state

### Requirement: Running timer state persistence
The system SHALL persist the running timer's state (activity id, started_at, status) in the local database, not solely in app memory, so that the timer survives app crashes and is readable by widgets and lock-screen Controls.

#### Scenario: Timer survives app crash
- **WHEN** a timer is running and the app crashes or is killed by the OS
- **THEN** on next launch the app reads the timer state from the database and resumes the running-timer UI (shows the elapsed time and the activity name)

#### Scenario: Control displays running timer
- **WHEN** a lock-screen Control or widget renders while a timer is running
- **THEN** it reads the timer state from the shared container database and displays the running status and elapsed time

### Requirement: Transactional outbox
The system SHALL record every local mutation (create, update, delete) as a row in a transactional `outbox` table, written in the same database transaction as the state change. The outbox is the durable queue of operations to propagate to the backend relay when sync is active.

#### Scenario: Create writes state and outbox atomically
- **WHEN** the user creates a new activity
- **THEN** the system writes the activity row and an outbox row (op=create, resource=activity, record_id, payload) in a single transaction; if either write fails, neither is committed

#### Scenario: Delete is first-class in the outbox
- **WHEN** the user deletes an activity and the 30s undo window has elapsed
- **THEN** the system deletes the activity row and inserts an outbox row (op=delete, resource=activity, record_id) in one transaction; the outbox row persists even though the activity row is gone

#### Scenario: Outbox survives relaunch
- **WHEN** the app is killed and relaunched with pending outbox rows
- **THEN** the outbox rows are still present and will be drained by the sync client when it next runs

### Requirement: Durable undo buffer
The system SHALL hold deletions in a durable `undo_buffer` table (not in-memory) with a wall-clock 30-second window computed from `deleted_at + 30s`, not from a Timer. No outbox row is created while a deletion is in the undo buffer.

#### Scenario: Delete enters buffer atomically
- **WHEN** the user confirms a deletion
- **THEN** the system writes an undo_buffer row (containing a full serialized snapshot of the deleted records) and deletes the records in one transaction; no outbox row is created

#### Scenario: Undo within window restores records
- **WHEN** the user triggers undo before `deleted_at + 30s`
- **THEN** the system restores the records from the buffer's payload and deletes the buffer row in one transaction; no outbox row is ever created, so the backend relay is never notified of the deletion

#### Scenario: Window elapses in background
- **WHEN** the app is backgrounded during the 30s window and the window elapses while the app is not in the foreground
- **THEN** no commit occurs in the background; on the next foreground, the system detects the expired buffer and commits (deletes the buffer row + inserts outbox rows for the deletion) in one transaction

#### Scenario: Undo after cold launch within window
- **WHEN** the app was killed and relaunched within the 30s window (by wall clock)
- **THEN** the buffer row is still present; the system does not show an unsolicited UndoToast on cold launch, but if the user navigates to the affected screen within the window, the deletion can be undone from the durable buffer

#### Scenario: Supersession
- **WHEN** the user performs a second undoable deletion while a first is still in the buffer
- **THEN** only the most recent deletion is restorable via shake-to-undo / UndoToast (per existing U7); the older deletion commits when its own 30s window elapses

### Requirement: Sign-out preserves local data
The system SHALL NOT wipe the local database or the outbox when the user signs out of sync. The user's local data persists; an explicit "Erase local data" action is available in Profile for shared-device or privacy cases. Confirming "Erase local data" SHALL additionally reset the auth navigation so the auth flow starts over from its first step.

#### Scenario: Sign out keeps data
- **WHEN** the user signs out of sync
- **THEN** the local database, including the outbox, is preserved; the user can continue using the app locally and can re-sign-in to resume sync

#### Scenario: Explicit erase
- **WHEN** the user taps "Erase local data" in Profile and confirms
- **THEN** the local database is wiped (including the outbox and undo buffer); the action is destructive and irreversible

#### Scenario: Erase resets auth flow
- **WHEN** the erase is confirmed
- **THEN** the auth navigation resets so "Enable Sync" starts at email entry with no previous address

### Requirement: Local deletion tombstone reads

The local store SHALL expose read-only tombstone queries over the existing outbox and undo-buffer tables (no schema change): whether `(resource, record_id)` has a pending outbox DELETE, whether it sits in a buffered deletion snapshot (activity snapshots cover their entries' ids), and the combined exclusion used by the sync client.

#### Scenario: Committed delete is a tombstone until drained

- **WHEN** a deletion commits (outbox DELETE row exists) and has not been drained
- **THEN** the tombstone query reports it deleted; after the drain clears the row, it no longer does

#### Scenario: Buffered delete is a tombstone until undone or committed

- **WHEN** a deletion enters the undo buffer
- **THEN** the tombstone query reports every snapshotted `(resource, record_id)` deleted; after undo (row restored, buffer cleared) or cold-launch commit (buffer cleared, outbox DELETEs queued), the buffered tombstone no longer applies (the outbox one does, until drained)

### Requirement: Tombstone application

The local store SHALL apply a relay tombstone `(resource, record_id, deleted_at)` by removing the local row — entries and join rows cascade for activities — in a single write transaction with no outbox row, and by dropping pending create/update outbox rows for every affected id (the activity id plus its entry ids; the single id otherwise). Pending DELETE rows SHALL be left untouched. A clean local row newer than the tombstone SHALL be kept (stale tombstone after a recreation).

#### Scenario: Activity tombstone cascades without outbox

- **WHEN** an activity tombstone is applied and the activity has entries and category joins
- **THEN** the entries, joins, and row are removed in one transaction, no outbox row is created, and pending create/update rows for the activity and its entries are gone

#### Scenario: Pending deletes survive tombstone application

- **WHEN** an outbox DELETE row exists for the tombstoned id
- **THEN** the DELETE row remains queued (it converges via 404-as-success on drain)

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

