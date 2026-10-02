## MODIFIED Requirements

### Requirement: Dependency-ordered outbox drain
The sync client SHALL drain `category` outbox rows before `entry` rows, preserving `created_at, rowid` order within each resource. Because `POST /entries` rejects unknown `category_ids` with 422, pushing categories first ensures referenced categories exist on the relay before entries that carry them. Additionally, before pushing each entry create/update, the drain SHALL ensure every referenced category id exists on the relay: ids missing from the relay snapshot but present locally (and not pending deletion) SHALL be created on the relay first via idempotent create (a `category_exists` 409 remaps local references to the winning id and the entry push uses it); only ids missing locally or pending deletion may reach the push uncreated.

#### Scenario: Entry queued before its category still pushes category first
- **WHEN** the outbox holds an entry create whose `created_at` precedes its category create
- **THEN** the drain pushes the category create before the entry create and the cycle completes

#### Scenario: Entry referencing a relay-unknown category pushes it first
- **WHEN** the drain pushes an entry create/update whose category id exists locally but is absent from the relay
- **THEN** the category is created on the relay first and the entry push carries the full category set — no 422, no prune, and the local entry keeps its categories

#### Scenario: Entry referencing a locally-deleted category still prunes
- **WHEN** the drain pushes an entry whose category id has a pending delete (or no local row at all)
- **THEN** that id is not created on the relay and the existing validation_error prune-and-retry path applies

#### Scenario: Same-tick rows drain in insertion order
- **WHEN** two outbox rows in the same resource share an identical `created_at` tick
- **THEN** the drain pushes the earlier-inserted row first (SQLite `rowid` order), so the sequence is deterministic across runs
