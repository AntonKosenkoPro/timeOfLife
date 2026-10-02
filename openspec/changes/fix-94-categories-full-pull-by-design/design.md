## Context

See `proposal.md` (Why) for motivation. Current state: `ListCategories` (`backend/internal/handlers/catalog.go:54-69`) ignores `modified_since` and returns the full list ordered by name; the OpenAPI `GET /categories` note (~lines 482-489) already says full-pull but frames delta support as a "follow-up"; FURPS F7/S1 and both test pins (`contract/openapi_test.go:460`, `handlers/entries_edge_test.go:226`) already pin the full-pull contract; iOS `fetchCategories()` is a bare full pull and `SyncController` full-pulls categories with a local-only cursor that is never sent. The single inconsistency is the `sync-client` delta-pull parenthetical `(and GET /categories)`.

Constraints from `docs/project-context.md`: OpenAPI is the authoritative API contract (S10) — wording changes stay consistent on both sides; baseline specs are never edited directly (delta only); no backward-compat burden for on-disk formats is irrelevant here (no format change).

## Goals / Non-Goals

**Goals:**

- Make FURPS, spec, and contract consistently say categories full-pull with the stated reason (catalog small).
- Keep both existing pins green without touching them.

**Non-Goals:**

- Any handler/store/client/test behavior change; adding `modified_since` to categories; removing the unused `CategoryFilter.ModifiedSince` DB hook.

## Decisions

- **Docs-only drop + harden (decision A from the issue), not implement-the-filter.** Rationale: catalog is seeded plus a handful of user rows, so snapshot merge is cheap; entries are unbounded and justify the cursor. Alternative (implement `modified_since` on categories end-to-end) rejected as disproportionate: handler + store filter + client cursor + OpenAPI + pins all change for negligible payload savings.
- **Leave `CategoryFilter.ModifiedSince` in place as a noted future hook.** Rationale: removing an unused struct field adds churn with no behavior gain; noting it keeps the option open. Alternative (delete it now) rejected — it is harmless and documents where a filter would plug in.
- **No ctx7 fetch.** No external library/framework/SDK behavior constrains this design (wording-only change to first-party spec + OpenAPI text); nothing to cite.

## Risks / Trade-offs

- [Risk] A reader interprets "by design" as "never revisit" → Mitigation: delta spec + OpenAPI note keep the rationale (catalog small) so a future scale-up can reopen the question deliberately.
- [Risk] OpenAPI edit drifts from the delta spec → Mitigation: tasks verify the three surfaces (FURPS already correct, delta spec, OpenAPI note) use the same "full-pull by design (catalog small)" phrasing.

## Migration Plan

No migration: no code, schema, or contract-shape change. Rollback is reverting the two wording edits.
