# Tasks: fix-delete-resurrection

## 1. Tombstone reads (LocalStore, no schema change)

- [x] 1.1 `hasPendingDelete(resource:recordID:)` — outbox `op = 'delete'` existence check.
- [x] 1.2 `isBufferedForDeletion(resource:recordID:)` — undo-buffer snapshot scan for the exact `(resource, recordID)` pair (covers entry ids inside activity snapshots).
- [x] 1.3 `isLocallyDeleted(resource:recordID:)` — combined guard used by sync.

## 2. Delete-wins in SyncController

- [x] 2.1 `applyServer(_ activity:serverCategories:)`, `applyServer(_ category:)`, `applyServer(_ entry:)` — early skip + secret-free log on tombstone hit.
- [x] 2.2 `adoptServerVersion` — skip the merge on tombstone hit (row still clears; queued DELETE converges the relay).

## 3. Regression coverage (SyncControllerTests fakes + temp store)

- [x] 3.1 First-sync with a pending activity DELETE: pull-first does not resurrect; DELETE pushes; outbox empties; idle.
- [x] 3.2 Buffered activity deletion + pull returning the relay copy: stays deleted, buffer stays restorable, idle.
- [x] 3.3 Buffered category deletion + full snapshot containing it: stays deleted, buffer stays restorable, idle.
- [x] 3.4 Buffered entry deletion + pull returning the relay copy: stays deleted, buffer stays restorable, idle.
- [x] 3.5 Update-conflict (409) with a superseding queued DELETE: no adoption resurrection; DELETE pushes; outbox empties; idle.

## 4. Verification and docs

- [x] 4.1 `swiftlint lint --strict` clean; warning-free build; full `xcodebuild test` green (backend untouched — no contract change).
- [x] 4.2 Re-check `Requirements/FURPS/Timetracking.md` F5–F8 + `Activity_Catalog_and_Categories.md` R2 for conflicts (expected: none — same LWW protocol; deletes already first-class in the outbox).
- [x] 4.3 Update `docs/project-context.md` sync-plane bullet (delete-wins line) + OpenSpec routing (this change); no OpenAPI changes.
- [x] 4.4 `openspec validate --all` green; archive this change after verification so the delta folds into the `sync-client` baseline.
