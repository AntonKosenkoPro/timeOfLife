# sync-client delta spec

## MODIFIED Requirements

### Requirement: Sync is optional and gated on sign-in
The system SHALL activate the sync client only when the user holds an active signed-in session; a valid session is mandatory for every sync operation. When no session is active, the sync client SHALL NOT run: no sync network traffic is sent signed-out, no outbox is drained, and no delta pull runs. Because sign-in precedes tracking (per the app-shell and local-first-store deltas), a signed-out state exists only before the first sign-in or after sign-out with the account's local file dormant, and the outbox drains only after a signed-in session resumes that account's file.

#### Scenario: Unsigned user
- **WHEN** the user has not signed in
- **THEN** the app offers no function without an account — tracking sits behind the sign-in gate — and the sync client performs no operation: no request reaches the backend, the outbox is not drained, and no delta pull runs

#### Scenario: Sign-in activates sync
- **WHEN** the user signs in (OTP or Apple Sign-in) and the account's local file becomes active
- **THEN** the sync client activates for that account, performs a first-sync (pull-then-push), and begins responding to sync triggers

#### Scenario: Sign-out deactivates sync
- **WHEN** the user signs out
- **THEN** the sync client deactivates and stops making requests; the account's local database file and its outbox are preserved intact in the dormant per-user file, so re-signing in as the same account resumes the drain

### Requirement: Manual sync and status visibility
The system SHALL expose a "Sync now" action and a sync status ("Last synced: <relative time>" or "Syncing…" or an error state) in Profile, visible whenever the user is signed in. The action calls the same drain+pull path as the automatic triggers. While a sync is in progress, the "Sync now" button SHALL keep its title (disabled) and the status row SHALL be the single "Syncing…" surface — never two. A failed cycle SHALL surface its captured error message alongside the generic error state (secret-free: codes and server messages only). Status views SHALL subscribe to the sync status directly rather than through a non-publishing intermediary, so the display follows the cycle on its own.

#### Scenario: Status display
- **WHEN** the user views Profile while signed in
- **THEN** the sync status and "Sync now" button are visible; while a sync is in progress, the button is disabled under its own title and exactly one "Syncing…" indicator is shown

#### Scenario: Status follows the cycle without manual refresh
- **WHEN** a sync cycle completes (or fails) while Profile is visible
- **THEN** the status row and button state update on their own — no navigation or re-render trigger needed

#### Scenario: Error state
- **WHEN** a sync cycle fails (network error, 5xx)
- **THEN** the status shows an error with its captured message and the "Sync now" button remains enabled to allow retry

## ADDED Requirements

### Requirement: Same-account guard on sync cycles
Every sync cycle SHALL be bound to the account it serves: the sync client SHALL record the `userId` the cycle's local database file is bound to and SHALL verify it against the authenticated session's `userId` before acting. On account mismatch, the cycle SHALL be refused or skipped — the client SHALL never drain or push one account's outbox, or apply a pull for one account's database, under another account's token. The guard SHALL be checked at cycle start and SHALL remain in effect if the active account changes mid-cycle.

#### Scenario: Cycle is refused on account mismatch
- **WHEN** a sync cycle finds the bound `userId` of the active local database differs from the authenticated session's `userId`
- **THEN** the cycle is skipped with a secret-free log entry and the outbox is left untouched

#### Scenario: Outbox is never pushed under another account's token
- **WHEN** a signed-in session for account B becomes active while account A's outbox still holds rows in a dormant file
- **THEN** account A's outbox rows stay in A's dormant file and are never drained or pushed under B's session token

#### Scenario: Mid-cycle account change aborts the cycle
- **WHEN** the active account changes (sign-out or account swap) while a sync cycle is in flight
- **THEN** the in-flight cycle aborts without draining further rows or applying further pulled records to the swapped-out account's file