## MODIFIED Requirements

### Requirement: Idempotent outbox drain
The sync client SHALL drain the outbox by issuing one HTTP request per outbox row, in created_at order within a resource. Because POST is idempotent on `id` and PATCH carries `updated_at` (LWW), replaying an outbox row is safe. Entries carry `activity_text`, ordered `category_ids`, and `notes`; a pulled entry referencing a category id absent from the relay snapshot SHALL resolve by dropping the unknown id and keeping the remainder (logged, secret-free), never failing the cycle. A pulled entry referencing a category id present in the relay snapshot but missing locally SHALL NOT be stripped: when a local category with the same name exists the join SHALL be remapped to that local id (local-only rewrite, never enqueued), otherwise the snapshot category row SHALL be merged locally and the id kept.

#### Scenario: Replay after relaunch
- **WHEN** the app was killed mid-drain and relaunched, leaving some outbox rows already pushed and some not
- **THEN** re-pushing the already-pushed rows returns 200 (idempotent) or 409 (already newer) — both treated as success — and the outbox clears cleanly

#### Scenario: Entry with unknown category is pruned
- **WHEN** a pulled entry references a category id absent from the relay snapshot and with no local row
- **THEN** the unknown id is dropped, the entry merges with the remainder, and the cycle completes

#### Scenario: Entry with relay-known but locally-missing category keeps its category
- **WHEN** a pulled entry references a category id present in the relay snapshot but with no local row
- **THEN** the entry keeps a category: the join is remapped to the same-name local category when one exists, otherwise the snapshot category row is merged locally — the entry never silently loses the category

#### Scenario: Entry without provenance defaults to manual
- **WHEN** a pulled entry omits `source` (relays predating entry provenance)
- **THEN** the entry decodes with `source` = "manual" instead of failing the pull

### Requirement: Dependency-ordered outbox drain
The sync client SHALL drain `category` outbox rows before `entry` rows, preserving `created_at, id` order within each resource. Because `POST /entries` rejects unknown `category_ids` with 422, pushing categories first ensures referenced categories exist on the relay before entries that carry them. Additionally, before pushing each entry create/update, the drain SHALL ensure every referenced category id exists on the relay: ids missing from the relay snapshot but present locally (and not pending deletion) SHALL be created on the relay first via idempotent create (a `category_exists` 409 remaps local references to the winning id and the entry push uses it); only ids missing locally or pending deletion may reach the push uncreated.

#### Scenario: Entry queued before its category still pushes category first
- **WHEN** the outbox holds an entry create whose `created_at` precedes its category create
- **THEN** the drain pushes the category create before the entry create and the cycle completes

#### Scenario: Entry referencing a relay-unknown category pushes it first
- **WHEN** the drain pushes an entry create/update whose category id exists locally but is absent from the relay
- **THEN** the category is created on the relay first and the entry push carries the full category set — no 422, no prune, and the local entry keeps its categories

#### Scenario: Entry referencing a locally-deleted category still prunes
- **WHEN** the drain pushes an entry whose category id has a pending delete (or no local row at all)
- **THEN** that id is not created on the relay and the existing validation_error prune-and-retry path applies

### Requirement: Push validation_error recovery for unknown categories
On an entry create/update push receiving `validation_error` with `category_ids` details, the sync client SHALL fetch the relay categories, drop unknown ids from the queued payload keeping the remainder (secret-free log), rewrite the outbox payload, retry the push exactly once, and clear the row on success. If no id is pruned or the retry fails, the cycle SHALL fail loudly with the push error and keep remaining rows queued. The following pull converges the local copy via LWW. This path is a last resort only: the dependency-ordered ensure step above SHALL make it unreachable whenever the missing categories exist locally.

#### Scenario: Entry with unknown category is pruned on push
- **WHEN** the drain pushes an entry create referencing a category id absent from the relay
- **THEN** the payload is pruned to the known remainder, the push retries and succeeds, the outbox clears, and the cycle completes idle

#### Scenario: Unprunable validation still fails
- **WHEN** the entry push fails with `validation_error` but every id is already known (or the retry fails)
- **THEN** the cycle fails with the push error and rows stay queued for retry

## ADDED Requirements

### Requirement: Pull heals category-set forks
When a pulled server entry is NOT newer than the local entry (tie or older, so LWW keeps local) but the local category set is a strict superset of the server set via existing clean local rows (none pending deletion), the sync client SHALL enqueue an entry update with a bumped `updated_at` (strictly newer even under second-precision truncation) carrying the full local set, so the complete categories reconverge on the relay on the next drain instead of diverging silently forever.

#### Scenario: Re-assigned categories reconverge after a silent prune
- **WHEN** a previous relay-side prune stored fewer categories than the local entry holds (equal timestamps, clean local rows)
- **THEN** the next pull enqueues a healing update and the following drain pushes the full category set, which other devices then receive

#### Scenario: Healing skips delete-wins ids
- **WHEN** the extra local ids are pending deletion
- **THEN** no healing update is enqueued for them and the queued delete still converges the relay
