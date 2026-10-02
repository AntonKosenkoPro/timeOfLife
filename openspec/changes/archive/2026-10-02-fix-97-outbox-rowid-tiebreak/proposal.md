## Why

Outbox drain order is nondeterministic for same-tick rows: `outboxRows` orders by `created_at, id`, but outbox ids are random UUIDv4 (`UUID().uuidString`, `Date()` tick), so rows created within the same tick drain coin-flip. This flakes `LocalStoreTests.updateCategory renames` and `SyncControllerTests.midCycleAccountChangeAborts` (~2/3 on a pristine tree). Issue #97 resolves this with a `rowid` tiebreak plus suite hardening and a spec touch.

## What Changes

- Change the outbox read order from `ORDER BY created_at, id` to `ORDER BY created_at, rowid` (insertion order; the store is GRDB/SQLite-only so the `rowid`-ism is fine). Outbox ids stay UUIDv4 — no migration (unlike record IDs, which already use time-ordered UUIDv7 as precedent).
- Harden the two named suites (`LocalStoreTests.updateCategory renames`, `SyncControllerTests.midCycleAccountChangeAborts`) to repeated full-run green.
- Update the `sync-client` drain-order line to the `rowid` tiebreak (categories before entries, then `created_at, rowid` within each resource).

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `sync-client`: dependency-ordered outbox drain tiebreak changes from `created_at, id` to `created_at, rowid` within each resource.

## Impact

- Code: `LocalStore.swift:1302-1308 outboxRows` ordering only; no schema, migration, or outbox-id format change.
- Tests: `LocalStoreTests.swift` (update renames), `SyncControllerTests.swift` (mid-cycle abort); repeated full-run verification.
- Spec: `openspec/specs/sync-client/spec.md` drain-order line via this change's delta.
- Non-goals: changing outbox ids to UUIDv7; touching the same-class backend `GetValidOTP ORDER BY created_at DESC LIMIT 1` (out of scope); any drain resource priority change (categories-before-entries stays). No ctx7 external-docs fetch: SQLite `rowid` insertion-order semantics via the already-pinned GRDB/SQLite-only store, no new external API surface.
