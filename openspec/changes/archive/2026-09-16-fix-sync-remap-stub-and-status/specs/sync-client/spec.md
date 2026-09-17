# Sync Client — Remap, Status & Failure Transparency Delta

## MODIFIED Requirements

### Requirement: Cross-device name collision remapping
When the client pushes a create and receives 409 `activity_exists` or `category_exists`, it SHALL re-map local references (entries, tags) to the winning record's id returned in `details`, clear the outbox row, and proceed without surfacing an error to the user, per the existing design. Conflict recovery SHALL never synthesize record content: when the winning-record fetch fails, the recovery SHALL rethrow — keeping the outbox row queued for retry — instead of merging a stub, and local records SHALL keep their real names until the real winner arrives.

#### Scenario: Activity name collision on push
- **WHEN** the client pushes a local activity and receives 409 `activity_exists` with the existing activity's `{id, name}` in `details`
- **THEN** the client re-maps any local entries referencing the local id to the server's id, clears the outbox row, and does not show an error

#### Scenario: Winner fetch failure retries instead of stubbing
- **WHEN** the winning-record fetch fails during `activity_exists`/`category_exists` recovery
- **THEN** the client merges nothing, keeps the outbox row, and surfaces the cycle failure normally; the next cycle retries with local names intact

### Requirement: Manual sync and status visibility
The system SHALL expose a "Sync now" action and a sync status ("Last synced: <relative time>" or "Syncing…" or an error state) in Profile, visible only when signed in. The action calls the same drain+pull path as the automatic triggers. While a sync is in progress, the "Sync now" button SHALL keep its title (disabled) and the status row SHALL be the single "Syncing…" surface — never two. A failed cycle SHALL surface its captured error message alongside the generic error state (secret-free: codes and server messages only). Views SHALL observe `SyncController` (and `SessionStore`) directly as environment objects — nested reads through `AppContainer` never invalidate the view, freezing the status row on "Syncing…" and the button state.

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

### Requirement: Relay wire-format date decoding
The client SHALL decode every relay timestamp as RFC 3339 (`format: date-time`) through wire DTOs (`WireDate`), never through the local models' default `Double`-timestamp Codable. Categories and entries use `CategoryWireDTO`/`EntryWireDTO` like activities use `ActivityWireDTO`; a decoding failure SHALL surface as a normal cycle error, never a stuck "Syncing…".

#### Scenario: Non-empty pull decodes
- **WHEN** the relay returns categories or entries with RFC 3339 timestamps (with or without fractional seconds)
- **THEN** the pull merges them and the cycle completes; no `typeMismatch` on `created_at`/`updated_at`
