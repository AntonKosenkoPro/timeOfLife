## Context

See proposal.md (Why) for motivation. Current state from two exploration sweeps: backend carries a create-then-drop migration chain with duplicate `004` numbers, an `adaptToSQLite` string-surgery layer, no `schema_migrations` table, and hardcoded OTP/TTL/timeout values; the Postgres/SQLite catalog is a ~1500-line mirror with a second-precision vs timestamptz skew. iOS carries 4 parallel `RecentEntry` shapes, triple timer idioms, twin editor chromes, 6 `file_length` suppressions, magic focus delays, a dead deferred-start machine, and `Theme`/`L10n` bypasses. Docs and 12 baseline specs still name the removed `activities` entity, the 30s wall-clock undo window, Enable Sync, and `By activity`. Load-bearing paths (RootView gate ordering, AppContainer open/close, config/migrations/middleware, SyncController merge matrix) lack tests. Constraints: LocalStore stays the single mutation chokepoint; no raw GRDB writes outside it; XcodeGen-managed (`project.yml` then regenerate); `Theme` semantic colors only; strings in both locales + `L10n`; OpenAPI is the authoritative contract; pre-release so on-disk shapes edit in place; one `xcodebuild` at a time.

## Goals / Non-Goals

**Goals:**
- Establish a safe order (docs-contract → backend → iOS → tests) so refactors pin to a true contract.
- Keep every slice behavior-preserving with a rollback that is a plain revert.
- Leave the tree greener than found: linters + both suites green at every slice boundary.

**Non-Goals:**
- No Postgres/SQLite engine unification (separate spike).
- No `LogTimeView` #57 split or full `SyncController` stage extraction beyond testability needs.
- No new endpoints, entities, dependencies, or user-visible copy changes beyond the wording sync.

## Decisions

- **Docs-contract first, code second.** Wording-only spec deltas + `AGENTS.md`/`config.yaml`/`README.md`/`project-context.md`/`Requirements`/`Design`/`openapi.yaml` prose land before code moves, so later slices have an unambiguous oracle. Alternative (code first) was rejected: it lets wording drift re-enter unnoticed.
- **Migration squash as delete + single clean schema (pre-release privilege).** Replace the `003`-creates/`007`-drops chain and duplicate `004`s with one sequential set plus a `schema_migrations` table; keep `adaptToSQLite` only as a tested, minimal dialect shim. Alternative (incremental renumber only) was rejected: it preserves the create-then-drop fiction and the every-boot re-apply fragility.
- **Thread config, don't centralize engines.** Pass `maxAttempts`/TTLs/timeouts via `config` into constructors/handlers; unify `Pool()`/`DB()` naming; share only pure helpers (cursor codec, limit clamp, nullable-time). Alternative (full query-builder/codegen now) was rejected as the engine-unification spike in disguise.
- **Unify iOS around single types, not new abstractions.** One `ExactName` type + mapper, one `FieldCard`/`EditorToolbar`/`DestructiveBottomButton`, one duration-formatter + `DynamicTypeMetrics`, one `FocusDelay`/ticker idiom. Alternative (generic card/framework) was rejected: the duplication is concrete and small; generics would add API surface for 3 call sites each.
- **Retire, don't shim.** Delete the deferred-start prod path, `waitForSyncShutdown` poll (publisher instead), `TrackLayoutSpike` from the app target, dead params/tokens, and `fatalError`/`try!` crash paths (surfaced errors). Alternative (deprecate-and-keep) was rejected: shims are how this debt grew.
- **Tests pin refactored behavior, not old.** New tests land after each slice's refactor (config/embed/middleware/uuid/cursor, gate/container/races/matrix, contract pins), and the brittle `allCasesCount == 148` becomes a sorted-keys snapshot. Alternative (tests-first for refactor) was rejected except where the spec deltas already define the oracle.

## Risks / Trade-offs

- [Migration squash touches the most sensitive files] → Mitigation: sequential renumber + tracking table in one commit, `go test ./...` with SQLite plus boot-idempotency test, review SQL line-by-line; rollback is revert.
- [Spec-delta wording could be read as behavior change] → Mitigation: deltas are explicitly wording-only (no SHALL changes to behavior); validate with `openspec validate --all --strict`.
- [iOS unification causes visual drift] → Mitigation: shared components extracted with identical tokens/padding; simulator smoke per slice; no screenshot-baseline changes expected.
- [New tests expose real bugs (time precision, CORS, SES fallback)] → Mitigation: file as follow-up behavior changes, do not smuggle fixes into this umbrella; note in tasks.
- [Single-writer contention (`openapi.yaml`, `project.yml`, `tasks.md`)] → Mitigation: serialize those edits; one `xcodebuild` at a time per `docs/ios-test-loop.md`.

## Migration Plan

1. Land spec deltas + docs/contract prose (validate green).
2. Land backend simplicity (build + `go test` + linters green).
3. Land iOS simplicity + dead-code retirement (swiftlint + build + tests green).
4. Land test-coverage additions (both suites green, coverage up, no behavior diff).
5. Update `docs/project-context.md` + archive the change. Rollback per slice is a plain revert (no migrations for shipped users pre-release).

## Open Questions

None — engine unification stays a separate future spike by design.
