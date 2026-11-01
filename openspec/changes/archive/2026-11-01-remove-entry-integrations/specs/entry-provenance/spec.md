## REMOVED Requirements

### Requirement: Entry source and source_ref fields
**Reason**: Entry-producing integrations are abandoned; provenance no longer changes entry behavior or editability.
**Migration**: Entries use the source-free contract in `local-first-store` and `sync-client`. Historical relay columns remain temporarily for rollback, not as public fields.

### Requirement: Duplicate import prevention
**Reason**: There are no supported import producers or external record identities.
**Migration**: Keep ordinary entry-ID idempotency and LWW. Ignore obsolete source/reference request keys; retire `duplicate_import`. Deployed columns/index are contracted separately after reader retirement.

### Requirement: Delete does not resurrect on re-import
**Reason**: No integration can re-import an entry under the supported product contract.
**Migration**: Preserve existing sync tombstones, delete-wins, and buffered-deletion rules for ordinary entries; do not remove those mechanisms with import deduplication.

### Requirement: User-visible source labels
**Reason**: All saved entries have the same ownership/editing contract; source labels have no supported producer.
**Migration**: Remove source labels from History, entry forms, and accessibility output, retaining entry identity, categories, notes indication, and timing.
