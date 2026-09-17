# Local-First Store — Erase Resets Auth Flow Delta

## MODIFIED Requirements

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