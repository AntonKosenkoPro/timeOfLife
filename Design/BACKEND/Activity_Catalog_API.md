# Entry & Categories — Backend API Design

Backend design for **entry-owned text and category tags** (requirements in [`Requirements/FURPS/Activity_Catalog_and_Categories.md`](../../Requirements/FURPS/Activity_Catalog_and_Categories.md); OpenSpec change `remove-activities-layer`). The authoritative contract is [`backend/api/openapi.yaml`](../../backend/api/openapi.yaml); this doc is the design reasoning and is kept in sync with it.

**Scope (confirmed):** the relay stores two resources — **categories** and **entries**. There is no activity entity: every entry owns its trimmed `activity_text`, its ordered `category_ids`, and its `notes` at write time, so history syncs cross-device from the start with nothing resolved at query time.

All endpoints are under `/api/v1`, require a Bearer access token (`AuthMiddleware`, existing), and are scoped to the authenticated `userID` from context. Errors use the existing uniform envelope `{ "error": { code, message, details } }`.

---

## Data model

Migration `007_remove_activities.sql` (one-shot; pre-release, no on-disk compat). Follows the existing pattern (`internal/migrations/00X_*.sql`, Postgres SQL auto-adapted to SQLite by `migrations.adaptToSQLite`). All ids are **client-generated UUID v7** (see [Sync & ids](#sync--ids) below).

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

### `entry_categories` (ordered tag join; F3)
| column | type | notes |
|---|---|---|
| `entry_id` | UUID → entries(id) ON DELETE CASCADE | |
| `category_id` | UUID → categories(id) ON DELETE CASCADE | |
| `position` | INT NOT NULL | explicit order; first position supplies chip/row icons |
| `PRIMARY KEY (entry_id, category_id)` | | |

Deleting a category removes the tag from all entries (cascade on the join) but does **not** touch entries themselves — each entry simply drops the tag.

### `entries`
| column | type | notes |
|---|---|---|
| `id` | UUID PK | client-generated v7 |
| `user_id` | UUID NOT NULL → users(id) | |
| `activity_text` | TEXT NOT NULL | exact trimmed identity (byte-exact, case-sensitive); ≤ 60 chars |
| `notes` | TEXT NOT NULL DEFAULT '' | ≤ 280 chars |
| `started_at` | TIMESTAMPTZ NOT NULL | |
| `ended_at` | TIMESTAMPTZ | set at Stop; entries are Stop-only (no running rows) |
| `duration_seconds` | INT | `ended_at - started_at`; stored for query/filter convenience |
| `source` | TEXT NOT NULL DEFAULT 'manual' | provenance enum: `manual`, `widget`, `siri`, `control`, `screentime`, `garmin`, `calendar`, `healthkit` |
| `source_ref` | TEXT | external identifier for the source (e.g. Screen Time callback uuid, Garmin activity id); NULL for `manual` |
| `created_at` | TIMESTAMPTZ NOT NULL DEFAULT NOW() | |
| `updated_at` | TIMESTAMPTZ NOT NULL DEFAULT NOW() | LWW sync version |

- `INDEX (user_id, started_at DESC)` — history list / date-range queries (History feature).
- `INDEX (user_id, activity_text, started_at DESC)` — Recents grouping (`GROUP BY activity_text`, newest wins).
- `UNIQUE (user_id, source, source_ref)` — for non-null `source_ref`; prevents duplicate imports (e.g. a Screen Time callback firing twice for the same interval). A duplicate insert is rejected with **409 `duplicate_import`**.
- The entry's **text**, **ordered tags** (via `entry_categories` ⨝ `categories`), and **notes** are stored on the entry. Editing one entry never affects another (per-entry isolation); nothing is resolved at query time.

---

## Sync & ids

> **The backend is a relay, not the authority** (OpenSpec change `local-first-sync-architecture`). The client's local GRDB database is the source of truth; the backend stores a copy for cross-device sync and integrations. The `remove-activities-layer` change is a contract break (OpenAPI v2.0.0): it removes `/activities*` and `activity_id` and puts owned fields on entries. The client drives sync: it drains a transactional outbox (one HTTP call per mutation) and pulls deltas via `?modified_since=`; the server's merge rules (idempotent POST, LWW, hard DELETE) are unchanged.

- **Client-generated UUID v7 ids** for categories/entries. The client creates records offline and references the id locally; on reconnect it `POST`s with the id already known. The server validates the id format and uses it. `POST` is **idempotent on `id`** — a replay of the same id returns the existing record (no duplicate), which makes the offline queue safe to replay.
- **Last-write-wins on `updated_at`** (R2): every mutable request (`PATCH`) carries the client's `updated_at`. The server applies the write only if `client.updated_at > server.updated_at` (optimistic `UPDATE … WHERE updated_at < $client_updated_at`). On a stale write the server returns **409 `conflict`** with its current version so the client can reconcile. No field-level merge at MVP.
- **Hard deletes + tombstones** (R3): no server-side trash. The client holds buffered deletions (restorable until the app restarts); the `DELETE` is only sent to the server after a restart commits the buffer (or is never sent if undone). Each hard delete upserts a `(user_id, resource, record_id, deleted_at)` tombstone in the same transaction (cascade-deleted join rows get none — one row per user intent); recreating an id clears its tombstone. `GET /deletions?deleted_since=` lists tombstones oldest-first for cross-device convergence; no GC yet (rows are tiny, personal scale; `deleted_at` enables a future policy).
- **Cross-device name collision** (two devices create "Sport" offline with different ids): the `UNIQUE (user_id, lower(name))` constraint rejects the second `POST` with **409 `category_exists`** (carrying the winning category in `details`). The client re-maps its local entry references to the surviving id. Noted as the one LWW edge case the client must handle.
- **Delta pull-sync**: `GET /categories` and `GET /entries` accept an optional `modified_since` (RFC 3339) that filters to records with `updated_at` **strictly greater** than the timestamp; absent/empty = full pull. The client advances a per-resource cursor to the max `updated_at` received, so integrations (hundreds/thousands of entries) don't force full re-pulls.
- **Prune-unknown-category**: entry payloads may reference category ids unknown to the receiver (deleted elsewhere). The receiver keeps the remainder and drops the unknown ids — never rejects the entry.
- **Entry provenance**: entries carry `source` (default `manual`) and nullable `source_ref`. The `UNIQUE (user_id, source, source_ref)` constraint rejects a duplicate import with **409 `duplicate_import`** — a source re-sending the same record (Screen Time firing twice, Garmin re-sync) cannot create a duplicate. Deleting an imported entry is a hard delete; a later re-import of the same `(source, source_ref)` does not resurrect it.

---

## Endpoints

All `401 unauthorized` on missing/invalid token (existing `AuthMiddleware`). All `400 invalid_body` on malformed JSON (existing `decodeJSON`).

### Categories

| Method | Path | Body | Success | Errors |
|---|---|---|---|---|
| GET | `/categories` | — | 200 `[{category…}]` ordered by name | (401) |
| POST | `/categories` | `{id, name, icon}` | 201 `{category…}`; idempotent on `id` | 400, 422, 409 `category_exists`/`conflict`, (401) |
| PATCH | `/categories/{id}` | `{name?, icon?, updated_at}` | 200 `{category…}` | 400, 404, 409 `conflict`/`category_exists`, 422, (401) |
| DELETE | `/categories/{id}` | — | 204 (join rows cascade; entries unaffected; one category tombstone) | 404, (401) |

### Entries

| Method | Path | Body | Success | Errors |
|---|---|---|---|---|
| GET | `/entries` | — | 200 `{items:[…], next_cursor?}` ordered by `started_at DESC`; filters `?from=&to=&category_id=&limit=&cursor=&modified_since=` (delta pull) | (401) |
| GET | `/entries/recents` | — | 200 `[{activity_text, started_at, category_ids}]` — newest entry per exact text, `started_at DESC`, capped at 6 | (401) |
| GET | `/entries/{id}` | — | 200 `{entry…}` with owned `activity_text`, ordered `categories[]`, and `notes` | 404, (401) |
| POST | `/entries` | `{id, activity_text, category_ids?, notes?, started_at, ended_at?, source?, source_ref?}` | 201 `{entry…}`; unknown category ids are pruned (remainder kept); `source` defaults to `manual`; duplicate `(source, source_ref)` → 409 `duplicate_import` | 400, 422, 409 `conflict`/`duplicate_import`, (401) |
| PATCH | `/entries/{id}` | `{activity_text?, category_ids?, notes?, started_at?, ended_at?, updated_at}` | 200 `{entry…}` (full `category_ids` = replace-all tags) | 400, 404, 409 `conflict`, 422, (401) |
| DELETE | `/entries/{id}` | — | 204 (hard delete + entry tombstone) | 404, (401) |

### Deletions (cross-device delete propagation)

| Method | Path | Body | Success | Errors |
|---|---|---|---|---|
| GET | `/deletions` | — | 200 `[{resource, id, deleted_at}]` ordered by `deleted_at ASC`; optional `?deleted_since=` (tombstones with `deleted_at > deleted_since`; absent/empty = full list) | 422 `validation_error` (garbage timestamp), (401) |

### Recents (F5) — server-assisted, entries-grouped

`GET /entries/recents` groups the user's entries by exact `activity_text` and returns the newest row per group (`started_at DESC`, `id DESC` tiebreak), capped at 6. The on-device query is authoritative offline; the endpoint exists so a fresh device can render Recents before its first full entry pull.

### Seeding (F6)

No dedicated endpoint. Seeds are created client-side on first run (7 localized categories with catalog icons, no entries) and synced via ordinary `POST /categories` calls. This keeps the backend simple and lets the client own localization (EN/RU) — the server is locale-agnostic. Seeds are ordinary records, fully editable/deletable.

---

## Resource shapes

### Category
```json
{ "id": "…", "name": "Sport", "icon": "figure.run", "created_at": "…", "updated_at": "…" }
```

### Entry
```json
{
  "id": "…", "activity_text": "Gym",
  "started_at": "…", "ended_at": "…", "duration_seconds": 3600,
  "notes": "Leg day",
  "source": "manual", "source_ref": null,
  "created_at": "…", "updated_at": "…",
  "categories": [ { "id": "…", "name": "Sport", "icon": "figure.run" } ]
}
```
`activity_text`, ordered `categories`, and `notes` are owned by the entry (written at creation, changed only by editing that entry). `source` records provenance (default `manual`); `source_ref` holds the external identifier for non-`manual` sources (e.g. Screen Time callback uuid, Garmin activity id) and is null for `manual`.

---

## Validation (U1/U2)

Reuses the auth validator pattern (one field → one error; multiple rules for one field collapse into a single unified message). On failure: **422 `validation_error`**, `details` = `{ "<field>": "<message>" }`.

- `activity_text` (entry): non-empty after trim, ≤ 60 chars.
- `name` (category): non-empty after trim, ≤ 60 chars.
- `notes`: ≤ 280 chars.
- `icon` (category): must be a non-empty SF Symbol string from the allowed set.
- `started_at`: required, valid RFC 3339, ≤ now + small clock-skew tolerance.
- `ended_at`: if present, must be > `started_at`.
- `category_ids`: each must exist and belong to the user (unknown ids on entry write are pruned, not rejected — see above).
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
| `category_exists` | 409 | case-insensitive name collision on create; `details` carries the existing record |
| `duplicate_import` | 409 | `POST /entries` with a `(source, source_ref)` that already exists for the user (uniqueness constraint); the existing entry is kept as-is |
| `internal_error` | 500 | existing; never leaks cause |
| `invalid_body` / `unauthorized` / `rate_limited` | 400/401/429 | existing semantics |

No PII (notes content) is logged (S4); structured `log/slog` events use ids only.
