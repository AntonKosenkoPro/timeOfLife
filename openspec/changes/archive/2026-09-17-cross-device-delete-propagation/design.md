# Design: cross-device-delete-propagation

## Context and composition with fix-delete-resurrection

Yesterday's guard (pull-merge skips locally-deleted ids) covers the **pre-convergence window**: buffered deletions (no relay trace exists by design — undo must stay invisible) and pull-first cycles (the DELETE hasn't been pushed yet, so no tombstone exists). Tombstones cover everything after the drain pushes the DELETE. Both stay; neither subsumes the other.

## Relay contract (authoritative: `backend/api/openapi.yaml`, v1.4.0)

### Migration `006_tombstones.sql`

```sql
-- 006: Deletion tombstones (cross-device delete propagation). Every hard
-- DELETE of an activity, category, or entry upserts one row; recreating an id
-- clears it. No GC yet (rows are tiny; deleted_at enables future GC).
-- Idempotent (re-applied on every start): IF NOT EXISTS throughout.
CREATE TABLE IF NOT EXISTS tombstones (
    user_id TEXT NOT NULL,
    resource TEXT NOT NULL,
    record_id TEXT NOT NULL,
    deleted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, resource, record_id)
);
CREATE INDEX IF NOT EXISTS idx_tombstones_user_deleted
    ON tombstones(user_id, deleted_at);
```

`resource` is one of `activity | category | entry` (mirrors the client's outbox resource strings). Writers always pass `deleted_at` explicitly (`time.Now().UTC()`); the DEFAULT is a backstop only.

### Store (interface + SQLite + Postgres, same tx as the mutation)

```go
// Tombstone records a hard delete that other devices must apply.
type Tombstone struct {
    Resource  string    `json:"resource"`
    ID        string    `json:"id"`
    DeletedAt time.Time `json:"deleted_at"`
}

// ListDeletions returns the user's tombstones with deleted_at > since
// (nil/zero = all), ordered by deleted_at ASC.
ListDeletions(ctx context.Context, userID string, since *time.Time) ([]Tombstone, error)
```

- `DeleteActivity`: in the existing tx, after the `affected == 0 → ErrNotFound` check, upsert
  `INSERT INTO tombstones (user_id, resource, record_id, deleted_at) VALUES (…,'activity',…,…) ON CONFLICT (user_id, resource, record_id) DO UPDATE SET deleted_at = excluded.deleted_at`.
  Cascade-deleted entries get **no** tombstones (the client's apply cascades — one row per user intent).
- `DeleteCategory` / `DeleteEntry`: same, with `'category'` / `'entry'`.
- `CreateActivity` / `CreateCategory` / `CreateEntry`: on the isNew path (and harmlessly on replay),
  `DELETE FROM tombstones WHERE user_id = ? AND resource = ? AND record_id = ?` so a recreation
  never meets its own stale tombstone. No new transactions — follow each method's existing shape
  (ordered exec where no tx exists; crash-window races are covered by client rule R1 below).
- SQLite uses `?` placeholders + `fmtTime`, Postgres `$n` + native times (mirror the neighboring methods).
- JSON: `deleted_at` formats RFC 3339 Nano UTC (same as `versionDetails`).

### Endpoint

`GET /api/v1/deletions?deleted_since=<RFC3339>` → `200` bare array (mirror `ListCategories`' nil→`[]`
rule so the client never decodes null). Absent/empty = full list. Garbage → `422`
`deleted_since must be a valid RFC 3339 timestamp` (mirror `modified_since` handling via
`parseRFC3339` + `validationErrs`). Bearer-protected like every catalog route (add to
`TestCatalogRoutesProtected` if it enumerates paths). Register `r.Get("/deletions", h.ListDeletions)`
in `server.go` beside the catalog routes. OpenAPI: `operationId: listDeletions`, tag `Sync`,
schema `Deletion{resource(enum), id(uuid), deleted_at(date-time)}`.

## Client contract

### Fetch (`CatalogSending`)

```swift
/// `GET /deletions?deleted_since=` — full list when `since` is nil.
func fetchDeletions(since: Date?) async throws -> [Deletion]
```

`Deletion{resource: String, id: String, deletedAt: Date}` + `DeletionWireDTO` decoded via
`WireDate` (same pattern as `EntryWireDTO`); path builder mirrors `activitiesPath` with
`deleted_since`. Mock gains `deletionsResult` + call logging (mirror `fetchedModifiedSince`).

### Apply (`LocalStore.applyDeletionTombstone`)

One write tx per call site batch (the whole deletions list in a single `dbQueue.write` is
preferred; reuse the file's private static helpers — `fetchActivity`, `entry(from:)`, outbox
deletes by `(resource, record_id, op)`):

- **activity `id`**: collect its entry ids first. If a local row exists, is clean (no pending
  create/update outbox row for the id), and `updatedAt > deletedAt` → keep it (R1: stale tombstone,
  the recreation already won). Else delete entries + joins + row with **no outbox row**, and drop
  pending **create/update** (not delete) outbox rows for the activity id **and** its entry ids.
- **entry `id`**: same R1 check single-row; delete with no outbox; drop its pending create/update rows.
- **category `id`**: same R1 check; delete joins + row with no outbox; drop its pending create/update rows.
  (Snapshot reconciliation stays untouched as backstop.)

Rules: pending DELETE rows are left alone (drain converges them via existing 404-as-success);
delete-wins over concurrent offline edits is deliberate and documented (single-user relay: a delete
is an explicit intent; tombstones carry `deleted_at` so a future LWW-resurrect policy needs no migration).
Timer state pointing at a tombstoned activity is left as-is (known limitation, follow-up).

### Cycle (`SyncController`)

Every cycle applies tombstones **before** draining (this ordering is what un-wedges the
404-on-update trap: the stale update row is dropped pre-drain):

- steady (`syncNow`/`trigger`): `applyTombstones()` → `drainOutbox()` → `pull(modifiedSince: nil)`
- first (`activate`): `pull(modifiedSince: nil)` → `applyTombstones()` → `drainOutbox()`
  (pull stays first so relay ids still arrive before local pushes; yesterday's guard covers the window)

`applyTombstones()`: cursor = `store.lastSyncedAt(resource: "deletions")`; fetch; apply each in
server order; advance the cursor to max `deletedAt` only when non-empty (mirror the existing
no-change-keeps-cursor convention).

## Verification (shared)

- Backend: `gofmt -l .` empty, `go vet`, `golangci-lint run`, `go test ./...` — new sqlite tests
  (tombstone on all three deletes; since-filter; recreate clears; double-delete keeps tombstone;
  cascade writes exactly one; user scoping) + postgres parity (`postgres_parity_test.go` pattern;
  runs only with a DB — follow the file's existing skip convention) + handler tests (422 garbage,
  200 `[]` empty, since passthrough) + openapi contract still green.
- iOS: `swiftlint lint --strict`, warning-free build, full `xcodebuild test` — new
  `SyncControllerTests` (activity/entry/category converge with no outbox + cursor advance;
  R1 stale tombstone keeps clean newer row; pending update dropped pre-drain so a 404-throwing
  update mock is never called and the cycle stays idle; empty list keeps cursor; unknown id no-op;
  tombstones-before-drain ordering) + `LocalStoreTests` for the apply rules.
- `openspec validate --all`; FURPS Timetracking F-table gains the propagation row; no other
  requirement conflicts (same outbox/LWW protocol, hardened).
