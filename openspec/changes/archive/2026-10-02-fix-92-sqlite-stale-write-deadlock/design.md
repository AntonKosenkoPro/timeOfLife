## Context

See `proposal.md` (Why) for motivation. Current state (`backend/internal/db/sqlite_catalog.go`):

- `UpdateEntry` (~:646-691) opens a tx holding the single pool conn (`sqlite.go:25 SetMaxOpenConns(1)`, test-only store; Postgres uses a real pool and is unaffected). On `affected == 0`, the FIRST stale branch at :666 calls `s.getEntryRow` through `s.db` while the tx is still open → deterministic hang (the pool has no free conn). The SECOND read at :676 (`s.GetEntry`) is already rollback-before-read (:673-676) — the first read is the bug.
- `UpdateCategory` (~:283-324) has the same shape (UPDATE-then-existence-check without a tx today) — twin scope per decision B.
- `fmtTime` / `parseTime` / `fmtTimeArg` / `nullTimePtr` (~:23-67) use `"2006-01-02 15:04:05"` (second precision), so a same-second PATCH compares equal and spuriously enters the stale path. Postgres mirror stores native `timestamptz` and already follows rollback-before-read on the second read.
- Constraint: pre-release, no backward compat for on-disk formats — timestamp strings may be reformatted in place.

## Goals / Non-Goals

**Goals:**
- Stale entry/category PATCHes on SQLite return 409 with the current version promptly, including the same-second (identical `updated_at`) case.
- `updated_at` comparisons distinguish writes within the same second (millisecond precision) on the SQLite path.

**Non-Goals:**
- No Postgres query change; no handler / OpenAPI / sync-client logic change (409 semantics already pinned).
- No SQLite WAL / busy-timeout / pool-size tuning — the single-conn pool stays; the fix is ordering, not concurrency.

## Decisions

- **Decision B: rollback-first, twin scope (entries AND categories).** In `UpdateEntry`, roll back the tx immediately on `affected == 0` before the `ErrNotFound` existence check (single rollback; the deferred `tx.Rollback()` becomes a no-op), then perform both reads via the pool. Apply the same ordering to `UpdateCategory` (twin). Alternatives considered: (a) entry-only fix — rejected, identical hang shape in categories; (b) reading via the tx instead of the pool — rejected, keeps the tx open longer and diverges from the Postgres mirror pattern.
- **Millisecond-precision SQLite timestamps (`fmtTime` / `parseTime` / `fmtTimeArg` / `nullTimePtr`).** Format `"2006-01-02 15:04:05.999"` (UTC, millisecond). `parseTime` / `nullTimePtr` accept both the old second-precision and the new millisecond strings (fallback parse) so pre-existing test rows still read; all writes use the new shape. Alternative (nanosecond / RFC3339) rejected — millisecond matches Go `time` truncation behavior on SQLite TEXT and keeps lexicographic `updated_at < ?` ordering correct.
- **Regression tests pin the hang, not just the value.** Same-second `UpdateEntry` with identical `updated_at` must complete with `ErrConflict` (with a timeout guard so a hang fails instead of blocking the suite); same for `UpdateCategory`. Genuinely-stale and not-found cases keep their existing assertions (no behavior change).

## Risks / Trade-offs

- [Risk] Old second-precision rows compare equal to new millisecond rows within the same second → Mitigation: one-time benign 409 on the first same-second edit after upgrade; writes immediately move to millisecond precision.
- [Risk] Double-rollback error paths (`defer Rollback` + explicit `Rollback`) → Mitigation: ignore explicit-rollback errors that only signal already-rolled-back; keep the deferred rollback as the safety net (mirrors existing :673-675 style).
- [Risk] Lexicographic vs temporal ordering of mixed-precision strings → Mitigation: both formats are fixed-width UTC prefixes (`"2006-01-02 15:04:05"` is a prefix of the millisecond form), so string `<` ordering stays chronological.

## Migration Plan

No migration: test-only SQLite store; Postgres untouched. Rollback is reverting the change — no data repair needed (timestamps remain parseable by both formats).

## Open Questions

None.
