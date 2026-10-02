## MODIFIED Requirements

### Requirement: Delta pull via modified_since
The sync client SHALL pull only records modified since the last successful pull, using the `?modified_since=<timestamp>` query parameter on `GET /entries`, and SHALL advance the entries sync cursor to the max `updated_at` received. `GET /categories` is full-pull by design (catalog small: seeded plus a handful of user rows, so a snapshot merge with newer-owns-the-name is cheap; entries are unbounded and need the cursor): the client SHALL fetch the full category list on every pull and SHALL NOT send a categories cursor.

#### Scenario: Incremental pull
- **WHEN** the sync client runs after a previous successful pull recorded a cursor at time T
- **THEN** it requests `GET /entries?modified_since=T` and receives only records with `updated_at > T`; it applies them locally with LWW merge and advances the cursor

#### Scenario: No changes
- **WHEN** the delta pull returns no records
- **THEN** the cursor is unchanged and no local updates are applied

#### Scenario: Categories always full-pull
- **WHEN** the sync client runs a pull (first sync or delta cycle)
- **THEN** it fetches `GET /categories` with no `modified_since` parameter and merges the full snapshot (newer-owns-the-name), regardless of the entries cursor
