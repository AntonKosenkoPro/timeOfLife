# Backend Test Framework

Test framework: **Go test (built-in)** — `*_test.go` alongside source (Go convention), SQLite in-memory for unit/API tests, PostgreSQL for parity tests, executable OpenAPI contract fixtures.

## Quick Start

```bash
go test ./...            # full suite (SQLite only; no Docker needed)
go test ./... -race      # race detector (matches CI)
make test                # go test ./... -cover
make test:race           # go test ./... -race
make test:cover          # coverage profile + per-function report
make test:pg             # PostgreSQL parity tests (needs Docker)
```

`make test:pg` starts `postgres:15-alpine` via `docker-compose.yml`, applies the real embedded migrations, and runs `backend/internal/db/postgres_parity_test.go` against it. The parity suite skips itself when `TEST_PG_DSN` is unset, so `go test ./...` stays green offline.

## Architecture

| Piece | Location | Purpose |
|---|---|---|
| Unit + API tests | `internal/*/*_test.go` | Logic + handler tests over an in-memory SQLite store (no Docker) |
| OpenAPI contract gate | `internal/contract/openapi_test.go` | Executable contract fixtures pinning `api/openapi.yaml` to documented invariants (R-006) |
| PostgreSQL parity | `internal/db/postgres_parity_test.go` | Same critical catalog semantics against real PostgreSQL (R-007) |
| Factories | `internal/handlers/catalog_helpers_test.go`, `catalog_factories_test.go` | Deterministic seeding: `newActivity`, `newActivityWithEntries`, `twoUsers` |
| Handler harness | `catalogRouter`, `serve`, `mintBearer`, `jsonReq`, `decodeBody`, `errCode` | Real chi routing + auth + handlers without a network socket |

## Best Practices

- **Factories over hand-rolled bodies** — seed state with `newActivityWithEntries(t, h, tok, n)` / `twoUsers(t, store)`; overrides keep intent explicit.
- **SQLite everywhere possible** — the parity suite is the only Postgres-dependent piece and is `TEST_PG_DSN`-gated.
- **Contract discipline** — the OpenAPI spec is authoritative (S10). If a handler emits a new error code or a path changes, update `api/openapi.yaml` **and** the `canonicalErrorCodes`/`bearerProtectedPaths` lists in `internal/contract/openapi_test.go` together; the gate fails otherwise.
- **Deterministic time** — entries use fixed UTC anchors; avoid `time.Now()` in seeds and assertions.
- **Ownership checks** — cross-user tests use the `twoUsers` factory (user A's resources must 404 for user B).

## CI Integration

`.github/workflows/backend.yml` runs `gofmt`, `go vet`, `golangci-lint`, and `go test ./... -race -coverprofile` on every PR (Requirements S6). The OpenAPI contract gate and SQLite suites run there with no Docker. PostgreSQL parity is scheduled/nightly scope per the test design (`test-design-epic-1.md`), run via `make test:pg`.

## Troubleshooting

- **Parity tests skip** — `TEST_PG_DSN` unset; run `make test:pg` (starts Docker Postgres) or point `TEST_PG_DSN` at a reachable database.
- **Contract gate fails** — a handler/spec drifted; align `api/openapi.yaml` and the contract lists per Best Practices.
- **Lint `unused` on a factory** — factories exist for upcoming ATDD/automation tests; a sample test in `catalog_factories_test.go` keeps them referenced. Delete a factory together with its last usage.

## Knowledge Base References

- `.agents/skills/bmad-testarch-framework/resources/knowledge/contract-testing.md` (R-006 gate rationale)
- `.agents/skills/bmad-testarch-framework/resources/knowledge/data-factories.md` (factory patterns)
- `.agents/skills/bmad-testarch-framework/resources/knowledge/fixture-architecture.md` (seeding strategy)
- `.agents/skills/bmad-testarch-framework/resources/knowledge/test-quality.md` (determinism, isolation)
