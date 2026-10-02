## MODIFIED Requirements

### Requirement: Last-write-wins conflict resolution
On pull, the sync client SHALL apply a server record to the local database only if `server.updated_at > local.updated_at` for the same record id; otherwise the local version is kept. On push, a 409 `conflict` response SHALL cause the client to adopt the server's version (keep-latest) and clear the outbox row. There SHALL be no cross-record name-identity remapping: equal or similar texts with different ids are independent records. The relay SHALL compare `updated_at` at millisecond precision for entry and category updates, so two writes within the same second are ordered correctly and only a truly stale `updated_at` conflicts. A stale entry or category update SHALL return 409 `conflict` with the current server version promptly and SHALL never hang or block indefinitely.

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
- **WHEN** a pulled record's text matches a different local id (name collision under exact-text identity)
- **THEN** no identity remap occurs: equal texts are independent records, the pull applies per-id LWW only, and the cycle continues

#### Scenario: Pull keeps newer local identity on name collision
- **WHEN** a pulled record's text matches a different local id and either side is newer
- **THEN** both records are kept as independent entries or categories; nothing merges, nothing is skipped for collision, and convergence needs no name-freedom step

#### Scenario: Same-second stale entry update conflicts instead of hanging
- **WHEN** a client PATCHes an entry with an `updated_at` equal to the relay's current `updated_at` (same second, same millisecond)
- **THEN** the relay returns 409 `conflict` with the current server version promptly and the request completes (never hangs)

#### Scenario: Same-second stale category update conflicts instead of hanging
- **WHEN** a client PATCHes a category with an `updated_at` equal to the relay's current `updated_at` (same second, same millisecond)
- **THEN** the relay returns 409 `conflict` with the current server version promptly and the request completes (never hangs)
