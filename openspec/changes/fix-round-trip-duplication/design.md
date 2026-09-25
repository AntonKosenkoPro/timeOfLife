## Context

See proposal.md — Why. Current state (proven by prod relay forensics, not
hypothesized): record ids are relay-global while pull merges purely by id
(`applyServer(_:)` inserts any locally-unknown, not-locally-deleted id as new)
and adoption rekeys every clean row on every account switch. The composition
is a duplication engine: each A→B→A round trip with drains inserts the other
account's generation as new rows, then rekeys and pushes them as another
generation. Scripted round trips reproduce 1 → 2 → 3 rows per logical entry
with green cycles throughout (`RoundTripReproTests`, failing as designed).

## Goals / Non-Goals

- Goals: make round trips idempotent (pull recognizes superseded generations);
  converge the existing ×3 relay/local copies without losing user edits; no
  backend change; no new failure modes (every cycle still converges or fails
  loudly under existing rules).
- Non-Goals: content-similarity/fuzzy matching anywhere; auto-merging
  divergent copies; changing LWW, tombstone, delete-wins, or remap semantics.

## Decisions

- **Adoption map (exact id chains, local-only).** New `adoption_map(old_id,
  new_id, resource)` table written in the same chokepoint transaction as every
  adoption/heal rekey. Pull resolves unknown ids transitively
  (OLD→NEW→NEWER…) to a live row and merges (LWW) instead of inserting.
  Rejected alternative: content-identity dedupe on pull — any heuristic
  (text+started_at) risks silently merging two legitimately identical manual
  entries (data loss); exact chains cannot false-positive. Rejected
  alternative: backend generation tracking — unnecessary (client-side chains
  suffice) and would need a deploy + migration.
- **Map pruning by liveness, not by time.** Rows whose NEW id is locally
  deleted are dropped with the row (delete-wins already skips them); surviving
  chains are tiny (one row per rewrite) and need no GC at personal scale.
- **One-time convergence, byte-identical only.** Group same-account entries by
  (activity_text, notes, started_at, ended_at, duration_seconds, ordered
  category set, source, source_ref); groups of size > 1 with a single distinct
  payload fold to the survivor with intact category refs, others hard-deleted
  (tombstones propagate via the normal drain so other devices converge).
  Divergent groups are kept whole and logged. Rows with outbox rows, buffered
  rows, and locally-deleted rows are excluded. Runs once per account (flag in
  local metadata), before the switch adoption on every signed-in activation —
  convergence must precede adoption, or rekeyed losers gain create rows and
  become ineligible forever. Each loser records a loser→survivor edge in the
  same transaction (the same cycle's pull runs before the drain pushes the
  deletes; without the edge it would resurrect every loser).
- **Collapse of unpushed rewrite products (no map required).** When a pull
  returns the relay generation an unpushed adopted/healed row was cloned from
  (byte-identical business content), the live row adopts the relay id and its
  redundant create is dropped — no new generation is ever pushed for content
  the relay already holds. Pre-fix generations have no map edges, so the
  lookup falls back from exact chains to a byte-identical live row. Guarded by
  rewrite history: the live row must be rewrite-minted (an incoming map edge)
  and still carry its create. A user-created row with no rewrite history never
  collapses — pinned by `nameCollisionKeepsBothRecords` and the
  newer-local-rival tests; the coincidence it concedes (same-second identical
  manual double-log across devices) is invisible when it fires (content is
  identical) and vanishingly rare.
- **Retirement of superseded relay copies (entries only).** When the live row
  is clean, rewrite-bearing, and already carries the pulled generation's exact
  content, the drain-worthy move is deleting the relay copy, not pushing
  another: the pull enqueues the tombstoned delete. This is what converges
  rarely-visited accounts (OTP 52→26) instead of accumulating generations.
  Never fires for newer server content (adopted via LWW merge instead —
  deleting it could strand the content) or history-less live rows. Categories
  are excluded by design: the relay's name-unique 409 already dedupes them
  server-side (populated-winner remap converges the client).
- **Cleanup order: prevention first in code, convergence guarded behind it.**
  The convergence runs only in builds containing the map-aware pull; otherwise
  a post-cleanup round trip would regrow generations.

## Risks / Trade-offs

- [Risk] Map misses a pre-fix generation (no map row exists for it) → Mitigation:
  the one-time convergence handles exactly those; the map covers everything
  rewritten after this ships.
- [Risk] Convergence survivor choice surprises the user (which copy's
  `updated_at` wins downstream) → Mitigation: survivors are byte-identical
  except identity columns, so the choice is unobservable; divergent copies are
  never folded.
- [Risk] Entry categories of folded generations reference rekeyed-away ids →
  Mitigation: survivor = generation with intact refs; folded rows' joins die
  with them (FK cascade); relay copies die by hard delete.
- [Risk] Another device holding old generations re-pushes them →
  Mitigation: relay deletes leave tombstones; a device pulling a tombstoned id
  drops it, and map-aware pull merges anything that arrives under a mapped id.
- [Risk] Same-second identical double-log across devices collapses two
  intentional rows into one → Mitigation: accepted (content is byte-identical
  so the difference is invisible; personal-scale likelihood negligible), and
  only rewrite-minted unpushed rows can collapse — clean user rows never do.
- [Risk] Multi-device newer-content races strand generations on the relay
  (newer server content merges locally without retiring either copy; divergent
  cross-account edits accumulate per-account versions) → Mitigation: accepted
  as known limitations — local state stays correct and converged; relay copies
  are identical-or-divergent-kept-whole by explicit non-goals, never corrupt.
  Flagged for a future change if multi-device editing becomes common.

## Migration Plan

No schema migration beyond the additive `adoption_map` table (fresh installs
create it; existing installs create it on launch — pre-release, no legacy
branches). No relay deploy. Roll back by reverting; map rows are inert without
the resolving pull, queued tombstones drain under previous rules.

## Open Questions

None — mechanism, generations, and counts were established from prod data
before writing this; the scripted repro pins the contract.
