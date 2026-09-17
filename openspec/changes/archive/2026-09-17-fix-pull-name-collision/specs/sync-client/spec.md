## MODIFIED Requirements

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
When the client pushes a create and receives 409 `activity_exists` or `category_exists`, it SHALL re-map local references (entries, tags) to the winning record's id returned in `details`, clear the outbox row, and proceed without surfacing an error to the user, per the existing design. When merging a server activity, the client SHALL translate its category references to local ids (by id, else by normalized name from the pulled snapshot) so joins never reference a skipped server category; an unresolvable reference SHALL skip the activity (transient, retried next pull), never fail the cycle.

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
