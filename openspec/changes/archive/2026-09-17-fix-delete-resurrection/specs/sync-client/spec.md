## ADDED Requirements

### Requirement: Delete-wins on pull-merge

On pull, the sync client SHALL NOT apply a server record the user deleted locally — a deletion sitting in the durable undo buffer (no outbox row yet) or a committed deletion with a pending outbox DELETE row. Such records SHALL be skipped with a secret-free log, and the cycle SHALL continue; the queued DELETE (once committed and drained) converges the relay. Undoing the deletion or successfully draining the DELETE lifts the exclusion, after which newer server versions merge under the normal last-write-wins rule.

#### Scenario: First-sync with a pending activity delete

- **WHEN** the outbox holds an activity DELETE and the relay still returns that activity (pull-first runs before the drain pushes the DELETE)
- **THEN** the pull skips the record, the drain pushes the DELETE, the outbox clears, and the activity stays deleted locally with an idle cycle

#### Scenario: Buffered activity deletion survives a pull

- **WHEN** an activity deletion sits in the undo buffer (no outbox row) and a pull returns the relay's copy
- **THEN** the pull skips the record, the local row stays gone, the buffer row stays restorable, and the cycle completes

#### Scenario: Buffered category deletion survives the full snapshot

- **WHEN** a category deletion sits in the undo buffer and the authoritative category snapshot still contains it
- **THEN** the pull skips the record (snapshot reconciliation never re-creates it via merge) and the buffer row stays restorable

#### Scenario: Buffered entry deletion survives a pull

- **WHEN** an entry deletion sits in the undo buffer and a pull returns the relay's copy
- **THEN** the pull skips the record and the buffer row stays restorable

#### Scenario: Push-conflict adoption respects a superseding delete

- **WHEN** an outbox update (or create) push receives 409 `conflict` but a DELETE for the same record is queued behind it in the same drain
- **THEN** the client skips adopting the server version (the local deletion stands), clears the conflicting row, and the queued DELETE converges the relay
