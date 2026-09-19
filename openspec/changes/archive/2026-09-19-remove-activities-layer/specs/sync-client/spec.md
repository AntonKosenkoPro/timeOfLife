## MODIFIED Requirements

### Requirement: Delta pull via modified_since
The sync client SHALL pull only records modified since the last successful pull, using the `?modified_since=<timestamp>` query parameter on `GET /entries` (and `GET /categories`), and SHALL advance the per-resource sync cursor to the max `updated_at` received.

#### Scenario: Incremental pull
- **WHEN** the sync client runs after a previous successful pull recorded a cursor at time T
- **THEN** it requests `?modified_since=T` and receives only records with `updated_at > T`; it applies them locally with LWW merge and advances the cursor

#### Scenario: No changes
- **WHEN** the delta pull returns no records
- **THEN** the cursor is unchanged and no local updates are applied

### Requirement: Last-write-wins conflict resolution
On pull, the sync client SHALL apply a server record to the local database only if `server.updated_at > local.updated_at` for the same record id; otherwise the local version is kept. On push, a 409 `conflict` response SHALL cause the client to adopt the server's version (keep-latest) and clear the outbox row. There SHALL be no cross-record name-identity remapping: equal or similar texts with different ids are independent records.

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
- **WHEN** a pulled record's text matches a different local id (name collision under exact-text identity)
- **THEN** no identity remap occurs: equal texts are independent records, the pull applies per-id LWW only, and the cycle continues

#### Scenario: Pull keeps newer local identity on name collision
- **WHEN** a pulled record's text matches a different local id and either side is newer
- **THEN** both records are kept as independent entries or categories; nothing merges, nothing is skipped for collision, and convergence needs no name-freedom step

### Requirement: Idempotent outbox drain
The sync client SHALL drain the outbox by issuing one HTTP request per outbox row, in created_at order within a resource. Because POST is idempotent on `id` and PATCH carries `updated_at` (LWW), replaying an outbox row is safe. Entries carry `activity_text`, ordered `category_ids`, and `notes`; unknown category ids on merge SHALL resolve by dropping the unknown id and keeping the remainder (logged, secret-free), never failing the cycle.

#### Scenario: Replay after relaunch
- **WHEN** the app was killed mid-drain and relaunched, leaving some outbox rows already pushed and some not
- **THEN** re-pushing the already-pushed rows returns 200 (idempotent) or 409 (already newer) — both treated as success — and the outbox clears cleanly

#### Scenario: Entry with unknown category is pruned
- **WHEN** a pulled entry references a category id with no local row
- **THEN** the unknown id is dropped, the entry merges with the remainder, and the cycle completes

#### Scenario: Entry without provenance defaults to manual
- **WHEN** a pulled entry omits `source` (relays predating entry provenance)
- **THEN** the entry decodes with `source` = "manual" instead of failing the pull

### Requirement: Tombstone fetch and apply
Every sync cycle SHALL fetch the relay's deletion tombstones since the `deletions` cursor and apply them locally BEFORE draining the outbox. Applying a tombstone SHALL delete the local row (entries cascade to their joins; categories cascade to entry joins) with no outbox row, drop pending create/update outbox rows for the affected ids, and leave pending DELETE rows to converge via the existing 404-as-success. The cursor SHALL advance to the max `deleted_at` received, and stay unchanged when the list is empty. A tombstone for an unknown id is a no-op that still advances the cursor.

#### Scenario: Entry or category deleted on another device converges
- **WHEN** the relay holds an entry or category tombstone from a device that deleted it
- **THEN** after a sync the entry is gone (or the category and its entry joins are gone with entries surviving untagged), no outbox row exists, and the cursor advanced past the tombstone

#### Scenario: Entry deleted on another device converges
- **WHEN** the relay holds an entry tombstone and this device holds the live entry
- **THEN** after a sync the entry is gone locally with no outbox row and the cycle is idle

#### Scenario: Category deleted on another device converges
- **WHEN** the relay holds a category tombstone and this device holds the live category attached to entries
- **THEN** after a sync the category and its entry joins are gone, the entries survive untagged, and no outbox row exists

#### Scenario: Tombstones apply before the drain
- **WHEN** this device holds a stale pending update for a record the relay tombstoned
- **THEN** the tombstone step drops the update row before the drain runs, so no 404 is ever pushed for it and the cycle stays idle

#### Scenario: Stale tombstone never kills a recreation (R1)
- **WHEN** the local row is clean (no pending create/update) and newer than the tombstone (`updated_at > deleted_at`)
- **THEN** the row is kept and the tombstone is buried by the cursor advance

#### Scenario: Empty deletions keep the cursor
- **WHEN** the deletions fetch returns no tombstones
- **THEN** the cursor is unchanged and no local state is touched

### Requirement: Push-404 resurrection
When an outbox push fails because the relay lacks the record and no tombstone covers it, the sync client SHALL resurrect from the local record and retry exactly once instead of failing the cycle: entry/category update receiving `not_found` SHALL be re-posted as a create (idempotent; `duplicate_import` clears the row via the existing resolver). Rows with no local record left SHALL clear without further pushes. Any further failure SHALL rethrow the original error loudly; nothing is ever silently dropped.

#### Scenario: Stale update re-posts as create
- **WHEN** the drain pushes an entry or category update and the relay answers `not_found` while the full local row exists
- **THEN** the row is re-posted as a create, the outbox clears, and the cycle completes idle with the local record intact

#### Scenario: Remap-leftover update clears without pushing
- **WHEN** a stale update row references a record id with no local row left (no remap flow exists to orphan it)
- **THEN** the row clears with no further push and no other record is touched

#### Scenario: Failed heal surfaces loudly
- **WHEN** the re-post fails
- **THEN** the cycle fails with the original push error and all rows stay queued for retry

## REMOVED Requirements

### Requirement: Cross-device name collision remapping
**Reason**: No activity/category-name identity owns references; equal texts are independent records.
**Migration**: Delete `activity_exists` remap, newer-owns-the-name, and category-reference translation for activities. Category `category_exists` remap for category records themselves stays.

### Requirement: Delete-wins on pull-merge
**Reason**: Requirement text names buffered activity deletions, which no longer exist; the surviving rule is restated narrowly below.
**Migration**: Replaced by per-record delete-wins for entries and categories only.

## ADDED Requirements

### Requirement: Delete-wins for entries and categories
On pull, the sync client SHALL NOT apply a server entry or category the user deleted locally — a deletion sitting in the durable undo buffer or a committed deletion with a pending outbox DELETE row. Such records SHALL be skipped with a secret-free log; the queued DELETE converges the relay on drain.

#### Scenario: Buffered entry deletion survives a pull
- **WHEN** an entry deletion sits in the undo buffer and a pull returns the relay's copy
- **THEN** the pull skips the record and the buffer row stays restorable

#### Scenario: First-sync with a pending entry delete
- **WHEN** the outbox holds an entry DELETE and the relay still returns that entry
- **THEN** the pull skips the record, the drain pushes the DELETE, and the entry stays deleted locally
