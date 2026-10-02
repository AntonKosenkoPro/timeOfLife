## Context

See `proposal.md` (Why) for motivation. Current state: `LocalStore.outboxRows()` (`LocalStore.swift:1302-1308`) reads `SELECT * FROM outbox ORDER BY created_at, id`; outbox ids are random UUIDv4 (`UUID().uuidString` at enqueue, `Date()` tick), so same-tick rows have random order. The `sync-client` baseline pins `created_at, id` within each resource (categories before entries). Record IDs already use time-ordered UUIDv7 as precedent, but outbox ids stay v4 to avoid a migration.

Constraints from `docs/project-context.md`: LocalStore is the single mutation chokepoint (GRDB in the App Group) — the ordering fix lives there; no backward compat for on-disk formats (pre-release) — no migration needed; test loop per `docs/ios-test-loop.md` (single writer, one `xcodebuild` at a time).

## Goals / Non-Goals

**Goals:**

- Deterministic drain for same-tick rows via insertion order, with the two named suites green across repeated full runs.
- Keep resource priority (categories before entries) unchanged; spec line matches the implementation.

**Non-Goals:**

- Migrating outbox ids to UUIDv7; touching backend `GetValidOTP ORDER BY created_at DESC` (same class, out of scope); any drain concurrency or retry-semantics change.

## Decisions

- **`ORDER BY created_at, rowid` (decision A from the issue).** Rationale: `rowid` is the SQLite insertion sequence, giving a total deterministic order for equal `created_at` without new columns or id-format changes; the store is GRDB/SQLite-only so the `rowid`-ism is contained. Alternatives considered: (a) switch outbox ids to UUIDv7 — rejected, requires migration/backfill for zero extra benefit over `rowid`; (b) keep `id` tiebreak and harden tests to be order-insensitive — rejected, leaves the production nondeterminism in place and weakens the suites.
- **Harden the two named suites to repeated full-run green rather than single-pass.** Rationale: the flake reproduces ~2/3 on pristine-tree full runs, so one green run proves nothing; repeated full runs are the acceptance signal. Alternative (single targeted test run) rejected as insufficient.
- **Spec touch updates only the tiebreak token (`id` → `rowid`) plus a same-tick scenario.** Rationale: minimal delta, same requirement header, full block preserved for clean archive. Alternative (rewrite drain requirements) rejected as scope creep.
- **No ctx7 fetch.** No new external API is used — `rowid` ordering is a property of the already-pinned SQLite-backed GRDB store, not a new library integration; nothing to cite.

## Risks / Trade-offs

- [Risk] `rowid` reuse after row deletion (`VACUUM`/reuse semantics) surprises future readers → Mitigation: outbox rows are short-lived queue entries (insert → drain → delete); `rowid` is only an intra-queue tiebreak, never a stable identity.
- [Risk] Future non-SQLite store would not have `rowid` → Mitigation: store is explicitly SQLite-only (GRDB); the spec scenario phrases it as "insertion order" with `rowid` as the mechanism, so a port can substitute its own sequence.
- [Risk] Hardening masks a different flake → Mitigation: repeated full-run verification of the two named suites (not targeted single-test runs) before claiming green.

## Migration Plan

No migration: one `ORDER BY` token change, no schema or id-format change. Rollback is reverting the token and the spec line.
