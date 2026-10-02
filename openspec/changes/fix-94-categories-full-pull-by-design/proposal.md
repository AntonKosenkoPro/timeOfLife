## Why

`GET /categories` is full-pull by intent, but the `sync-client` baseline still carries a stale `(and GET /categories)` parenthetical on the delta-pull requirement, contradicting FURPS F7/S1, the OpenAPI description, and the pinned handler behavior. Issue #94 resolves this as drop + harden: declare full-pull by design and fix the wording, not the code.

## What Changes

- Delete the stale `(and GET /categories)` parenthetical from the `sync-client` "Delta pull via modified_since" requirement so it names `GET /entries` only.
- Harden the OpenAPI `GET /categories` description note from "follow-up" wording to "by design (catalog small)" with the stated rationale (small seeded catalog, cheap snapshot merge; entries are unbounded and need the cursor).
- No handler, store, client, or test changes: `ListCategories` keeps ignoring `modified_since`, both existing pins stay green untouched.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `sync-client`: delta-pull requirement becomes entries-only; categories are full-pull by design.

## Impact

- Docs/spec touch only: `openspec/specs/sync-client/spec.md` (via this change's delta), `backend/api/openapi.yaml` (`GET /categories` description, ~lines 482-489).
- Authoritative references already consistent and unchanged: FURPS F7/S1 (`Requirements/FURPS/Timetracking.md`), `ListCategories` (`backend/internal/handlers/catalog.go:54-69`), pins `contract/openapi_test.go:460 TestSpec_NoModifiedSinceOnListCategories` and `handlers/entries_edge_test.go:226 TestCategories_ModifiedSinceIgnored`, iOS `fetchCategories()` / `SyncController` full-pull categories path.
- Non-goals: implementing `modified_since` on categories; removing the unused `CategoryFilter.ModifiedSince` DB-layer hook (left in place, noted as a future hook); any behavior, migration, or client cursor change. No ctx7 external-docs fetch: no external library behavior is involved.
