## Why

Entry delete enters the durable undo buffer (`LocalStore.deleteEntryUndoable`) but no surface ever registers it with the system Undo manager, so shake-to-undo after an entry delete does nothing (issue #87). Category delete is already wired on Manage Categories; History needs the same wiring for entry-owned snapshots.

## What Changes

- HistoryView hosts `ShakeFirstResponderHost` with the environment undo manager (mirror of `ManageCategoriesView.swift:116`).
- New `HistoryViewModel.registerSystemUndo` for ENTRY snapshots only: clear-then-single-register of the newest entry-owned buffer row, with the in-flight-push guard (mirror of `ManageCategoriesViewModel.swift:73-110`).
- Entry form behavior unchanged: `LogTimeView.deleteEntry` still dismisses after `deleteConfirmed`; History reloads via the existing invalidate path and offers restore through the DEFAULT system Undo prompt only — no UndoToast, no custom UI.
- Proof test: `undoCategoryDeletion` restores `entry_categories` joins (unassignment revert), locking the category-undo join-restore contract this surface relies on.
- Per-owner supersession (U7) is kept: each surface restores only its own newest snapshot; a category-newest buffer offers nothing on History and vice versa.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `history-entry-list`: History offers restore of the most recent entry deletion through the DEFAULT system Undo confirmation (shake → prompt → confirm), entry-owned snapshots only, per-owner supersession kept.

## Impact

- Affected code: `HistoryView.swift`, `HistoryViewModel.swift` (new `registerSystemUndo`/`performUndo` mirroring the category pattern), `LocalStore.entryDeletionSnapshot`/`undoEntryDeletion` gain their first UI caller; `LogTimeViewModel.deleteConfirmed` path unchanged.
- Authoritative docs: `openspec/specs/history-entry-list/spec.md`, `openspec/specs/entry-editor/spec.md` ("Entry delete needs confirmation and enters the undo buffer"), `openspec/specs/local-first-store/spec.md` ("Durable undo buffer", U7 supersession + in-flight guard), `openspec/specs/category-management/spec.md` (category pattern reference).
- Non-goals: no UndoToast on any surface; no change to the undo buffer lifetime (restart-or-push commit), supersession, or in-flight-guard semantics; no entry-form UI changes; no new localized strings (reuse existing Delete confirm string for the action name, U4); no swipe/long-press actions on History rows.
