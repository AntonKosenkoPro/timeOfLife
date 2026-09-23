# Tasks: propagate buffered deletions (Option A)

- [x] 1. `LocalStore`: add `undoBufferRows()` (list all buffer rows) and `undoBufferRemove(id:)` (drop one row); add in-flight flag plumbing (`undoPushInFlight`, checked by `undoBufferRestore` / `undoEntryDeletion` / `undoCategoryDeletion`, refusing with the existing persistence error while set)
- [x] 2. `SyncController`: add `pushBufferedDeletions()` step (tombstones → buffered pushes → drain → pull); per record `DELETE` via `remote`, 404 treated as success, other errors fail the cycle loudly; drop the buffer row only when all its records pushed; set/clear the in-flight flag around the loop
- [x] 3. `UndoBufferStore`: document the new commit trigger (next successful push; cold launch stays as backstop)
- [x] 4. Copy: update `entry.deleteMessage` + `delete.category.message` (en + ru) to the "until it syncs" window; no new `L10n` keys
- [x] 5. Tests: buffered entry delete pushed on cycle + buffer cleared; buffered category delete pushed; 404-on-buffered-push treated as success; push failure keeps the row buffered and undoable; in-flight undo refused; undo-before-push still clean (no relay traffic); offline cycle keeps buffer
- [x] 6. Verify: `swiftlint lint --strict`, `xcodebuild build`, `xcodebuild test`, `openspec validate --all`; live two-device check (delete on A → Sync now → tombstone on relay → B applies on next cycle)
