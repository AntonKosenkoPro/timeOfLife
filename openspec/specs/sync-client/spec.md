# sync-client Specification

## Purpose

The optional background sync layer that, when the user signs in, keeps the local database and the backend relay eventually consistent by draining the outbox and pulling deltas. Activated on sign-in, deactivated on sign-out; the app works fully without it.
## Requirements
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
On pull, the sync client SHALL apply a server record to the local database only if `server.updated_at > local.updated_at` for the same record id; otherwise the local version is kept. On push, a 409 `conflict` response SHALL cause the client to adopt the server's version (keep-latest) and clear the outbox row, per the existing R2 design. When a server record's normalized name matches a DIFFERENT local id, the newer `updated_at` owns the name: a newer server record SHALL be adopted via identity remap (local references move to the server id, the losing local identity is removed without emitting a delete); otherwise the local record is kept and the server record is skipped for this cycle. The pull SHALL NOT fail on such collisions.

#### Scenario: Newer server record overwrites local
- **WHEN** a pulled record has `updated_at` greater than the local record's `updated_at`
- **THEN** the local record is overwritten with the server version

#### Scenario: Newer local record resists server
- **WHEN** a pulled record has `updated_at` less than the local record's `updated_at`
- **THEN** the local record is preserved and the server version is discarded

#### Scenario: Push conflict adopts server version
- **WHEN** the client pushes an outbox row and receives 409 `conflict` with the server's current version in `details`
- **THEN** the client overwrites the local record with the server version, clears the outbox row, and surfaces an informational "Edited on another device" state (non-blocking, keep-latest)

#### Scenario: Pull adopts newer server identity on name collision
- **WHEN** a pulled category/activity has the same normalized name as a local row with a different id and a newer `updated_at`
- **THEN** local references (joins, entries, pending outbox payloads) move to the server id, the losing local identity is removed with its create row, and the cycle continues

#### Scenario: Pull keeps newer local identity on name collision
- **WHEN** a pulled category/activity has the same normalized name as a local row with a different id and an older-or-equal `updated_at`
- **THEN** the local record is kept, the server record is skipped (logged, secret-free), and the cycle continues; convergence follows when the name frees up or a later server version wins

### Requirement: Cross-device name collision remapping
When the client pushes a create and receives 409 `activity_exists` or `category_exists`, it SHALL re-map local references (entries, tags) to the winning record's id returned in `details`, clear the outbox row, and proceed without surfacing an error to the user, per the existing design. Conflict recovery SHALL never synthesize record content: when the winning-record fetch fails, the recovery SHALL rethrow — keeping the outbox row queued for retry — instead of merging a stub, and local records SHALL keep their real names until the real winner arrives. When merging a server activity, the client SHALL translate its category references to local ids (by id, else by normalized name from the pulled snapshot) so joins never reference a skipped server category; an unresolvable reference SHALL skip the activity (transient, retried next pull), never fail the cycle.

#### Scenario: Activity name collision on push
- **WHEN** the client pushes a local activity and receives 409 `activity_exists` with the existing activity's `{id, name}` in `details`
- **THEN** the client re-maps any local entries referencing the local id to the server's id, clears the outbox row, and does not show an error

#### Scenario: Winner fetch failure retries instead of stubbing
- **WHEN** the winning-record fetch fails during `activity_exists`/`category_exists` recovery
- **THEN** the client merges nothing, keeps the outbox row, and surfaces the cycle failure normally; the next cycle retries with local names intact

#### Scenario: Activity merge translates skipped server categories
- **WHEN** a pulled activity tags a server category that was skipped (local counterpart kept)
- **THEN** the merge attaches the local counterpart's id; the join write succeeds and the cycle continues

### Requirement: Idempotent outbox drain
The sync client SHALL drain the outbox by issuing one HTTP request per outbox row, in created_at order within a resource. Because POST is idempotent on `id` and PATCH carries `updated_at` (LWW), replaying an outbox row is safe; a replay after a crash or relapse produces the same result as the first attempt. A pulled entry whose activity is absent locally (skipped server branch) SHALL be skipped with a log instead of failing the cycle on the foreign-key constraint; the next pull retries.

#### Scenario: Replay after relaunch
- **WHEN** the app was killed mid-drain and relaunched, leaving some outbox rows already pushed and some not
- **THEN** re-pushing the already-pushed rows returns 200 (idempotent) or 409 (already newer) — both treated as success — and the outbox clears cleanly

