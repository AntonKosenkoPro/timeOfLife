## 1. Red tests (write first, all must fail before the fix)

- [x] 1.1 Client: 409 `category_exists` with empty-string winner id performs no `fetchCategory` call, keeps the outbox row queued, and surfaces a collision diagnostic (SyncControllerTests, mock remote).
- [x] 1.2 Client: 409 `category_exists` with missing winner id behaves identically to 1.1.
- [x] 1.3 Client: account-switch adoption mints fresh ids — adopted categories/entries land under new ids with names/texts/icons/notes preserved, entry payloads reference the fresh category ids, stale update rows for old ids are dropped, delete rows are preserved (LocalStoreTests + SyncControllerTests).
- [x] 1.4 Client: entry `duplicate_import` + `GET` returning `not_found` self-heals to a fresh id and lands; `duplicate_import` + `GET` returning matching import keys still clears silently (SyncControllerTests).
- [x] 1.5 Backend: cross-user id `POST /categories` returns 409 with nil details (no empty strings); cross-user id `POST /entries` is covered by the disambiguation contract — pin current mapping in a test first (sqlite + postgres parity, `catalog_test.go` style).

## 2. Backend honesty valve

- [x] 2.1 `CreateCategory`/`CreateEntry` winner-details: emit nil (not `{"id":"","name":""}`) when the post-violation winner lookup misses.
- [x] 2.2 Document the nil-details unresolvable-collision form on the 409 responses in `backend/api/openapi.yaml` (S10).
- [x] 2.3 `go test ./... -cover`, `gofmt -l .`, `go vet ./...`, `golangci-lint run` green.

## 3. Client implementation (LocalStore stays the single chokepoint)

- [x] 3.1 LocalStore: switch-time adoption clones under fresh ids (categories + entries, entry refs rewritten, stale updates dropped, deletes preserved) in chokepoint transactions.
- [x] 3.2 SyncController: drain self-heal — rewrite stuck row in place to a fresh id, remap local joins/payloads, retry once, adopt landed row; empty/missing winner id never fetched (clear diagnostic, row kept).
- [x] 3.3 SyncController: entry `duplicate_import` disambiguation via single `GET` (rare-path only), wired to the same self-heal.
- [x] 3.4 `swiftlint lint --strict` clean; `xcodebuild` build + full `SyncControllerTests`/`LocalStoreTests` green (1.x tests now pass).

## 4. End-to-end verification (the original repro, no guessing)

- [x] 4.1 Local relay repro: fresh backend + postgres, seed user-A starters, switch-account adoption to user B, colliding POST now self-heals to 201s; sync reaches idle with matching local/relay state (use the curl recipe from the investigation: OTP-console → token → seed → collide → observe).
- [x] 4.2 Re-check `Requirements/FURPS/*.md` sync rows; update `docs/project-context.md` (sync plane) if behavior text changed.
- [x] 4.3 Corner sweep with tests: switch-back-to-OTP (ids stay per-account, no cross-talk); populated-409 remap path untouched (existing tests green); buffered/pending-delete refs to old ids converge via 404-as-success; same-account cycles byte-identical behavior (existing snapshot/tombstone tests green).

## 5. Summary and archive offer

- [x] 5.1 Summarize evidence → fix → verification for the human and offer `openspec archive fix-cross-account-id-collision` (do not archive unasked).
