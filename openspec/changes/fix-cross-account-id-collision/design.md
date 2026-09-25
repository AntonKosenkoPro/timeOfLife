## Context

See proposal.md — Why. Current state (reproduced locally, not hypothesized):
`POST /categories` with an id committed under another user returns
`409 category_exists` with `details: {"id": "", "name": ""}`, because record
ids are a global `PRIMARY KEY` (`003_catalog.sql`) while the id pre-check, the
name pre-check, and the post-violation winner re-query are all user-scoped
(`postgres_catalog.go` / `sqlite_catalog.go` `CreateCategory`). The client's
remap flow takes `details["id"]` verbatim and requests
`GET /api/v1/categories/` (empty id); chi has no such route, so the bare 404
(`http_404`) fails the cycle with the outbox row still queued — the identical
`POST→409 → GET→404` pair repeats every cycle (prod access log, three
occurrences). Entries have the mirror hazard: a cross-user id `POST` trips the
entries-table PK, which `isUniqueViolation` maps to `ErrDuplicateImport`;
`resolveConflict` then clears the row silently while the entry is missing
remotely. The normal populated-winner path was verified working (exact, case,
and whitespace name variants all return the winner).

## Goals / Non-Goals

- Goals: unwedge the sync (including the currently-wedged device, with no data
  surgery); make cross-account id reuse structurally impossible going forward;
  never emit or fetch an empty winner id again; keep the populated-winner remap
  path byte-for-byte as is.
- Non-Goals: OTP↔SiWA identity merging; relay PK schema change; idempotency
  semantic change; new error codes; touching tombstone/delete-wins behavior.

## Decisions

- **Fresh-id adoption at account switch (prevention).** `switchSyncAccountIfNeeded`
  clones adopted rows under `newRecordID()` instead of re-enqueueing original
  ids, rewriting entry payloads to the fresh category ids in the same
  chokepoint transaction (existing `remapCategoryReferences` machinery covers
  categories; entries get a small sibling helper). Rejected alternative: keep
  old ids and rely on the relay tolerating cross-user reuse — impossible
  without breaking the global PK / idempotency contract. Rejected alternative:
  backend per-user PKs — a schema + semantics migration far out of proportion.
  Fresh ids can't collide (UUIDv7); same-name clashes then flow through the
  proven populated-409 remap. Stale update rows for old ids are dropped in the
  same transaction (the adoption create carries current state — lossless);
  delete rows are preserved (404-as-success converges them).
- **Drain self-heal by rewrite-in-place (cure).** On an unresolvable collision
  (nil/empty winner), the drain rewrites the stuck outbox row's record id and
  payload to a fresh id, remaps local joins/payloads, pushes, then adopts the
  landed row locally (drop old local row, merge fresh, drop superseded
  companion rows) — reusing the remap flow's convergence shape. Bounded by
  construction (a second collision on a fresh UUID is a new occurrence, and a
  populated 409 converges via the existing remap). This heals the currently
  wedged device with no version stamps and no manual steps, and works even
  against an undeployed backend.
- **Entry disambiguation by single GET (no backend change).** `duplicate_import`
  stays silent-clear only after `GET /entries/{id}` confirms the relay holds
  the same import keys; `not_found` there proves a cross-user id collision and
  routes to the same self-heal. The extra GET fires only on the rare 409 path.
  Rejected alternative: a new backend code for entry PK clashes — unnecessary
  once the client can distinguish with one read.
- **Backend honesty valve (tiny).** When the post-violation winner re-query
  misses, emit the 409 with nil details instead of `{"id":"","name":""}`,
  documented in `openapi.yaml` as unresolvable-collision. No new code, no
  behavior change for populated winners. This stops any client (present or
  future) from ever building an empty-id route.
- **Guard: never fetch an empty id.** Any winner id that is missing or empty
  keeps the row queued and fails loudly with a collision diagnostic naming the
  record (secret-free), replacing today's mystery `http_404`.

## Risks / Trade-offs

- [Risk] Fresh ids duplicate a logical row across accounts (OTP keeps id A,
  SiWA gets id F) → Mitigation: accepted — accounts are separate relay
  universes by design (no identity merge); each converges independently.
- [Risk] Self-heal + populated-409 interplay double-lands a row → Mitigation:
  the second push 409s populated (name now taken) and converges via the
  existing remap, which drops the redundant local/queue state.
- [Risk] Switch-back-and-forth mints ids per account per switch → Mitigation:
  adoption runs once per account transition (stored-id compare); steady
  same-account cycles are untouched.
- [Risk] Buffered/undo rows referencing old ids during a heal → Mitigation:
  heals refuse while a record is locally deleted (delete-wins guard, mirroring
  every other pull/drain path); pending DELETE pushes converge via
  404-as-success.

## Migration Plan

No schema or data migration. Deploy order is safe either way: new client +
old backend self-heals without the nil-details valve; old client + new backend
behaves as today (nil details hit the same guards that empty strings do).
Roll back by reverting; queued rows resume under previous rules.

## Open Questions

None — endpoint behavior was reproduced against a live backend before writing
this; naming and codes were deliberately kept to existing vocabulary.
