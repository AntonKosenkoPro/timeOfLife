## ADDED Requirements

### Requirement: Push-404 convergence

When an outbox push fails because the relay already deleted the record, the sync client SHALL converge locally instead of failing the cycle: entry create/update receiving `activity_not_found` or `not_found`, and activity/category update receiving `not_found`, SHALL delete the local row (activities cascade; no outbox row), drop pending create/update rows for the affected ids (including the failing row), and continue the drain. DELETE receiving any 404 stays success. Activity/category CREATE receiving 404 SHALL still throw. A `not_found` from the deletions fetch itself (pre-tombstone relay) SHALL skip the tombstone step with a log and continue the cycle.

#### Scenario: Entry push against a deleted activity converges

- **WHEN** the drain pushes an entry create and the relay answers `activity_not_found`
- **THEN** the local entry and its outbox rows are removed, no DELETE is pushed (the relay never had the entry), and the cycle completes idle

#### Scenario: Stale update against a relay-deleted record converges

- **WHEN** the drain pushes an activity, category, or entry update and the relay answers `not_found`
- **THEN** the local record is removed (with cascade) and its outbox rows dropped, and the cycle completes idle

#### Scenario: Pre-tombstone relay does not fail the cycle

- **WHEN** the deletions fetch answers `not_found` (relay predates tombstones)
- **THEN** the tombstone step is skipped with a log; drain and pull run normally
