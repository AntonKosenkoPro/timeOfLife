## ADDED Requirements

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
