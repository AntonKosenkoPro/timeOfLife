## ADDED Requirements

### Requirement: Push-404 resurrection

When an outbox push fails because the relay lacks the record and no tombstone covers it, the sync client SHALL resurrect from the local record and retry exactly once instead of failing the cycle: entry create/update receiving `activity_not_found` or `not_found` SHALL be re-posted as a create (idempotent; `duplicate_import` clears the row via the existing resolver); a missing parent SHALL be re-posted first (409 `activity_exists` on the heal reuses the remap flow, then the entry retries with its rewritten payload); activity/category update receiving `not_found` SHALL be re-posted as a create (queued updates PATCH normally afterward; 409 reuses the existing conflict resolver). Rows with no local record left (remap leftovers) SHALL clear without further pushes. Any further failure SHALL rethrow the original error loudly; nothing is ever silently dropped.

#### Scenario: Entry push resurrects a forgotten parent

- **WHEN** the drain pushes an entry create and the relay answers `activity_not_found` while the full parent row exists locally
- **THEN** the parent is re-posted, the entry push retried, both rows clear, and the cycle completes idle with entry and activity intact

#### Scenario: Stale update re-posts as create

- **WHEN** the drain pushes an entry, activity, or category update and the relay answers `not_found` while the full local row exists
- **THEN** the row is re-posted as a create, the outbox clears, and the cycle completes idle with the local record intact

#### Scenario: Remap-leftover update clears without pushing

- **WHEN** a name-collision remap already moved an activity to its winner and the stale update row for the losing id answers `not_found`
- **THEN** the row clears with no further push and the adopted winner is untouched

#### Scenario: Failed heal surfaces loudly

- **WHEN** the parent re-post fails with anything but a remappable collision
- **THEN** the cycle fails with the original push error and all rows stay queued for retry

## REMOVED Requirements

### Requirement: Push-404 convergence
