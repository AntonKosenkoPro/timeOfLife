# Tasks: push-404-resurrect

## 1. Resurrect-and-retry (SyncController drain path)

- [x] 1.1 Replace `convergeRelayDeleted` with `resurrectAndRetry` (+ `pushEntryWithHealedParent`, `healParentAndRetryEntry`, `repushRecordAsCreate`): single retry, original error rethrown, remap/conflict-resolver reuse, locally-missing clears rows.
- [x] 1.2 Pre-push stale-update guard (`isLocallyMissing`): updates for locally-missing records drop without pushing (remap leftovers, delete-superseded updates).
- [x] 1.3 Rewrite the 4 convergence tests to resurrection expectations (parent re-posted, records intact, rows empty, idle); new: parent-heal via remap, heal-failure loud, remap-leftover never pushed.

## 2. Verification and docs

- [x] 2.1 `swiftlint lint --strict` clean; warning-free build; full `xcodebuild test` green — 554/554 (backend untouched).
- [x] 2.2 FURPS F14 clause rewritten (resurrect-wins); `docs/project-context.md` sync-plane line; no OpenAPI/backend changes.
- [x] 2.3 `openspec validate --all` green; archive (REMOVED+ADDED on `sync-client`).
