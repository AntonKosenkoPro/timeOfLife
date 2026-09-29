## Purpose

Per-user database file lifecycle for account-bound local data: naming, single-active-file selection, open/resume on login, dormant retention on logout, per-account erase, and the running timer's survival across account switches.

## ADDED Requirements

### Requirement: Per-user database file
The system SHALL store each account's local data in its own database file named `lifio_<userId>.db` inside the App Group shared container. At any moment exactly one file SHALL be active, and the active file SHALL be determined solely by the signed-in account's `user_id`.

#### Scenario: One active file per account
- **WHEN** the device holds dormant files for accounts A and B and the user is signed in as A
- **THEN** exactly one database file is active (A's), B's file remains on disk untouched, and no operation reads or writes B's file

### Requirement: First login adopts or creates the account file
The system SHALL, on the first successful sign-in as an account, open that account's database file — creating it if absent — and seed it with the starter categories exactly once per account file. Pre-existing anonymous/dev-install data SHALL NOT be migrated (discarded pre-release).

#### Scenario: Fresh account seeds starter categories
- **WHEN** the user signs in for the first time as an account with no database file on disk
- **THEN** the file is created in the App Group container, starter categories are seeded into it once, and no leftover anonymous data from a previous install state appears

#### Scenario: Reinstall after erase re-seeds
- **WHEN** the account's file was erased and the user signs in again as that account
- **THEN** a new file is created and starter categories are seeded again

### Requirement: Re-login resumes the dormant file
The system SHALL reopen the existing account file on re-login and resume without a full server re-pull: pending outbox operations drain, incremental sync cursors continue from where they stopped, and the running timer draft resumes.

#### Scenario: Outbox drains and cursors continue
- **WHEN** an account with pending outbox operations and advanced sync cursors logs out and later logs back in
- **THEN** the app opens the same file, drains the pending outbox, continues incremental pulls from the stored cursors, and never performs a full re-pull

### Requirement: Logout keeps all account files
The system SHALL preserve all account database files on logout. Only Keychain session tokens, cached session state, and in-memory session SHALL be cleared; a dirty outbox remains in the dormant file.

#### Scenario: Logout retains dormant dirty outbox
- **WHEN** the user logs out while the active file has uncommitted outbox operations
- **THEN** all files stay on disk, the dirty outbox remains in the now-dormant file, and only Keychain and cached session state are cleared

### Requirement: Running timer survives logout and account switch
The system SHALL keep a running timer's state in its account's file across logout or account switch, and SHALL resume it (elapsed time, activity) when that account becomes active again.

#### Scenario: Timer resumes after returning to its account
- **WHEN** a timer is running in account A, the user logs out and signs in as B, then later signs back in as A
- **THEN** account A's file still holds the running timer state, and on return the timer UI resumes with the elapsed time and activity intact; account B never sees A's timer

### Requirement: Explicit per-account erase
The system SHALL delete only the active account's database file and its session artifacts (Keychain/cache entries) when the user performs an explicit per-account erase action. Erase SHALL never occur as a side effect of logout, re-login, or account switch.

#### Scenario: Erase deletes only the active file
- **WHEN** the user confirms erase while signed in as account A, with account B's dormant file present
- **THEN** only A's file and its session artifacts are deleted; B's dormant file remains, and logout alone never deletes any file

### Requirement: Single active session
The system SHALL maintain at most one authenticated account at a time. Opening a second account's file SHALL require fresh authentication as that account; the app SHALL NOT keep a cached second session for switching.

#### Scenario: Switching accounts requires re-authentication
- **WHEN** the user, signed in as A, signs out and signs in as B
- **THEN** B's sign-in requires the full fresh authentication flow, no cached session for B is reused, and only one account is authenticated at any time