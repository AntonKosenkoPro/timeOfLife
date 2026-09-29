# local-first-store Specification — MODIFIED (account-bound-local-data)

## MODIFIED Requirements

### Requirement: Device is the source of truth
The system SHALL treat the active signed-in account's local SQLite database in the App Group shared container as the authoritative source of the user's categories, entries, entry-category assignments, and running timer draft. All app features (timer, history, insights) SHALL operate against this active account's database while the user is signed in, and SHALL function fully with no network connectivity. No app feature SHALL operate against any local database while the user is signed out: the auth gate is the only reachable surface, and it SHALL neither read nor write tracker data.

#### Scenario: App launches with no account
- **WHEN** the app is installed and launched for the first time, with no signed-in session
- **THEN** the auth gate precedes all data access: no anonymous timer, categories, or history is available, the app presents only the auth flow, and no tracker feature operates until sign-in completes

#### Scenario: Sync is unavailable
- **WHEN** the user is signed in but offline, or is not signed in
- **THEN** a signed-in user retains full local function (timer, categories, history) against the active account's database with no network connectivity, while a signed-out user has no tracker function and remains at the auth gate

### Requirement: Sign-out preserves local data
The system SHALL NOT wipe any per-account local database, outbox, or undo buffer when the user signs out. All per-account files — including the dormant file of the signed-out account and its pending dirty outbox — SHALL be kept on disk; re-signing in as the same account SHALL reopen its file and resume (drain the outbox, continue sync cursors, and resume a dormant running timer draft). The user's local data persists across sign-out. An explicit per-account "Erase local data" action is available in Profile for shared-device or privacy cases and SHALL delete only the active account's local file (with its associated keychain and cache entries); it MUST NOT touch other accounts' dormant files. Confirming "Erase local data" SHALL additionally reset the auth navigation so the auth gate starts over from its first step. The Profile "Erase local data" row SHALL present as destructive: its icon and title render in the danger token and its control carries destructive button semantics, so its appearance warns before the confirmation alert.

#### Scenario: Sign out keeps data
- **WHEN** the user signs out
- **THEN** the signed-out account's local database file is kept with its outbox intact, no other account's data is affected, and re-signing in as that account resumes from the dormant file

#### Scenario: Explicit erase
- **WHEN** the user taps "Erase local data" in Profile and confirms
- **THEN** only the active account's local database file is wiped (with its outbox, undo buffer, and associated keychain and cache entries); other accounts' dormant files are not touched, and the action is destructive and irreversible

#### Scenario: Erase row warns as destructive
- **WHEN** the user views the Profile "On This Device" section
- **THEN** the "Erase local data" row shows a danger-styled trash icon and danger-styled title and exposes destructive button semantics, visually distinct from the regular Categories row beside it

#### Scenario: Erase resets auth flow
- **WHEN** the erase is confirmed
- **THEN** the auth navigation resets so the launch gate starts at email entry with no previous address

## ADDED Requirements

### Requirement: Anonymous data is discarded on first login
Because this change ships pre-release, the system SHALL NOT migrate existing anonymous or prior-dev-install local data into any per-account database file. On the first sign-in under the account-bound model, the system SHALL discard the anonymous local database content and start the signed-in account with its own fresh per-account file. No compatibility branch or legacy-format read path SHALL be kept for anonymous data.

#### Scenario: First login starts fresh
- **WHEN** a user signs in for the first time on a device that holds anonymous pre-release data from a prior install or prior build
- **THEN** the anonymous data is not carried into the account's database; the signed-in account starts with an empty per-account file

#### Scenario: No migration path is retained
- **WHEN** the account-bound model is active
- **THEN** the system performs no anonymous-to-account migration, and no legacy anonymous database branch remains in the store

### Requirement: Starter seeding is per-account-file
The system SHALL seed starter categories into a per-account database file the first time that account's file is opened, and SHALL NOT re-seed it afterward. Each account's file is seeded independently: opening one account's file does not seed, modify, or reset any other account's file.

#### Scenario: New account file is seeded
- **WHEN** an account signs in and its per-account file is opened for the first time
- **THEN** the starter categories are seeded into that account's file and are immediately visible to the signed-in user

#### Scenario: Existing account file is not re-seeded
- **WHEN** the same account re-opens its existing per-account file after sign-out and sign-in
- **THEN** the starter seeding does not run again and the file's existing data is preserved as-is

#### Scenario: Seeding is scoped to the opened account
- **WHEN** an account's file is opened and seeded
- **THEN** no other account's dormant file is created, modified, or seeded as a side effect