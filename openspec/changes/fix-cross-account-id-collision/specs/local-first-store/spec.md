## ADDED Requirements

### Requirement: Sync state is scoped per account with fresh-id adoption

The local store SHALL persist the account id the sync cursors belong to
alongside the per-resource cursors. When the signed-in account id differs from
the stored one, the store SHALL, in chokepoint transactions: reset all
per-resource cursors (so the next pull is a full pull against the new account),
adopt every clean local category under a freshly-minted id (name and icon
preserved) and every clean local entry under a freshly-minted id (text, notes
and ordered categories preserved, category references rewritten to the fresh
category ids), each with its own create outbox row. Records that already carry
any outbox row keep it untouched at this step (the drain's self-heal converges
them). Superseded update outbox rows for adopted-away old ids SHALL be dropped
(the adoption create carries current state); pending delete rows SHALL be
preserved so deletions still propagate. The adoption runs exactly once per
account transition; re-sign-in to the same account id is a no-op.

#### Scenario: switching accounts never reuses relay-global ids

- **WHEN** the stored sync account is A (or none) and sign-in reports B, with
  clean locals present
- **THEN** cursors are cleared, every adopted row carries an id minted for B,
  entry payloads reference the fresh category ids, stale updates for old ids
  are gone, deletes are still queued, and the stored sync account reads B

#### Scenario: same-account sign-in changes nothing

- **WHEN** the stored sync account already equals the signed-in id
- **THEN** no cursor, id, or outbox rewrite occurs (existing same-account
  reconciliation and tombstone behavior is untouched)
