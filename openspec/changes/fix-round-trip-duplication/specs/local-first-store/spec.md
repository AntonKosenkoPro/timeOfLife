## ADDED Requirements

### Requirement: Adoption records superseded-generation mappings

Every adoption or collision-heal rewrite that replaces record id OLD with a
fresh id NEW SHALL persist the mapping OLD → NEW (per resource) in the same
chokepoint transaction that performs the rewrite, so later pulls can recognize
OLD as a superseded generation of the live row. Mappings survive restarts and
account switches; a mapping whose NEW id is itself later superseded resolves
transitively. No content comparison is ever used for this recognition.

#### Scenario: renamed rows stay recognizable across switches

- **WHEN** adoption rekeys rows O→F on switching to account B, and a later
  pull from any account returns O
- **THEN** O resolves to the live row F (or its transitive successor) instead
  of inserting a duplicate

### Requirement: Pull-side collapse and rewrite-history guard

The store SHALL provide pull-side collapse for entries and categories:
a live row that was minted by a rewrite, still carries its never-pushed
create, and is byte-identical to the pulled server version adopts the server
id with its redundant queued rows dropped and nothing enqueued. The store
SHALL answer whether an id has rewrite history (starts a chain or is pointed
at); the sync client retires or collapses only history-bearing rows, so
user-created and relay-adopted rows are never folded by content.

#### Scenario: adopted rows collapse instead of re-pushing

- **WHEN** a pull returns the relay generation an unpushed adopted row was
  cloned from, with identical content
- **THEN** the live row takes the relay id, its create row is dropped, and
  the drain pushes nothing for it — while a user-created identical row keeps
  its id and its queued push

### Requirement: One-time convergence of duplicate generations

The store SHALL provide a one-time convergence that folds same-account entry
groups with byte-identical business payloads (activity text, notes, started
and ended times, duration, ordered category set, source and source reference)
down to a single survivor — the generation whose category references are
intact — deleting the other rows locally and queueing hard deletes for their
relay copies (which propagate as tombstones through the normal drain). Each
loser also records a loser→survivor map edge in the same transaction, so the
same cycle's pull (which runs before the drain) resolves the still-listed
losers onto the survivor instead of resurrecting them. Groups
whose payloads diverge in any business field SHALL be kept whole and reported,
never auto-merged. Rows with pending outbox operations, rows in the undo
buffer, and locally-deleted rows SHALL be excluded from folding. Categories
need no convergence (same-name remap already collapses generations). The run
is guarded by a per-account once-flag, and the sync layer invokes it before
the account-switch adoption on every signed-in activation.

#### Scenario: tripled entries converge without losing user edits

- **WHEN** an account holds three byte-identical generations of an entry plus
  a fourth copy whose notes the user edited
- **THEN** after convergence one identical generation survives (locally and
  on the relay, via tombstoned deletes), the edited copy survives untouched,
  and no outbox or buffered row was disturbed