#### Scenario: Entry without provenance defaults to manual
- **WHEN** a pulled entry omits `source` (relays predating entry provenance)
- **THEN** the entry decodes with `source` = "manual" (mirroring the relay's own back-compat) instead of failing the pull on `keyNotFound`

#### Scenario: Entry with missing activity is skipped
- **WHEN** a pulled entry references an activity id with no local row
- **THEN** the entry is skipped (logged), the cycle completes, and a later pull retries after the activity lands

### Requirement: Sync triggers
The sync client SHALL run on: (1) app enters foreground, (2) connectivity restores (NWPathMonitor `.satisfied`), (3) manual "Sync now" action. On macOS, a timer-based background sync (every N minutes while running) SHALL be added; on iOS, background task scheduling SHALL NOT be used (unreliable).

#### Scenario: Foreground trigger
- **WHEN** the app enters the foreground
- **THEN** the sync client runs a drain-outbox + delta-pull cycle (if signed in)

#### Scenario: Connectivity restored
- **WHEN** connectivity transitions to `.satisfied` while signed in
- **THEN** the sync client runs a cycle

#### Scenario: Manual sync
- **WHEN** the user taps "Sync now" in Profile
- **THEN** the sync client runs a cycle and updates the displayed "Last synced" timestamp on completion

### Requirement: Manual sync and status visibility
The system SHALL expose a "Sync now" action and a sync status ("Last synced: <relative time>" or "Syncing…" or an error state) in Profile, visible only when signed in. The action calls the same drain+pull path as the automatic triggers. While a sync is in progress, the "Sync now" button SHALL keep its title (disabled) and the status row SHALL be the single "Syncing…" surface — never two. A failed cycle SHALL surface its captured error message alongside the generic error state (secret-free: codes and server messages only). Status views SHALL subscribe to the sync status directly rather than through a non-publishing intermediary, so the display follows the cycle on its own.

#### Scenario: Status display
- **WHEN** the user views Profile while signed in
- **THEN** the sync status and "Sync now" button are visible; while a sync is in progress, the button is disabled under its own title and exactly one "Syncing…" indicator is shown

#### Scenario: Status follows the cycle without manual refresh
- **WHEN** a sync cycle completes (or fails) while Profile is visible
- **THEN** the status row and button state update on their own — no navigation or re-render trigger needed

#### Scenario: Error state
- **WHEN** a sync cycle fails (network error, 5xx)
- **THEN** the status shows an error with its captured message and the "Sync now" button remains enabled to allow retry

### Requirement: Relay wire-format date decoding
The client SHALL decode every relay timestamp as RFC 3339 (`format: date-time`) through dedicated wire shapes, never through the local models' timestamp decoding. Categories and entries use wire decoding like activities do. A decoding failure SHALL surface as a normal cycle error, never a stuck "Syncing…".

#### Scenario: Non-empty pull decodes
- **WHEN** the relay returns categories or entries with RFC 3339 timestamps (with or without fractional seconds)
- **THEN** the pull merges them and the cycle completes; no `typeMismatch` on `created_at`/`updated_at`

### Requirement: Delete-wins on pull-merge

On pull, the sync client SHALL NOT apply a server record the user deleted locally — a deletion sitting in the durable undo buffer (no outbox row yet) or a committed deletion with a pending outbox DELETE row. Such records SHALL be skipped with a secret-free log, and the cycle SHALL continue; the queued DELETE (once committed and drained) converges the relay. Undoing the deletion or successfully draining the DELETE lifts the exclusion, after which newer server versions merge under the normal last-write-wins rule.

#### Scenario: First-sync with a pending activity delete

- **WHEN** the outbox holds an activity DELETE and the relay still returns that activity (pull-first runs before the drain pushes the DELETE)
- **THEN** the pull skips the record, the drain pushes the DELETE, the outbox clears, and the activity stays deleted locally with an idle cycle

#### Scenario: Buffered activity deletion survives a pull

- **WHEN** an activity deletion sits in the undo buffer (no outbox row) and a pull returns the relay's copy
- **THEN** the pull skips the record, the local row stays gone, the buffer row stays restorable, and the cycle completes

#### Scenario: Buffered category deletion survives the full snapshot

- **WHEN** a category deletion sits in the undo buffer and the authoritative category snapshot still contains it
- **THEN** the pull skips the record (snapshot reconciliation never re-creates it via merge) and the buffer row stays restorable

#### Scenario: Buffered entry deletion survives a pull

- **WHEN** an entry deletion sits in the undo buffer and a pull returns the relay's copy
- **THEN** the pull skips the record and the buffer row stays restorable

#### Scenario: Push-conflict adoption respects a superseding delete

- **WHEN** an outbox update (or create) push receives 409 `conflict` but a DELETE for the same record is queued behind it in the same drain
- **THEN** the client skips adopting the server version (the local deletion stands), clears the conflicting row, and the queued DELETE converges the relay

### Requirement: Tombstone fetch and apply

Every sync cycle SHALL fetch the relay's deletion tombstones since the `deletions` cursor and apply them locally BEFORE draining the outbox. Applying a tombstone SHALL delete the local row (activities cascade to entries and joins) with no outbox row, drop pending create/update outbox rows for the affected ids, and leave pending DELETE rows to converge via the existing 404-as-success. The cursor SHALL advance to the max `deleted_at` received, and stay unchanged when the list is empty. A tombstone for an unknown id is a no-op that still advances the cursor.

#### Scenario: Activity deleted on another device converges

- **WHEN** the relay holds an activity tombstone and this device holds the live activity with committed entries
- **THEN** after a sync the activity, its entries, and its joins are gone locally, no outbox row exists for them, the cycle is idle, and the cursor advanced past the tombstone

#### Scenario: Entry deleted on another device converges

- **WHEN** the relay holds an entry tombstone and this device holds the live entry
- **THEN** after a sync the entry is gone locally with no outbox row and the cycle is idle

#### Scenario: Category deleted on another device converges

- **WHEN** the relay holds a category tombstone and this device holds the live category attached to an activity
- **THEN** after a sync the category and its joins are gone, the activity survives untagged, and no outbox row exists

#### Scenario: Tombstones apply before the drain

- **WHEN** this device holds a stale pending update for a record the relay tombstoned
- **THEN** the tombstone step drops the update row before the drain runs, so no 404 is ever pushed for it and the cycle stays idle

#### Scenario: Stale tombstone never kills a recreation (R1)

- **WHEN** the local row is clean (no pending create/update) and newer than the tombstone (`updated_at > deleted_at`)
- **THEN** the row is kept and the tombstone is buried by the cursor advance

#### Scenario: Empty deletions keep the cursor

- **WHEN** the deletions fetch returns no tombstones
- **THEN** the cursor is unchanged and no local state is touched

