## Context

Local-first: device is source of truth, relay is optional transport. `LocalStore` is the single mutation chokepoint; outbox rows hold the operation + payload. Backend `POST /entries` is strict (`ErrInvalidCategoryID` → 422) while `PATCH` and pull-merge prune unknown ids (D7). iOS steady cycle is tombstones → drain → pull; first sync is pull → tombstones → drain. Pull already fetches/merges categories before entries.

## Decisions

- D1 — Categories-before-entries drain: sort the drain snapshot by (resourceRank, created_at, id) with category=0, entry=1, other=2. Preserves within-resource FIFO; fixes entry-before-category 422 after fresh backend deploys, seed races, and same-second `created_at` ties. Alternatives (global FIFO, parallel push) rejected: they reproduce the wedge.
- D2 — Heal-on-422, retry once: on `validation_error` + `category_ids` for entry create/update, `fetchCategories`, intersect payload ids with server ids, rewrite outbox payload via existing `rewriteOutboxPayload`, retry push once. Mirrors pull-side "drop unknown, keep remainder, never fail cycle" without silently dropping the whole entry. No local join rewrite: the post-drain pull converges local via LWW (server pruned version is newer). A winner-fetch-style failure rethrows and keeps the row queued.
- D3 — Keep backend strict: 422 stays as a safety net for genuinely bad clients; iOS now handles it. No `openapi.yaml`, migration, or store-schema change.

## Risks

- Pruned push loses the dropped tags server-side until the user re-attaches them; accepted (same as pull-prune) and surfaced in logs.
- Extra `fetchCategories` on the 422 path only; happy path unchanged.
