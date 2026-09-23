# local-first-store Specification

## Purpose

The on-device source of truth for the user's time-tracking data — a SQLite database in the App Group shared container that the app, widgets, extensions, and lock-screen Controls all read and write cross-process.
## Requirements

### Requirement: Device is the source of truth
The system SHALL treat the local SQLite database in the App Group shared container as the authoritative source of the user's categories, entries, entry-category assignments, and running timer draft. All app features (timer, history, insights) SHALL operate against this local database and SHALL function fully with no network connectivity and no signed-in account.

#### Scenario: App launches with no account
- **WHEN** the app is installed and launched for the first time, with no signed-in session and no network connectivity
- **THEN** the user can start and stop a timer, create categories, and view history, with all data persisted to the local database

#### Scenario: Sync is unavailable
- **WHEN** the user is not signed in, or is signed in but offline
- **THEN** all app features continue to work against the local database; no feature is gated on the presence of a backend connection
### Requirement: App Group shared container
The system SHALL store the local database in an App Group shared container (`group.com.antonkosenko.timeoflifeapp`) so that the main app, widget extensions, Screen Time extension, and lock-screen Control intents can read and write the same data cross-process.

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
The system SHALL persist the running timer's draft state (entry text, ordered category ids, started_at, status) in the local database, not solely in app memory, so that the timer survives app crashes and is readable by widgets and lock-screen Controls.

#### Scenario: Timer survives app crash
- **WHEN** a timer is running and the app crashes or is killed by the OS
- **THEN** on next launch the app reads the draft from the database and resumes the running-timer UI (shows the elapsed time, the locked text, and the tags as left)

#### Scenario: Control displays running timer
- **WHEN** a lock-screen Control or widget renders while a timer is running
- **THEN** it reads the draft from the shared container database and displays the running status and elapsed time
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

### Requirement: Sign-out preserves local data
The system SHALL NOT wipe the local database or the outbox when the user signs out of sync. The user's local data persists; an explicit "Erase local data" action is available in Profile for shared-device or privacy cases. Confirming "Erase local data" SHALL additionally reset the auth navigation so the auth flow starts over from its first step. The Profile "Erase local data" row SHALL present as destructive: its icon and title render in the danger token and its control carries destructive button semantics, so its appearance warns before the confirmation alert.

#### Scenario: Sign out keeps data
- **WHEN** the user signs out of sync
- **THEN** the local database, including the outbox, is preserved; the user can continue using the app locally and can re-sign-in to resume sync

#### Scenario: Explicit erase
- **WHEN** the user taps "Erase local data" in Profile and confirms
- **THEN** the local database is wiped (including the outbox and undo buffer); the action is destructive and irreversible

#### Scenario: Erase row warns as destructive
- **WHEN** the user views the Profile "On This Device" section
- **THEN** the "Erase local data" row shows a danger-styled trash icon and danger-styled title and exposes destructive button semantics, visually distinct from the regular Categories row beside it

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
The local store SHALL apply a relay tombstone `(resource, record_id, deleted_at)` by removing the local row — entry-category joins cascade for entries and categories — in a single write transaction with no outbox row, and by dropping pending create/update outbox rows for every affected id. Pending DELETE rows SHALL be left untouched. A clean local row newer than the tombstone SHALL be kept (stale tombstone after a recreation).

#### Scenario: Activity tombstone cascades without outbox
- **WHEN** an entry tombstone is applied and the entry has category joins (activity tombstones no longer exist)
- **THEN** the joins and row are removed in one transaction, no outbox row is created, and pending create/update rows for the entry are gone

#### Scenario: Pending deletes survive tombstone application
- **WHEN** an outbox DELETE row exists for the tombstoned id
- **THEN** the DELETE row remains queued (it converges via 404-as-success on drain)
### Requirement: Entries own text, categories, and notes
Each entry SHALL own its `activity_text` (trimmed, non-empty, max 60 chars; case-sensitive identity), its ordered `category_ids` (zero or more, position-preserved via `entry_categories`), and its `notes` (max 280 runes, default empty). No entry SHALL reference any other record for its display name or classification.

#### Scenario: Entry saved with all fields
- **WHEN** a valid entry is saved with text, two ordered categories, and notes
- **THEN** all three persist on the entry and read back identically

#### Scenario: Per-entry isolation
- **WHEN** one entry's text, categories, or notes change
- **THEN** no other entry changes
### Requirement: Timer draft holds text and live categories
The `timer_state` singleton SHALL hold `(activity_text, ordered category_ids, started_at, status)` for the running draft. Toggles SHALL rewrite the snapshot in the same chokepoint transaction. Stop SHALL create the entry from the draft and clear it.

#### Scenario: Crash restores draft tags
- **WHEN** the app restarts with a persisted running draft
- **THEN** the timer resumes with the locked text and the tags as last left
