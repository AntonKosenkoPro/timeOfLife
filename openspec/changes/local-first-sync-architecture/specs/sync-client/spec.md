## Purpose

The optional background sync layer that, when the user signs in, keeps the local database and the backend relay eventually consistent by draining the outbox and pulling deltas. Activated on sign-in, deactivated on sign-out; the app works fully without it.

## ADDED Requirements

### Requirement: Sync is optional and gated on sign-in
The system SHALL activate the sync client only when the user has a signed-in session. When no session is active, no sync network traffic occurs, no outbox is drained, and no delta pull runs.

#### Scenario: Unsigned user
- **WHEN** the user has not signed in
- **THEN** the sync client is inactive; no requests are made to the backend; the outbox accumulates locally and is not drained

#### Scenario: Sign-in activates sync
- **WHEN** the user signs in (OTP or Apple Sign-in)
- **THEN** the sync client activates, performs a first-sync (pull-then-push), and begins responding to sync triggers

#### Scenario: Sign-out deactivates sync
- **WHEN** the user signs out
- **THEN** the sync client deactivates and stops making requests; the local data and outbox are preserved (per the local-first-store sign-out requirement)

### Requirement: First-sync is pull-first
On activation, the sync client SHALL pull the relay's current state (via `?modified_since=` with no since, i.e. full pull) and merge it into the local database (server-wins on `updated_at` conflicts) BEFORE draining the local outbox. This avoids cross-device name collisions by letting the relay's ids arrive before local pushes.

#### Scenario: First-sync with empty relay
- **WHEN** the user signs in for the first time (relay has no data for this user)
- **THEN** the pull returns nothing; the outbox drains and pushes all local records; no collisions

#### Scenario: First-sync with existing relay data
- **WHEN** the user previously used sync, signed out, used locally, and re-signs in
- **THEN** the pull brings the relay's current records down and merges them into the local database (server-wins on conflicts); then the outbox drains and pushes any local-only records, which are idempotent on `id` against existing relay records

### Requirement: Delta pull via modified_since
The sync client SHALL pull only records modified since the last successful pull, using the `?modified_since=<timestamp>` query parameter on `GET /activities` and `GET /entries`, and SHALL advance the per-resource sync cursor to the max `updated_at` received.

#### Scenario: Incremental pull
- **WHEN** the sync client runs after a previous successful pull recorded a cursor at time T
- **THEN** it requests `?modified_since=T` and receives only records with `updated_at > T`; it applies them locally with LWW merge and advances the cursor

#### Scenario: No changes
- **WHEN** the delta pull returns no records
- **THEN** the cursor is unchanged and no local updates are applied

### Requirement: Last-write-wins conflict resolution
On pull, the sync client SHALL apply a server record to the local database only if `server.updated_at > local.updated_at` for the same record id; otherwise the local version is kept. On push, a 409 `conflict` response SHALL cause the client to adopt the server's version (keep-latest) and clear the outbox row, per the existing R2 design.

#### Scenario: Newer server record overwrites local
- **WHEN** a pulled record has `updated_at` greater than the local record's `updated_at`
- **THEN** the local record is overwritten with the server version

#### Scenario: Newer local record resists server
- **WHEN** a pulled record has `updated_at` less than the local record's `updated_at`
- **THEN** the local record is preserved and the server version is discarded

#### Scenario: Push conflict adopts server version
- **WHEN** the client pushes an outbox row and receives 409 `conflict` with the server's current version in `details`
- **THEN** the client overwrites the local record with the server version, clears the outbox row, and surfaces an informational "Edited on another device" state (non-blocking, keep-latest)

### Requirement: Cross-device name collision remapping
When the client pushes a create and receives 409 `activity_exists` or `category_exists`, it SHALL re-map local references (entries, tags) to the winning record's id returned in `details`, clear the outbox row, and proceed without surfacing an error to the user, per the existing design.

#### Scenario: Activity name collision on push
- **WHEN** the client pushes a local activity and receives 409 `activity_exists` with the existing activity's `{id, name}` in `details`
- **THEN** the client re-maps any local entries referencing the local id to the server's id, clears the outbox row, and does not show an error

### Requirement: Idempotent outbox drain
The sync client SHALL drain the outbox by issuing one HTTP request per outbox row, in created_at order within a resource. Because POST is idempotent on `id` and PATCH carries `updated_at` (LWW), replaying an outbox row is safe; a replay after a crash or relapse produces the same result as the first attempt.

#### Scenario: Replay after relaunch
- **WHEN** the app was killed mid-drain and relaunched, leaving some outbox rows already pushed and some not
- **THEN** re-pushing the already-pushed rows returns 200 (idempotent) or 409 (already newer) — both treated as success — and the outbox clears cleanly

### Requirement: Sync triggers
The sync client SHALL run on: (1) app enters foreground, (2) connectivity restores (NWPathMonitor `.satisfied`), (3) manual "Sync now" action. On macOS, a timer-based background sync (every N minutes while running) SHALL be added; on iOS, background task scheduling SHALL NOT be used (unreliable).

#### Scenario: Foreground trigger
- **WHEN** the app enters the foreground
- **THEN** the sync client runs a drain-outbox + delta-pull cycle (if signed in)

#### Scenario: Connectivity restored
- **WHEN** connectivity transitions to `.satisfied` while signed in
- **THEN** the sync client runs a cycle

#### Scenario: Manual sync
- **WHEN** the user taps "Sync now" in Settings
- **THEN** the sync client runs a cycle and updates the displayed "Last synced" timestamp on completion

### Requirement: Manual sync and status visibility
The system SHALL expose a "Sync now" action and a sync status ("Last synced: <relative time>" or "Syncing…" or an error state) in Settings, visible only when signed in. The action calls the same drain+pull path as the automatic triggers.

#### Scenario: Status display
- **WHEN** the user views Settings while signed in
- **THEN** the sync status and "Sync now" button are visible; while a sync is in progress, the button is disabled and "Syncing…" is shown

#### Scenario: Error state
- **WHEN** a sync cycle fails (network error, 5xx)
- **THEN** the status shows an error and the "Sync now" button remains enabled to allow retry