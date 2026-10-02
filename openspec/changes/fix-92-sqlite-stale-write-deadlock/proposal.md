## Why

`SQLiteStore.UpdateEntry` deterministically hangs on the stale-write path: the transaction holds the single pool connection (`sqlite.go:25 SetMaxOpenConns(1)`, test-only store) while the first stale branch re-reads through `s.db` (`getEntryRow` at `sqlite_catalog.go:666`), which blocks forever waiting for the held connection. Second-precision `fmtTime` (`"2006-01-02 15:04:05"`) makes this worse — two PATCHes in the same second spuriously hit the stale path, so a normal same-second edit hangs instead of returning 409. GitHub issue #92. `UpdateCategory` has the same shape and needs the twin fix; Postgres is unaffected (larger pool, already rollback-first pattern).

## What Changes

- **Rollback-first stale path (twin):** in `UpdateEntry`, roll back the tx before the `ErrNotFound` existence check (single rollback, then reads via the pool); apply the same shape to `UpdateCategory`. No behavior change for genuinely stale writes — still `ErrConflict` (409) with the current version.
- **Millisecond-precision SQLite timestamps:** `fmtTime` / `parseTime` / `fmtTimeArg` / `nullTimePtr` move to millisecond precision (e.g. `"2006-01-02 15:04:05.999"`), so same-second PATCHes compare correctly and only truly stale `updated_at` values conflict.
- **Regression tests:** same-second `UpdateEntry` completes (identical `updated_at` → 409 conflict, not hang) + same for `UpdateCategory`.
- Explicitly **out of scope**: Postgres changes (mirror already rollback-first); OpenAPI contract changes (409 semantics unchanged); iOS / sync-client logic changes.

## Capabilities

### New Capabilities

None — no new user-visible behavior is introduced.

### Modified Capabilities

- `sync-client`: LWW conflict resolution — stale entry/category updates return 409 with the current version (never hang); `updated_at` comparison is millisecond-precision so same-second writes are ordered correctly.

## Impact

- Code: `backend/internal/db/sqlite_catalog.go` (`UpdateEntry` ~:643-691, `UpdateCategory` ~:283-324, `fmtTime`/`parseTime`/`fmtTimeArg`/`nullTimePtr` ~:23-67); `backend/internal/db/*_test.go` regression tests.
- APIs: none — `PATCH /entries/{id}` / `PATCH /categories/{id}` keep 409 `conflict` semantics; same-second PATCH now deterministically returns 409 instead of hanging.
- Tests: `go test ./...` must stay green; new regression tests fail (hang/timeout) before the fix and pass after.
- Non-goals: no Postgres change; no on-disk migration (pre-release — timestamps reformat in place); no new dependencies.
