## Context

See proposal.md (Why). Current pull (`SyncController.pull`, D4/D5): categories merge by id via `mergeCategory` upsert, activities via `mergeActivity`, entries via `mergeEntry`. All three upserts assume no cross-id name collision; the `lower(name)` unique indexes turn a seed-vs-relay collision into SQLite 19, aborting the cycle before `drainOutbox` runs — permanently, since the same pull repeats every trigger. Reuse targets: `store.category(named:)` / `store.activity(named:)` lookups, atomic `remapCategoryReferences` / `remapActivityReferences`, `AssociationError.invalidCategory` skip, `Logger(sync)`.

## Goals / Non-Goals

**Goals:**
- A name-collided pull always completes; convergence via specified recovery, offline-safe, no new endpoints.

**Non-Goals:**
- Field-level merge (record-level LWW only, per R2); changing server uniqueness semantics; timer-state/undo-buffer id translation (pre-existing exposure, unchanged).

## Decisions

- **D1 — Newer-owns-the-name (uniform, no dirty/clean special case).** Same normalized name + different id → compare `updated_at`; newer wins. Rationale: single rule for seeds and edits; dirty-local end state equals the eventual push-409 outcome (server identity), so pull-side remap only shortens the path. Alternative (always adopt server) discarded: clobbers newer local edits. Alternative (skip-always) discarded: leaves the reported crash in place for the common seed case via activity joins.
- **D2 — Translate, don't skip, activity category refs.** Server category ids map to local ids by id, else by normalized name from the in-memory snapshot; unresolvable → `invalidCategory` skip (existing contract). Rationale: FK-enforced joins make skipping the category insufficient — the activity merge is the next crash. Snapshot completeness guarantees resolvability; the throw is a backstop.
- **D3 — Skip dangling entries with a log.** Rationale: converts an FK crash into divergence-with-retry; a single bad row can never kill sync again.
- **D4 — Cursor semantics unchanged** (max over received). Skipped rows may stay invisible until the name frees; acceptable rarity vs. cursor complexity. Logged for future review.
- **D5 — Liberal entry decode for provenance.** Absent/null `source` defaults to "manual" (mirrors the relay's own back-compat for pre-provenance rows) instead of failing the pull. Everything else stays strict so genuine contract breaks stay loud.

## Risks / Trade-offs

- Dual-id same-name states can persist while local is newer (server branch invisible on this device until the name frees or server wins). Logged per occurrence.
- `remapActivityReferences` during pull rewrites pending entry payloads mid-cycle; the drain that follows pushes corrected references — ordering (pull-then-drain on first sync) already guarantees this.
