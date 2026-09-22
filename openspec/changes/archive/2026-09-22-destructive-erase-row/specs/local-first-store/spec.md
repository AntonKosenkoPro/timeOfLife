## MODIFIED Requirements

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
