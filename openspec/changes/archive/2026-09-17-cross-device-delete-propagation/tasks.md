# Tasks: cross-device-delete-propagation

## 1. Relay tombstones (backend — owner: backend agent; `openapi.yaml` locked by lead first)

- [x] 1.1 Migration `006_tombstones.sql` (idempotent `IF NOT EXISTS`; `TIMESTAMPTZ` so the SQLite adapter maps it; explicit `deleted_at` from writers).
- [x] 1.2 `db.Tombstone` + `Store.ListDeletions` + SQLite/Postgres impls (`deleted_at > since`, ASC; nil/zero since = all; never null — return `[]`).
- [x] 1.3 Tombstone upsert in the three deletes (same tx, after the `ErrNotFound` check); activity cascade writes exactly one (activity) tombstone.
- [x] 1.4 Tombstone clear in the three creates (recreation path).
- [x] 1.5 Handler `ListDeletions` (`deleted_since` validated like `modified_since`, 422 on garbage) + `GET /deletions` route + `TestCatalogRoutesProtected` coverage.
- [x] 1.6 Tests: sqlite tombstone-on-delete × 3, since-filter, recreate-clears, double-delete keeps tombstone, cascade-exactly-one, user scoping; postgres parity per file convention; handler 422/empty/since tests; contract suite green.

## 2. Client tombstone apply (iOS — owner: iOS agent; against locked `openapi.yaml`)

- [x] 2.1 `Deletion` model + `DeletionWireDTO` (WireDate) + `CatalogSending.fetchDeletions(since:)` + path builder (`deleted_since`, mirror `activitiesPath`) + `MockCatalogRepository.deletionsResult`.
- [x] 2.2 `LocalStore.applyDeletionTombstone` per design (R1 keep-rule, cascade, drop create/update, keep deletes, no outbox).
- [x] 2.3 `SyncController`: `applyTombstones()` with the `deletions` cursor; cycle reorder (steady: tombstones → drain → pull; first: pull → tombstones → drain).
- [x] 2.4 Tests: `SyncControllerTests` (all six design scenarios incl. never-call-404-update-mock ordering proof) + `LocalStoreTests` for the apply rules.

## 3. Verification and docs (owner: lead)

- [x] 3.1 Backend: `gofmt -l .` empty, `go vet`, `golangci-lint run`, `go test ./...` green.
- [x] 3.2 iOS: `swiftlint lint --strict`, warning-free build, full `xcodebuild test` green (544 tests).
- [x] 3.3 FURPS Timetracking F-table gains the propagation row; re-check F5–F8 + catalog R2 (expected: additive, no conflicts).
- [x] 3.4 `docs/project-context.md` (sync plane + routing) + `Design/BACKEND/Activity_Catalog_API.md` (`deleted_since`, tombstone lifecycle) updates.
- [x] 3.5 `openspec validate --all` green; archive (folds into `sync-client` + `local-first-store` baselines; OpenAPI stays the relay contract).
