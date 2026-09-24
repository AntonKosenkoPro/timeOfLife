## ADDED Requirements

### Requirement: Account-change adoption uses fresh record ids

When the sync scope changes to a different signed-in account id (OTP vs SiWA are
separate relay identities), the first sync cycle SHALL adopt preserved local
categories and entries into the new account under newly-minted record ids:
names, texts, icons and notes are preserved, and each adopted entry's ordered
`category_ids` SHALL be rewritten to the fresh category ids before anything is
pushed. Record ids are relay-global (a row id committed under one account
collides with the same id under another), so reusing old ids MUST NOT happen.
The first pull of that cycle SHALL NOT delete adopted locals before the drain
pushes them; relay tombstones still apply in that cycle. Stale outbox update
rows for the superseded old ids SHALL be dropped without pushing (the adoption
create carries the current state); pending old-account delete rows SHALL still
drain (a 404 there is success).

#### Scenario: relogin to a new account pushes locals as new relay rows

- **WHEN** the user signs into account B with clean local categories/entries
  created under account A, and the relay state for B is empty
- **THEN** after the first cycle the relay holds the same names/texts under new
  ids, local joins are intact, the outbox is empty, and no local row was
  deleted to match the empty snapshot

### Requirement: Unresolvable id collisions self-heal instead of wedging

When an outbox create/update push fails with an id collision the relay cannot
attribute to a usable winner — 409 `category_exists` (or entry `duplicate_import`
disambiguated below) with a missing or empty winner id in `details`, or the
backend's documented nil-details unresolvable-collision form — the drain SHALL
NOT fail the cycle on it and SHALL NOT request any route with an empty id.
Instead it SHALL rewrite the stuck row in place to a freshly-minted id
(remapping local joins and pending payloads onto the fresh id, superseding
companion rows for the old id), retry the push once, and adopt the landed row
locally. If the retry fails, the cycle SHALL fail loudly with a clear
diagnostic naming the collision (secret-free), keeping remaining rows queued.
A repeat collision on a fresh id is treated as a new occurrence, not a loop:
fresh ids are relay-unique by construction.

#### Scenario: wedged outbox row converges without data surgery

- **WHEN** a queued category create carries an id committed under another
  account, and the relay answers 409 with no usable winner id
- **THEN** one cycle later the relay holds the category under a fresh id, the
  local row and its entry joins reference the fresh id, the outbox is empty,
  and no `GET` with an empty id was ever issued

### Requirement: Entry duplicate-import collisions are disambiguated

A 409 `duplicate_import` on an entry push is ambiguous: a true same-account
replay (same `source`/`source_ref` already on the relay) versus a cross-user
id collision. The drain SHALL disambiguate with a single `GET` of the pushed
id: relay has it with the same import keys → true duplicate → clear the row
silently (existing behavior); relay answers `not_found` → cross-user id
collision → self-heal with a fresh id exactly like the category path. The
extra `GET` happens only on the rare 409 path, never per row.

#### Scenario: cross-user entry id does not vanish silently

- **WHEN** an adopted entry's old id exists under another account and the push
  answers `duplicate_import`
- **THEN** the entry lands on the new account under a fresh id with its text,
  notes and category set intact, instead of being cleared while missing remotely

## MODIFIED Requirements

### Requirement: Push-404 resurrection covers all 404 wire forms and never fetches empty ids

When an outbox push fails because the relay lacks the record and no tombstone
covers it, the sync client SHALL resurrect from the local record and retry
exactly once instead of failing the cycle: entry/category updates receiving a
404 in EITHER wire form (uniform-envelope `not_found` or bare-status `http_404`,
e.g. an unregistered route or proxy page) SHALL be re-posted as creates
(idempotent; entry `duplicate_import` follows the disambiguation rule above);
a 404 on DELETE (either form) is success and clears the row. Rows with no local
record left SHALL clear without further pushes. Any response naming a winner
id that is missing or empty SHALL NOT trigger a winner fetch: the row is kept
and the cycle fails loudly with a clear collision diagnostic (secret-free),
or self-heals per the unresolvable-collision rule when one applies. Any
further failure SHALL rethrow the original error loudly; nothing is ever
silently dropped.

#### Scenario: bare 404 resurrects exactly like envelope 404

- **WHEN** an entry update push receives a bare-status 404 (unregistered route
  or proxy page) with no tombstone coverage for the id
- **THEN** it is re-posted as a create and the cycle continues; a bare 404 on
  DELETE clears the row as success — identical to the envelope `not_found` form
