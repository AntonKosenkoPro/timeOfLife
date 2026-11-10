## ADDED Requirements

### Requirement: Database access is safe across process suspension

The app SHALL coordinate all account-bound database access with process execution availability so it does not retain a file or SQLite lock when suspended. When safe execution is unavailable, new database work SHALL fail or defer without partial mutations. Suspension SHALL NOT commit the undo buffer, erase local data, or discard a running timer draft or pending outbox operations.

#### Scenario: Suspension overlaps an active database operation
- **WHEN** the app is about to suspend while account-bound database work is active
- **THEN** that work completes within granted execution time or is interrupted with its locks released before suspension
- **AND** interrupted transactional mutations leave no partial state or orphaned outbox effects

#### Scenario: Work arrives after safe execution ends
- **WHEN** a reload or sync continuation attempts database access after safe execution becomes unavailable
- **THEN** it does not acquire a database lock until safe execution resumes
- **AND** existing committed data and pending local work remain intact

#### Scenario: Foreground access resumes
- **WHEN** the app returns to the foreground after database work was deferred or interrupted
- **THEN** normal reads and writes can resume for the bound account
- **AND** timer state and saved content are reconstructed from durable state rather than cleared on interruption

#### Scenario: Account binding changes across suspension
- **WHEN** the active account changes or signs out while database access is suspended
- **THEN** resumption does not reopen a dormant account or transfer delayed writes to a different account
- **AND** signed-out tracker access remains unavailable

#### Scenario: Existing background cleanup uses granted execution
- **WHEN** the system grants execution for an existing Live Activity cleanup task
- **THEN** necessary account-bound database work is permitted only within safe execution availability
- **AND** expiration releases database locks without creating a saved entry, inventing a saved duration, or committing buffered deletions
- **AND** this protection does not introduce background sync scheduling
