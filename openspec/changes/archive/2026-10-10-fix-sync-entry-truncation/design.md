## Context

See proposal.md (Why) for motivation. Current state:

- `GET /entries` paginates: `ORDER BY started_at DESC, id DESC`, `limit` default 50 / max 200, opaque `cursor` in, `next_cursor` out (`backend/internal/db/sqlite_catalog.go:392`, `catalog_shared.go:34`, `backend/api/openapi.yaml:685-698,1580-1592`). Pagination itself is correct and covered by `TestListEntries_CursorFollowThrough`.
- The iOS relay client (`RemoteCatalogRepository.fetchEntries`, `entriesPath`) sends only `?modified_since=` — no `limit`, no `cursor` — and `EntryListResponse` decodes only `items`, dropping `next_cursor`.
- `SyncController.pull` advances the `entry` cursor to `max(updated_at)` of the single page received. Page order (`started_at`) is uncorrelated with cursor order (`updated_at`), so the advance can skip unseen rows permanently.
- Local reads (`LocalStore.entries()`, `allActivityNames()`, `recents(limit:)`) are uncapped and correct; History, Insights, Recents, and the name picker all heal automatically once the pull is complete. No local-query change is needed.
- Same-account guard exists at cycle, stage, and per-record level; the page loop must participate in it.

## Goals / Non-Goals

**Goals:**

- Converge the full entry history on every pull regardless of page count, with the cursor always reflecting the complete result.
- Keep the fix client-side: no relay or contract change (the contract already supports paging; the client just doesn't use it).

**Non-Goals:**

- Adopting `GET /entries/recents` on the client, server-side Insights aggregation, category/deletion pagination, retry/backoff policy for page fetches (existing cycle error handling applies), offline page caching beyond the current snapshot merge.

## Decisions

1. **Follow `next_cursor` in the relay client (`fetchEntries` gains an internal page loop) over a dedicated sync endpoint.**
   The contract already exposes everything needed; a new endpoint would add relay surface for a client-side omission. Alternative (server `?all=true` bypass) rejected: it weakens the cost bound pagination exists for and still leaves the cursor-advance bug to fix separately.

2. **Request explicit `limit=200` (the relay max) on sync pulls.**
   Fewer round-trips per cycle (a 120-entry history converges in 1 page instead of 3). Default 50 stays for any other consumer. Alternative (keep default 50, loop more) rejected: more requests per cycle for no benefit; the max is documented and stable.

3. **Decode `next_cursor` as optional on `EntryListResponse`; loop while non-nil/non-empty.**
   The relay omits the key on the last page (`entries.go:68-71`), so absent and empty both terminate. Pre-release policy means editing the `Decodable` shape in place — no legacy branches.

4. **Advance the `entry` cursor once, to the max `updated_at` over all merged pages; skip the advance if the pull merged nothing.**
   Preserves the existing no-change-keeps-cursor convention and makes the advance order-independent (page order is by `started_at`, cursor domain is `updated_at`).

5. **Check the same-account guard after each page fetch, before merging that page.**
   Mirrors the existing mid-stage `requireSameAccount` pattern. A swap mid-pull costs at most one already-fetched page merged under the old session — same bound as today's mid-stage swap — and already-merged pages stay (they passed the guard when merged); the cursor does not advance for the aborted pull, so the next complete cycle re-merges idempotently via LWW.

6. **Repro before fixing (repo rule, S5): seed 120 entries via the relay, fresh sign-in, count local rows.**
   Encoded as the regression test below; the test fails on the current tree (50 rows) and passes after.

## Risks / Trade-offs

- [Risk] Large histories make first-sync slower (N pages serially) → Mitigation: `limit=200` keeps page count low; pulls stay foreground/connectivity-triggered as today; no behavior change for small accounts (single page, one request as before).
- [Risk] Mid-pull merge is not atomic across pages (crash between pages leaves partial merge + unadvanced cursor) → Mitigation: next cycle's pull re-fetches from the old cursor and LWW-merge is idempotent, so convergence just takes one more cycle; per-page merges already go through the same `mergeEntry` path.
- [Risk] Relay raises `maxEntryLimit` later and `limit=200` silently becomes non-max → Mitigation: loop terminates on absent `next_cursor`, not on page size, so correctness never depends on the limit value — only round-trip count does.
- [Risk] `modified_since` + `cursor` interaction on the relay (cursor resumes `started_at` order within the filtered set) → Mitigation: covered by a backend-parity test (filtered multi-page fetch returns the full filtered set); no relay change needed — `ListEntries` already combines both predicates (`sqlite_catalog.go:407-414`).

## Migration Plan

No migration: pre-release, no on-disk format change, no endpoint change. Rollback is a plain revert — worst case a device reverts to single-page pulls with the old cursor behavior.

## Open Questions

None — the only unknown (exact relay `limit`/`cursor` semantics) is answered by the existing handler, store, and edge tests cited above.
