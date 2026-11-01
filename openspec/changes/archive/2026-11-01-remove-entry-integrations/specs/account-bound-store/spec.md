## REMOVED Requirements

### Requirement: Confirmed account deletion cleans only the identified account
**Reason**: The extension-writer overlap scenario is retired with the final extension entry writer.
**Migration**: Preserve all account cleanup and ownership guarantees under “Account-scoped confirmed deletion cleanup”, replacing extension mutation with an app-side stop overlap scenario.

## ADDED Requirements

### Requirement: Account-scoped confirmed deletion cleanup
Explicitly confirmed server deletion or trustworthy remote confirmation SHALL schedule removal of that exact account UUID's local database, SQLite sidecars, outbox, undo buffer, cursors, timer draft, and account-owned session/cache/status artifacts. The system SHALL keep unrelated accounts' dormant files and the stable device identifier. A cleanup task SHALL remain bound to its original UUID even after sign-out, account switch, delayed response, or restart. Cleanup SHALL prevent the deleted account's file from being reopened or recreated by app work, including a delayed Live Activity Stop link. The Live Activity extension SHALL NOT act as a second database writer. This is a narrow deletion exception, not a change to logout preservation.

#### Scenario: Delete A while B is dormant
- **WHEN** A's account deletion is confirmed while B's file is present
- **THEN** A's data and session artifacts are removed, B's file remains intact, and the stable device identifier remains unchanged

#### Scenario: Delayed cleanup after switching accounts
- **WHEN** A's confirmed cleanup resumes after B has become the active account
- **THEN** it removes only A's data and does not clear B's session or active-session marker, erase B's file, reset B's navigation, or end B's Live Activity

#### Scenario: App stop overlaps cleanup
- **WHEN** an app-side stop request overlaps confirmed cleanup of that same account
- **THEN** the existing account/mutation fence prevents writing or recreating its file after cleanup, no stop-created entry escapes the fence, and no extension writer bypasses it
