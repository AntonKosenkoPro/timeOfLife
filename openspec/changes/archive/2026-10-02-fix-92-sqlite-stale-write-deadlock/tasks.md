## 1. Rollback-first stale path (twin)

- [x] 1.1 `UpdateEntry`: roll back the tx before the `ErrNotFound` existence check (single rollback, then pool reads); keep genuinely-stale → `ErrConflict` with fresh version and not-found → `ErrNotFound`
- [x] 1.2 `UpdateCategory`: apply the same rollback-before-read ordering to the twin stale path
- [x] 1.3 Verify no remaining `s.db` / `s.Get*` reads hold the tx open on either stale path (deferred rollback stays as no-op safety net)

## 2. Millisecond-precision SQLite timestamps

- [x] 2.1 Move `fmtTime` / `fmtTimeArg` to millisecond-precision UTC strings; keep lexicographic `updated_at < ?` ordering
- [x] 2.2 Make `parseTime` / `nullTimePtr` accept both legacy second-precision and new millisecond strings (fallback parse + warn-on-unparseable preserved)

## 3. Regression tests + verify

- [x] 3.1 Add same-second `UpdateEntry` regression test: identical `updated_at` completes promptly with `ErrConflict` (timeout-guarded so a hang fails, not blocks)
- [x] 3.2 Add same-second `UpdateCategory` regression test with the same guard
- [x] 3.3 Verify: `gofmt -l .` empty, `go vet ./...`, `go test ./... -cover` green; confirm same-second PATCH acceptance (409, not hang) and no behavior change for genuinely stale writes
