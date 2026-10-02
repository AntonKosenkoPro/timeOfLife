## 1. Ordering fix + spec touch

- [x] 1.1 Change `outboxRows` (`LocalStore.swift:1302-1308`) from `ORDER BY created_at, id` to `ORDER BY created_at, rowid`; keep outbox ids UUIDv4 (no migration) and resource priority (categories before entries) unchanged. Plus the required companion fix: `SyncController.orderedForDrain` re-sorted the snapshot in memory with an `id` tiebreak, which defeated the store ordering — tiebreak is now the snapshot index (insertion order).
- [x] 1.2 Update the `sync-client` delta spec drain-order line to the `rowid` tiebreak (`created_at, rowid` within each resource) with the same-tick insertion-order scenario.

## 2. Suite hardening + verification

- [x] 2.1 Harden `LocalStoreTests.updateCategory renames` and `SyncControllerTests.midCycleAccountChangeAborts` so same-tick rows assert deterministic insertion-order drain.
- [x] 2.2 Run repeated full-suite green for both suites (not single targeted runs; flake reproduces ~2/3 on pristine-tree full runs) per `docs/ios-test-loop.md` (one `xcodebuild` at a time); run `swiftlint lint --strict`.
- [x] 2.3 Re-check the relevant `Requirements/FURPS/*.md` rows, confirm backend `GetValidOTP ORDER BY created_at DESC` left untouched (out of scope), and run `openspec validate --change "fix-97-outbox-rowid-tiebreak" --all` (or `openspec validate --all` in the worktree) and resolve any findings.
