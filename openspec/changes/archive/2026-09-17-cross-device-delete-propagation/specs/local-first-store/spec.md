## ADDED Requirements

### Requirement: Tombstone application

The local store SHALL apply a relay tombstone `(resource, record_id, deleted_at)` by removing the local row — entries and join rows cascade for activities — in a single write transaction with no outbox row, and by dropping pending create/update outbox rows for every affected id (the activity id plus its entry ids; the single id otherwise). Pending DELETE rows SHALL be left untouched. A clean local row newer than the tombstone SHALL be kept (stale tombstone after a recreation).

#### Scenario: Activity tombstone cascades without outbox

- **WHEN** an activity tombstone is applied and the activity has entries and category joins
- **THEN** the entries, joins, and row are removed in one transaction, no outbox row is created, and pending create/update rows for the activity and its entries are gone

#### Scenario: Pending deletes survive tombstone application

- **WHEN** an outbox DELETE row exists for the tombstoned id
- **THEN** the DELETE row remains queued (it converges via 404-as-success on drain)
