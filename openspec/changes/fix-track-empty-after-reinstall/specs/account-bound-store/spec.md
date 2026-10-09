## MODIFIED Requirements

### Requirement: First login adopts or creates the account file
The system SHALL, on the first successful sign-in as an account, open that account's database file — creating it if absent — and seed it with the starter categories exactly once per account file. Pre-existing anonymous/dev-install data SHALL NOT be migrated (discarded pre-release). The sign-in lifecycle SHALL run in bind-then-reveal order: open the account file, commit buffered deletions from the previous process, seed starter categories, and only then reveal the shell; sync activation and the first-sync pull-first cycle start after the reveal and run in the background, never blocking it.

#### Scenario: Fresh account seeds starter categories
- **WHEN** the user signs in for the first time as an account with no database file on disk
- **THEN** the file is created in the App Group container, starter categories are seeded into it once, and no leftover anonymous data from a previous install state appears

#### Scenario: Reinstall after erase re-seeds
- **WHEN** the account's file was erased and the user signs in again as that account
- **THEN** a new file is created and starter categories are seeded again

#### Scenario: Shell never mounts before seed
- **WHEN** a fresh sign-in binds a new account file that still needs starter seeding
- **THEN** no tracker read mounts before the seed completes, so the first Track paint carries the starter categories instead of an empty category map

#### Scenario: First sync stays background
- **WHEN** the shell is revealed after bind, commit, and seed
- **THEN** the pull-first first-sync cycle runs concurrently without delaying the reveal, and tracker screens converge on pulled data via their sync-exit reloads; an offline or failed first sync never holds the splash or the shell
