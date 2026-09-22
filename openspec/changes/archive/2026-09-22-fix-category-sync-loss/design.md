## Context

See proposal.md — Why. Current state: steady `syncNow` runs tombstones → drain (categories-before-entries by outbox order) → pull; first-sync has no trailing pull. `POST /entries` strictly 422s on relay-unknown `category_ids` (atomic, nothing stored); relay `PATCH` silently prunes unknown ids with 200 while storing the client `updated_at` verbatim (second-precision on SQLite); `POST` is idempotent on id (replay is a no-op) and server-stamps `updated_at` on create. Pull merges entries with LWW strict `>` and double-prunes unknown ids (against the relay snapshot, then against the local table). Heal (`healUnknownCategoryIDs`) prunes the outbox payload, retries once, and relies on the trailing pull to converge local — which destroys just-saved local categories whenever the 422 trigger fires. Constraints: LocalStore stays the single mutation chokepoint (D1); tombstone/delete-wins semantics (R1) must survive; no backend behavior change (doc-only corrections).

## Goals / Non-Goals

**Goals:**
- Entry pushes carry the full category set whenever the categories exist locally (no 422, no heal, no local loss).
- Pulls never strip relay-known category ids; existing silent forks reconverge instead of diverging forever.

**Non-Goals:**
- No snapshot-reconciliation change (tombstone/spec tension stays a documented follow-up).
- No fix for the same-second user-edit 409 papercut (pre-existing, separate).
- No relay behavior change; no new endpoints, strings, or visuals.

## Decisions

- **Eager ensure-before-push per entry row (not lazy 422-retry-with-full-set).** Before pushing each entry create/update, fetch the relay category snapshot once per drain (cached) and POST every referenced id that is missing on the relay but present locally and not pending deletion (idempotent; 409 remaps to the winner and the entry push re-reads its payload). Lazy retry-after-422 cannot fix symptom 3 because relay PATCH prunes silently with 200 — there is no error to react to. The ensure step makes heal genuinely last-resort (dangling ids, delete-wins ids only).
- **Adopt-or-remap on entry merge (shared helper for pull + conflict adoption).** For ids in the relay snapshot but missing locally: remap the join to a same-name local rival when one exists, else merge the snapshot row. The rival remap is strictly local-only and never enqueues an outbox row — otherwise two devices with same-name/different-id seeds would flip the relay entry between ids on every edit (ping-pong). Truly snapshot-unknown ids keep the existing drop behavior; locally-deleted ids keep delete-wins (skip, the queued DELETE converges the relay).
- **Join-set healing on tie/older pulls (superset only).** When server `updatedAt <= local.updatedAt` and local categoryIDs strictly superset the server set via existing clean rows, enqueue an entry update with `updatedAt = max(now, server+1s, local+1s)` (the +1s survives SQLite second-truncation so the relay PATCH LWW guard passes). Whole-row LWW is otherwise untouched: server-newer still adopts; incomparable tie sets keep local (pre-existing limitation, out of scope). Healing drains next cycle (one-cycle lag).
- **Backend edits are doc-only.** `store.go` comment and `openapi.yaml` `EntryUpdate.category_ids` text currently state false behavior; correct the text to the pruned-on-merge reality pinned by handler/store tests. No code, no contract-gate risk beyond the corrected sentence.

## Risks / Trade-offs

- [Risk] Tombstone race: ensure recreates a category deleted on another device whose tombstone hasn't arrived yet → Mitigation: one-cycle bounded flicker; the next cycle's tombstone deletes it locally again and joins cascade (delete still wins).
- [Risk] Extra `fetchCategories` per drain → Mitigation: single cached call, only when the drain holds entry create/update rows.
- [Risk] Join-heal vs legitimate server prune oscillation → Mitigation: heal fires only for ids backed by existing clean local rows; a relay-side category delete arrives as a tombstone and removes the local row, which stops the healing.
- [Risk] Rival remap leaves cross-device id divergence (A-id vs B-id, same name) → Accepted: goal is no silent loss, not global id unity; future touches converge whole-row via LWW.

## Open Questions

- None blocking. Follow-ups (not this change): snapshot-reconciliation vs tombstone-only spec tension (four tests pin legacy snapshot removal); same-second user-edit 409 losing the second edit locally.
