## ADDED Requirements

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

## MODIFIED Requirements

### Requirement: Device is the source of truth
The system SHALL treat the local SQLite database in the App Group shared container as the authoritative source of the user's categories, entries, entry-category assignments, and running timer draft. All app features (timer, history, insights) SHALL operate against this local database and SHALL function fully with no network connectivity and no signed-in account.

#### Scenario: App launches with no account
- **WHEN** the app is installed and launched for the first time, with no signed-in session and no network connectivity
- **THEN** the user can start and stop a timer, create categories, and view history, with all data persisted to the local database

#### Scenario: Sync is unavailable
- **WHEN** the user is not signed in, or is signed in but offline
- **THEN** all app features continue to work against the local database; no feature is gated on the presence of a backend connection

### Requirement: Running timer state persistence
The system SHALL persist the running timer's draft state (entry text, ordered category ids, started_at, status) in the local database, not solely in app memory, so that the timer survives app crashes and is readable by widgets and lock-screen Controls.

#### Scenario: Timer survives app crash
- **WHEN** a timer is running and the app crashes or is killed by the OS
- **THEN** on next launch the app reads the draft from the database and resumes the running-timer UI (shows the elapsed time, the locked text, and the tags as left)

#### Scenario: Control displays running timer
- **WHEN** a lock-screen Control or widget renders while a timer is running
- **THEN** it reads the draft from the shared container database and displays the running status and elapsed time

### Requirement: Tombstone application
The local store SHALL apply a relay tombstone `(resource, record_id, deleted_at)` by removing the local row — entry-category joins cascade for entries and categories — in a single write transaction with no outbox row, and by dropping pending create/update outbox rows for every affected id. Pending DELETE rows SHALL be left untouched. A clean local row newer than the tombstone SHALL be kept (stale tombstone after a recreation).

#### Scenario: Activity tombstone cascades without outbox
- **WHEN** an entry tombstone is applied and the entry has category joins (activity tombstones no longer exist)
- **THEN** the joins and row are removed in one transaction, no outbox row is created, and pending create/update rows for the entry are gone

#### Scenario: Pending deletes survive tombstone application
- **WHEN** an outbox DELETE row exists for the tombstoned id
- **THEN** the DELETE row remains queued (it converges via 404-as-success on drain)

## REMOVED Requirements

### Requirement: Activity deletions enter the durable undo buffer with full snapshots
**Reason**: No activity entity exists; cascade activity deletion is gone. Per-entry delete remains under entry-editor.
**Migration**: Delete `ActivityDeletionSnapshot`, `remapActivityReferences`, pending-deletion restore, and activity cascade paths.

### Requirement: Running-timer activity deletion is refused at the store boundary
**Reason**: No activity exists to delete under a running timer.
**Migration**: The running draft references no deletable parent; stop always saves.
