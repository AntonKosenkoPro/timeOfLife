# Activity Catalog & Categories — Backend API Design

Backend design for **Epic 1: Activity Catalog & Categories** (`Epics.md`, requirements in [`Requirements/FURPS/Activity_Catalog_and_Categories.md`](../../Requirements/FURPS/Activity_Catalog_and_Categories.md)). The authoritative contract is [`backend/api/openapi.yaml`](../../backend/api/openapi.yaml); this doc is the design reasoning and is kept in sync with it.

**Scope (confirmed):** Epic 1 backend introduces three resources — **activities**, **categories**, and **entries** — so `activity_id` has a real home and history syncs cross-device from the start. Entries editing/UI is Epic 2, but the entries *resource* and its sync land here (per the Epics.md cross-cutting note: build the entries schema once, with `activity_id` from day one, so Epics 2/7/8 don't re-migrate).

All endpoints are under `/api/v1`, require a Bearer access token (`AuthMiddleware`, existing), and are scoped to the authenticated `userID` from context. Errors use the existing uniform envelope `{ "error": { code, message, details } }`.

---

## Data model

New migration `003_catalog.sql`. Follows the existing pattern (`internal/migrations/00X_*.sql`, Postgres SQL auto-adapted to SQLite by `migrations.adaptToSQLite`). All ids are **client-generated UUID v7** (see [Sync & ids](#sync--ids) below).

### `activities`
| column | type | notes |
|---|---|---|
| `id` | UUID PK | client-generated v7 |
| `user_id` | UUID NOT NULL → users(id) | owner scope |
| `name` | TEXT NOT NULL | ≤ 60 chars, trimmed |
| `notes` | TEXT | ≤ 280 chars, nullable |
| `last_used_at` | TIMESTAMPTZ | recency for **client-side** suggestions (F5); updated on entry start; synced so recency is shared across devices |
| `created_at` | TIMESTAMPTZ NOT NULL DEFAULT NOW() | |
| `updated_at` | TIMESTAMPTZ NOT NULL DEFAULT NOW() | LWW sync version (R2) |

- `UNIQUE (user_id, lower(name))` — enforces case-insensitive dedup per user (F4).
- `INDEX (user_id, last_used_at DESC)` — recency-ordered list (P1); also backs client-side suggestion ranking.

### `categories`
| column | type | notes |
|---|---|---|
| `id` | UUID PK | client-generated v7 |
| `user_id` | UUID NOT NULL → users(id) | |
| `name` | TEXT NOT NULL | ≤ 60 chars |
| `icon` | TEXT NOT NULL | SF Symbol name; chosen from the allowed set (validated) |
| `created_at` | TIMESTAMPTZ NOT NULL DEFAULT NOW() | |
| `updated_at` | TIMESTAMPTZ NOT NULL DEFAULT NOW() | LWW sync version |

- `UNIQUE (user_id, lower(name))` — case-insensitive uniqueness per user.

### `activity_categories` (many-to-many tag join; F2/F3)
| column | type | notes |
|---|---|---|
| `activity_id` | UUID → activities(id) ON DELETE CASCADE | |
| `category_id` | UUID → categories(id) ON DELETE CASCADE | |
| `PRIMARY KEY (activity_id, category_id)` | | |

Deleting a category removes the tag from all activities (cascade on the join) but does **not** touch entries — entries infer tags from their activity at query time (F9), so they simply drop the tag.

### `entries`
| column | type | notes |
|---|---|---|
| `id` | UUID PK | client-generated v7 |
| `user_id` | UUID NOT NULL → users(id) | |
| `activity_id` | UUID NOT NULL → activities(id) ON DELETE CASCADE | required; every entry references exactly one activity |
| `started_at` | TIMESTAMPTZ NOT NULL | |
| `ended_at` | TIMESTAMPTZ | NULL = running timer |
| `duration_seconds` | INT | `ended_at - started_at` when ended; NULL while running; stored for query/filter convenience |
| `source` | TEXT NOT NULL DEFAULT 'manual' | provenance enum: `manual`, `widget`, `siri`, `control`, `screentime`, `garmin`, `calendar`, `healthkit` |
| `source_ref` | TEXT | external identifier for the source (e.g. Screen Time callback uuid, Garmin activity id); NULL for `manual` |
| `created_at` | TIMESTAMPTZ NOT NULL DEFAULT NOW() | |
| `updated_at` | TIMESTAMPTZ NOT NULL DEFAULT NOW() | LWW sync version |

- `INDEX (user_id, started_at DESC)` — history list / date-range queries (Epic 2).
- `INDEX (user_id, activity_id)` — per-activity lookups.
- `UNIQUE (user_id, source, source_ref)` — for non-null `source_ref`; prevents duplicate imports (e.g. a Screen Time callback firing twice for the same interval). A duplicate insert is rejected with **409 `duplicate_import`**.
- FK `ON DELETE CASCADE`: deleting an activity removes all its entries (F10 "delete entire activity and all N entries").
- The activity's **name** and **tags** are resolved from the activity at query time (via `activities` and `activity_categories` ⨝ `categories`), so editing an activity's name or tags reflects on its past entries (F9). Nothing is frozen/denormalized on the entry.

---

## Sync & ids

> **The backend is a relay, not the authority** (OpenSpec change `local-first-sync-architecture`). The client's local GRDB database is the source of truth; the backend stores a copy for cross-device sync and integrations. The API contract is stable — the local-first change only adds an optional `modified_since` query param and nullable `source`/`source_ref` fields (D5). The client drives sync: it drains a transactional outbox (one HTTP call per mutation) and pulls deltas via `?modified_since=`; the server's merge rules (idempotent POST, LWW, hard DELETE) are unchanged.

- **Client-generated UUID v7 ids** for activities/categories/entries. The client creates records offline (e.g. auto-create an activity, start an entry against it) and references the id locally; on reconnect it `POST`s with the id already known. The server validates the id format and uses it. `POST` is **idempotent on `id`** — a replay of the same id returns the existing record (no duplicate), which makes the offline queue safe to replay.
- **Last-write-wins on `updated_at`** (R2): every mutable request (`PATCH`) carries the client's `updated_at`. The server applies the write only if `client.updated_at > server.updated_at` (optimistic `UPDATE … WHERE updated_at < $client_updated_at`). On a stale write the server returns **409 `conflict`** with its current version so the client can reconcile. No field-level merge at MVP.
- **Hard deletes** (R3): no server-side trash. The client holds the 30 s undo buffer; the `DELETE` is only sent to the server after the undo window passes (or is never sent if undone). The server just hard-deletes.
- **Cross-device name collision** (two devices create "Gym" offline with different ids): the `UNIQUE (user_id, lower(name))` constraint rejects the second `POST` with **409 `activity_exists`** (carrying the winning activity in `details`). The client re-maps its local entries/entry references to the surviving id. Noted as the one LWW edge case the client must handle.
- **Delta pull-sync**: `GET /activities` and `GET /entries` accept an optional `modified_since` (RFC 3339) that filters to records with `updated_at` **strictly greater** than the timestamp; absent/empty = full pull. The client advances a per-resource cursor to the max `updated_at` received, so integrations (hundreds/thousands of entries) don't force full re-pulls.
- **Entry provenance**: entries carry `source` (default `manual`) and nullable `source_ref`. The `UNIQUE (user_id, source, source_ref)` constraint rejects a duplicate import with **409 `duplicate_import`** — a source re-sending the same record (Screen Time firing twice, Garmin re-sync) cannot create a duplicate. Deleting an imported entry is a hard delete; a later re-import of the same `(source, source_ref)` does not resurrect it.

---

## Endpoints

All `401 unauthorized` on missing/invalid token (existing `AuthMiddleware`). All `400 invalid_body` on malformed JSON (existing `decodeJSON`).

### Activities

| Method | Path | Body | Success | Errors |
|---|---|---|---|---|
| GET | `/activities` | — | 200 `[{activity…}]` ordered by `last_used_at DESC`; optional `?q=` typeahead filter (case-insensitive `name LIKE`), optional `?modified_since=` delta pull (filters `updated_at > modified_since`) | (401) |
| GET | `/activities/{id}` | — | 200 `{activity…}` with `categories[]` | 404 `not_found`, (401) |
| POST | `/activities` | `{id, name, notes?, category_ids?}` | 201 `{activity…}`; idempotent on `id` (replay → 200 existing) | 400 `invalid_body`, 422 `validation_error`, 409 `activity_exists`/`conflict`, (401) |
| PATCH | `/activities/{id}` | `{name?, notes?, category_ids?, updated_at}` | 200 `{activity…}` (full `category_ids` = replace-all tags) | 400, 404 `not_found`, 409 `conflict`/`activity_exists`, 422, (401) |
| DELETE | `/activities/{id}` | — | 204 (cascades to entries + join rows) | 404 `not_found`, (401) |

### Categories

| Method | Path | Body | Success | Errors |
|---|---|---|---|---|
| GET | `/categories` | — | 200 `[{category…}]` ordered by name | (401) |
| POST | `/categories` | `{id, name, icon}` | 201 `{category…}`; idempotent on `id` | 400, 422, 409 `category_exists`/`conflict`, (401) |
| PATCH | `/categories/{id}` | `{name?, icon?, updated_at}` | 200 `{category…}` | 400, 404, 409 `conflict`/`category_exists`, 422, (401) |
| DELETE | `/categories/{id}` | — | 204 (join rows cascade; entries unaffected) | 404, (401) |

### Entries

| Method | Path | Body | Success | Errors |
|---|---|---|---|---|
| GET | `/entries` | — | 200 `{items:[…], next_cursor?}` ordered by `started_at DESC`; filters `?from=&to=&activity_id=&category_id=&limit=&cursor=&modified_since=` (delta pull) | (401) |
| GET | `/entries/{id}` | — | 200 `{entry…}` with `categories[]` (inferred from the activity) and `activity_name` (the activity's current name) | 404, (401) |
| POST | `/entries` | `{id, activity_id, started_at, ended_at?, source?, source_ref?}` | 201 `{entry…}`; `activity_id` is required and must belong to the user; `ended_at` null = running; `source` defaults to `manual`; duplicate `(source, source_ref)` → 409 `duplicate_import` | 400, 422, 404 `activity_not_found` (when `activity_id` doesn't belong to user), 409 `conflict`/`duplicate_import`, (401) |
| PATCH | `/entries/{id}` | `{started_at?, ended_at?, updated_at}` | 200 `{entry…}` (stop a running timer = set `ended_at`; recompute `duration_seconds`) | 400, 404, 409 `conflict`, 422, (401) |
| DELETE | `/entries/{id}` | — | 204 (hard delete) | 404, (401) |

> `activity_id` on `POST /entries` is required — every entry must reference an activity. The activity's name and tags are resolved at query time, so no name is stored on the entry.

### Suggestions (F5) — client-side, no endpoint

**Suggestions are computed on-device from the local catalog; there is no `/activities/suggestions` endpoint.** The client already holds the synced catalog (offline-first), so it ranks its local activities by `last_used_at` and takes the top 5 — a server round-trip would buy nothing and would break offline. `last_used_at` still syncs (see the `activities` table above), so recency is shared across devices: when device A uses "Gym" and syncs, device B's local `last_used_at` updates and B's suggestions reflect it on the next sync. The backend's only recency-related responsibility is to keep `last_used_at` correct on every entry start and let it sync.

### Seeding (F6)

No dedicated endpoint. Seeds are created client-side on first run (7 localized categories with catalog icons, no activities) and synced via ordinary `POST /categories` calls. This keeps the backend simple and lets the client own localization (EN/RU) — the server is locale-agnostic. Seeds are ordinary records, fully editable/deletable.

---

## Resource shapes

### Activity
```json
{
  "id": "0196…", "name": "Gym",
  "notes": "", "last_used_at": "2026-07-27T09:00:00Z",
  "created_at": "…", "updated_at": "…",
  "categories": [ { "id": "…", "name": "Sport", "icon": "figure.run" } ]
}
```

### Category
```json
{ "id": "…", "name": "Sport", "icon": "figure.run", "created_at": "…", "updated_at": "…" }
```

### Entry
```json
{
  "id": "…", "activity_id": "…", "activity_name": "Gym",
  "started_at": "…", "ended_at": "…", "duration_seconds": 3600,
  "source": "manual", "source_ref": null,
  "created_at": "…", "updated_at": "…",
  "categories": [ { "id": "…", "name": "Sport", "icon": "figure.run" } ]
}
```
`activity_name` and `categories` are resolved from the activity at query time (the entry stores only `activity_id`). `source` records provenance (default `manual`); `source_ref` holds the external identifier for non-`manual` sources (e.g. Screen Time callback uuid, Garmin activity id) and is null for `manual`.

---

## Validation (U1/U2)

Reuses the auth validator pattern (one field → one error; multiple rules for one field collapse into a single unified message). On failure: **422 `validation_error`**, `details` = `{ "<field>": "<message>" }`.

- `name` (activity & category): non-empty after trim, ≤ 60 chars.
- `notes`: ≤ 280 chars.
- `icon` (category): must be a non-empty SF Symbol string from the allowed set.
- `started_at`: required, valid RFC 3339, ≤ now + small clock-skew tolerance.
- `ended_at`: if present, must be > `started_at`.
- `category_ids`: each must exist and belong to the user.
- `id` (on POST): valid UUID v7 format.

No count caps at MVP (Resolved decisions).

---

## Error codes (additions)

All flow through the existing `ErrorResponse` envelope.

| code | HTTP | meaning |
|---|---|---|
| `validation_error` | 422 | field-level validation failure; `details` = field→message map |
| `not_found` | 404 | resource doesn't exist or belongs to another user |
| `conflict` | 409 | LWW stale write (`updated_at` older than server); `details` carries the server's current version |
| `activity_exists` / `category_exists` | 409 | case-insensitive name collision on create; `details` carries the existing record |
| `activity_not_found` | 404 | `POST /entries` referenced an `activity_id` that doesn't belong to the user |
| `duplicate_import` | 409 | `POST /entries` with a `(source, source_ref)` that already exists for the user (uniqueness constraint); the existing entry is kept as-is |
| `internal_error` | 500 | existing; never leaks cause |
| `invalid_body` / `unauthorized` / `rate_limited` | 400/401/429 | existing semantics |

No PII (notes content) is logged (S4); structured `log/slog` events use ids only.

---

## Implementation plan (backend)

Mirrors the existing layering so review is mechanical:

1. **Migration** `internal/migrations/003_catalog.sql` — the four tables + indexes + constraints above; the provenance columns (`source`, `source_ref`) + unique constraint are added in a follow-up migration (`004_provenance.sql` or appended to `003_catalog.sql` if not yet shipped).
2. **Store** — extend `db.Store` with activity/category/entry CRUD + `activity_categories` methods; implement in `postgres.go` and `sqlite.go` (dual, per convention). Add `ErrConflict`, `ErrActivityExists`, `ErrCategoryExists` to `errors.go`.
3. **Handlers** — new `internal/handlers/catalog.go` (activities + categories) and `internal/handlers/entries.go` (entries), reusing `decodeJSON`/`writeJSON`/`writeError` and `UserIDFromContext`. New validators in a `catalog_validators.go` matching the auth validator style. (No suggestions handler — F5 is client-side.)
4. **Routing** — `server.go`: `r.Route("/api/v1", …)` adds `/activities`, `/categories`, `/entries` groups, all `r.With(h.AuthMiddleware)`.
5. **OpenAPI** — append the paths + schemas above to `backend/api/openapi.yaml` (S10/S1).
6. **Tests** — `catalog_test.go`, `entries_test.go` against the SQLite store; cover validators, dedup, LWW conflict, cascade delete, idempotent POST, `modified_since` delta pull, and `duplicate_import` provenance (S2).
7. **Docs** — update `AGENTS.md` (API contract table + catalog/entries entries), `README.md` (API contract + coverage), and this doc stays the design source.
