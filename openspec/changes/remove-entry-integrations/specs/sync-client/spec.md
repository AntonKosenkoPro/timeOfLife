## REMOVED Requirements

### Requirement: Idempotent outbox drain
**Reason**: Source-defaulting is no longer a supported decoding behavior and its old scenario is deliberately retired.
**Migration**: Preserve ID replay and category resolution under “Idempotent source-free outbox drain”; source-free decoding replaces manual-source synthesis.

## ADDED Requirements

### Requirement: Source-free entry relay contract
The current entry request/response schemas and sync payloads SHALL omit `source` and `source_ref`. The relay SHALL ignore obsolete producer/reference keys on otherwise valid requests without applying provider validation or external-reference deduplication, and SHALL NOT emit `duplicate_import`. Existing entry content, IDs, categories, timestamps, and account ownership SHALL be preserved regardless of any physically retained provenance on older relay rows. A later, separately gated database contract release SHALL own destructive removal of retired columns/indexes; this retirement SHALL NOT require destructive deployed schema changes or a provenance backfill.

#### Scenario: Ordinary source-free round trip
- **WHEN** the client creates, updates, or pulls an entry under the current contract
- **THEN** its supported values round-trip with no provenance fields in payloads or responses

#### Scenario: Older create body is accepted without import semantics
- **WHEN** an otherwise valid create body contains obsolete `source` and `source_ref` keys
- **THEN** the relay ignores those keys, creates or replays by entry ID, and does not return a source-validation or `duplicate_import` error

#### Scenario: Same external reference does not merge distinct IDs
- **WHEN** two valid creates use different entry IDs but the same obsolete external-reference keys
- **THEN** the relay keeps two independent entries, with no import deduplication

#### Scenario: Older stored provenance is not a public field
- **WHEN** the relay returns an existing row that physically retains non-manual provenance
- **THEN** its ID/content/categories/timestamps are unchanged and no response, including a conflict response, exposes the retired fields

#### Scenario: Previous backend image can still run
- **WHEN** the runtime-cleanup backend is rolled back to the previously deployed image
- **THEN** the historical columns, defaults, and index it expects remain present, with no destructive migration or provenance rewrite required by this change

### Requirement: Idempotent source-free outbox drain
The sync client SHALL drain the outbox by issuing one HTTP request per outbox row, in created_at order within a resource. Because POST is idempotent on `id` and PATCH carries `updated_at` (LWW), replaying an outbox row is safe. Entries carry `activity_text`, ordered `category_ids`, and `notes` without producer provenance; a pulled entry referencing a category id absent from the relay snapshot SHALL resolve by dropping the unknown id and keeping the remainder (logged, secret-free), never failing the cycle. A pulled entry referencing a category id present in the relay snapshot but missing locally SHALL NOT be stripped: when a local category with the same name exists the join SHALL be remapped to that local id (local-only rewrite, never enqueued), otherwise the snapshot category row SHALL be merged locally and the id kept.

#### Scenario: Replay after relaunch
- **WHEN** the app was killed mid-drain and relaunched, leaving some outbox rows already pushed and some not
- **THEN** re-pushing the already-pushed rows returns 200 (idempotent) or 409 (already newer) — both treated as success — and the outbox clears cleanly

#### Scenario: Entry with unknown category is pruned
- **WHEN** a pulled entry references a category id absent from the relay snapshot and with no local row
- **THEN** the unknown id is dropped, the entry merges with the remainder, and the cycle completes

#### Scenario: Entry with relay-known but locally-missing category keeps its category
- **WHEN** a pulled entry references a category id present in the relay snapshot but with no local row
- **THEN** the entry keeps a category: the join is remapped to the same-name local category when one exists, otherwise the snapshot category row is merged locally — the entry never silently loses the category

#### Scenario: Entry has no provenance to default
- **WHEN** the relay omits retired producer fields
- **THEN** the client decodes the supported entry values without synthesizing a source or failing the pull

## MODIFIED Requirements

### Requirement: Push-404 resurrection
When an outbox push fails because the relay lacks the record and no tombstone covers it, the sync client SHALL resurrect from the local record and retry exactly once instead of failing the cycle: entry/category update receiving `not_found` SHALL be re-posted as a create (idempotent on record ID, without a `duplicate_import` recovery branch). Rows with no local record left SHALL clear without further pushes. Any further failure SHALL rethrow the original error loudly; nothing is ever silently dropped.

#### Scenario: Stale update re-posts as create
- **WHEN** the drain pushes an entry or category update and the relay answers `not_found` while the full local row exists
- **THEN** the row is re-posted as a create, the outbox clears, and the cycle completes idle with the local record intact

#### Scenario: Remap-leftover update clears without pushing
- **WHEN** a stale update row references a record id with no local row left (no remap flow exists to orphan it)
- **THEN** the row clears with no further push and no other record is touched

#### Scenario: Failed heal surfaces loudly
- **WHEN** the re-post fails
- **THEN** the cycle fails with the original push error and all rows stay queued for retry
