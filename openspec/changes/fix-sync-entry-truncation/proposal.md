## Why

The entry sync pull silently truncates history: `GET /entries` is paginated (default page 50, newest-first by `started_at`), but the iOS pull fetches exactly one page, ignores `next_cursor`, and then advances the `entry` sync cursor to the max `updated_at` of that partial page. Any entry beyond the first 50 whose `updated_at` falls below that max never matches a future `modified_since` delta — it is lost permanently, not delayed. Local SQLite itself is uncapped, so History, Recents/autocomplete, and Insights (all pure local reads) faithfully mirror the same truncated 50 rows (~2–3 days of active use). Sync convergence is broken for any account with more than one page of entries.

## What Changes

- Entry pull follows relay pagination to exhaustion: request pages with `limit` + `cursor`, decode `next_cursor`, keep fetching until the relay returns no cursor, merge every page with the existing LWW rules.
- The `entry` sync cursor advances to the max `updated_at` over **all** pages received in the pull, never to the max of a partial page; empty pull keeps the cursor (unchanged behavior).
- Same-account guard and per-record abort checks apply per page fetch, not just per pull, so a mid-pull account swap still aborts before merging foreign records.
- Regression coverage: >1-page pull (e.g. 120 entries over default pages) converges fully; cursor lands on the global max; delta after a full paged pull returns nothing new.
- Repro first (repo rule): seed >50 entries on the relay, fresh sign-in, count local rows — expect 50 before the fix, full set after.

## Capabilities

### New Capabilities

(none — behavior fix within the existing sync contract)

### Modified Capabilities

- `sync-client`: the delta-pull requirement gains cursor-following pagination — a pull is complete only when the relay reports no further page, and the entries cursor advances over the complete result.

## Impact

- iOS: `RemoteCatalogRepository.fetchEntries` (paging loop + `limit`/`cursor` params), `EntryListResponse` (decode `next_cursor`), `SyncController.pull` (page loop, cursor advance, per-page account guard).
- Contract: `backend/api/openapi.yaml` already documents `limit`/`cursor`/`next_cursor` on `GET /entries` — no endpoint change; at most a clarifying line that sync clients must exhaust pages.
- Backend: no change (pagination behavior is correct and covered by `TestListEntries_CursorFollowThrough`).
- Tests: new `SyncControllerTests` paged-pull cases + `RemoteCatalogRepositoryTests` cursor decoding; existing sync suite must stay green.
- Non-goals: adopting `GET /entries/recents` on the client, server-side Insights aggregation, category pagination (categories are full-pull by design), deletions pagination (uncapped today).
