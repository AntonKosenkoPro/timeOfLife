## REMOVED Requirements

### Requirement: App Group shared container
**Reason**: The former requirement mandates unbuilt widget/Screen Time/Control database writers and scenarios that are explicitly retired.
**Migration**: Preserve the storage location under “Account database remains in the App Group”; Live Activities render app-published content instead of opening the database.

### Requirement: Data protection level
**Reason**: Its Control-specific execution scenarios are retired, not the protection policy.
**Migration**: Preserve the same protection and no-partial-write behavior under “Account database data protection”.

### Requirement: Running timer state persistence
**Reason**: The former requirement combines durable drafts with an abandoned Control database reader.
**Migration**: Preserve draft crash recovery and app-published Live Activity mirroring under “Durable running draft and Live Activity mirroring”.

## ADDED Requirements

### Requirement: Account database remains in the App Group
The system SHALL continue to store each account's local database in the App Group shared container (`group.com.antonkosenko.timeoflifeapp`). Retiring entry integrations and the fallback extension writer SHALL NOT relocate account files or create a second copy of tracker data. The main app SHALL own entry mutations; the Live Activity extension SHALL render app-published activity content rather than independently opening or mutating the tracker database. No Home Screen capture widget, Screen Time extension, or lock-screen Control writer is required.

#### Scenario: Account database retains its location
- **WHEN** the app binds a signed-in account
- **THEN** its local database uses that account's App Group file, not a new private-container duplicate

#### Scenario: Live Activity renders without database access
- **WHEN** a Live Activity face renders
- **THEN** it shows the content published by the app without independently reading, opening, or writing an account database

### Requirement: Account database data protection
The system SHALL keep the local database's iOS data protection `.completeUntilFirstUserAuthentication`. Storage access after first unlock and graceful no-write behavior before first unlock SHALL remain independent of the retired Control/intent paths. An inaccessible database SHALL NOT cause anonymous file creation or partial entry writes.

#### Scenario: App storage after first unlock
- **WHEN** the device has been unlocked at least once since boot and an authorized app operation accesses its bound account store
- **THEN** the database retains the existing data-protection accessibility without a Control-specific requirement

#### Scenario: Database inaccessible after cold boot
- **WHEN** the database is unavailable before first unlock and an app operation cannot open it
- **THEN** no entry, partial mutation, or anonymous database is created and the failure is handled without corrupting local data

### Requirement: Durable running draft and Live Activity mirroring
The system SHALL persist the running timer's draft state (entry text, ordered category ids, notes, started_at, status) in the local database, not solely in app memory, so the timer survives app crashes. The main app SHALL publish the current name, categories, and elapsed anchor to the Live Activity; the extension SHALL NOT require a database reader. Notes remain in the draft and SHALL NOT be displayed on Live Activity faces.

#### Scenario: Timer survives app crash
- **WHEN** a timer is running and the app crashes or is killed by the OS
- **THEN** on next launch the app reads the draft from the database and resumes the running-timer UI (shows the elapsed time, the locked text, the tags as left, and the draft notes as left)

#### Scenario: Live Activity reflects the published run
- **WHEN** a timer is running and a Live Activity renders
- **THEN** it shows the app-published running content and system-ticked elapsed time without reading the timer draft itself

## MODIFIED Requirements

### Requirement: Entries own text, categories, and notes
Each entry SHALL own its `activity_text` (trimmed, non-empty, max 60 chars; case-sensitive identity), its ordered `category_ids` (zero or more, position-preserved via `entry_categories`), and its `notes` (max 2000 trimmed runes, default empty). No entry SHALL reference any other record for its display name or classification. The current local entry shape, undo snapshots, and outbox payloads SHALL NOT carry producer provenance or external import identifiers (`source` or `source_ref`). Retired relay provenance SHALL NOT affect the entry's identity, values, or editability.

#### Scenario: Entry saved with all fields
- **WHEN** a valid entry is saved with text, two ordered categories, and notes
- **THEN** all three persist on the entry and read back identically

#### Scenario: Per-entry isolation
- **WHEN** one entry's text, categories, or notes change
- **THEN** no other entry changes

#### Scenario: Notes past the bound are rejected
- **WHEN** an entry holds more than 2000 trimmed runes of notes
- **THEN** the relay rejects the create/update with a notes `validation_error` and the local entry is unchanged

#### Scenario: Source-free local mutation
- **WHEN** an entry is created, edited, buffered for deletion, or restored
- **THEN** the local entry, outbox payload, and undo snapshot contain the supported entry values without producer provenance; transactional and undo behavior remain unchanged
