## Purpose

The on-device source of truth for the user's time-tracking data — a SQLite database in the App Group shared container that the app, widgets, extensions, and lock-screen Controls all read and write cross-process.

## ADDED Requirements

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
The system SHALL NOT wipe the local database or the outbox when the user signs out of sync. The user's local data persists; an explicit "Erase local data" action is available in Settings for shared-device or privacy cases.

#### Scenario: Sign out keeps data
- **WHEN** the user signs out of sync
- **THEN** the local database, including the outbox, is preserved; the user can continue using the app locally and can re-sign-in to resume sync

#### Scenario: Explicit erase
- **WHEN** the user taps "Erase local data" in Settings and confirms
- **THEN** the local database is wiped (including the outbox and undo buffer); the action is destructive and irreversible