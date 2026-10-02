## 1. History shake-to-undo wiring

- [x] 1.1 Add `UndoBufferStore` dependency plus `registerSystemUndo`/`performUndo` to `HistoryViewModel` (entry-owned snapshots only, clear-then-single, in-flight guard surfaces persistence error; mirror `ManageCategoriesViewModel:73-110`)
- [x] 1.2 Host `ShakeFirstResponderHost` in `HistoryView` with `@Environment(\.undoManager)`; call `registerSystemUndo` on appear/reload and after entry-form dismiss (reload-then-register ordering)
- [x] 1.3 Verify entry form still dismisses after `deleteConfirmed` with no form-side registration or toast

## 2. Regression tests

- [x] 2.1 Add proof test: `undoCategoryDeletion` restores `entry_categories` joins (delete assigned category → undo → joins back)
- [x] 2.2 Add per-owner tests: entry-newest buffer offers nothing to the category path (`categoryDeletionSnapshot` nil) and category-newest buffer offers nothing to the entry path (`entryDeletionSnapshot` nil)
- [x] 2.3 Add HistoryViewModel test: `registerSystemUndo` registers only for entry-owned newest row; `performUndo` restores entry with ordered categories and refreshes day groups

## 3. Verification and docs

- [x] 3.1 Run `swiftlint lint --strict`, warning-as-error build, and the iOS test suite per `docs/ios-test-loop.md`
- [x] 3.2 Re-check `Requirements/FURPS` entry/category rows for conflicts
- [ ] 3.3 Manual shake verification on simulator: entry delete → History shake → system prompt restores; category-newest → History shake offers nothing (and vice versa)
