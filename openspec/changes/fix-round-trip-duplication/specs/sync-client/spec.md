## MODIFIED Requirements

### Requirement: Pull merge recognizes superseded id generations

When a relay entry or category arrives with an id the local store does not
hold, the sync client SHALL first resolve that id through the adoption map
(following superseded-generation chains transitively): if the chain ends at a
live local row, the server version merges onto that row under last-write-wins
on `updated_at` (category joins resolved by the existing rules) instead of
being inserted as a new row. If the chain ends at a locally-deleted id, the
record stays skipped (delete-wins). If the id resolves to nothing, the
existing insert-as-new behavior applies unchanged. Resolution is by exact id
chains only — never by content similarity.

#### Scenario: round trip does not resurrect old generations as new rows

- **WHEN** the device switches account A→B→A→B with drains in between, and
  each account's relay holds earlier generations of the same logical entries
- **THEN** after every cycle each logical entry exists exactly once locally
  and each relay holds exactly one generation — pulls merge foreign
  generations onto the live rows and the outbox stays empty

#### Scenario: genuinely new relay rows still insert

- **WHEN** a relay row arrives with an id that is neither held locally nor
  present (transitively) in the adoption map, e.g. created on another device
- **THEN** it is inserted as a new local row exactly as before

### Requirement: Pull converges superseded generations by business identity

Exact chains cannot recognize pre-fix generations (rewrites before this change
were never recorded). When a locally-unknown relay entry has no usable chain,
the sync client SHALL fall back to a byte-identical live row (same text,
notes, timing, ordered categories, provenance — never similarity): an
unpushed rewrite-minted live row collapses onto the relay id (its redundant
create/update rows are dropped, nothing is enqueued, so no new generation is
pushed); a clean rewrite-minted live row retires the superseded relay copy
with a tombstoned delete; a live row with no rewrite history is never folded
— the server row inserts as new (independent records stay independent, even
byte-identical). Divergent generations are never auto-merged. The same
collapse applies to categories through the same-name rival path (no relay
retirement for categories: the name-unique 409 already guards the relay).

#### Scenario: rarely-visited account converges without new pushes

- **WHEN** the device returns to an account whose relay still holds
  pre-fix generations byte-identical to the adopted live rows
- **THEN** one cycle later each logical entry exists exactly once locally and
  on the relay: adopted rows collapse onto the relay ids, surplus relay
  generations are tombstoned, the outbox is empty, and no content-divergent
  row was touched
