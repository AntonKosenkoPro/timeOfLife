## 1. Store: undoable activity deletion

- [x] 1.1 Add `LocalStore.deleteActivityUndoable` (D1, D3): one write transaction that refuses with `.runBlocked` when `timer_state` targets the activity, else writes one undo-buffer row (activity record first, then one `entry` record per committed entry) and removes the activity, its join rows, and its entries; no outbox row. Add `activityDeletionSnapshot(bufferID:)` + `undoActivityDeletion(bufferID:)` decoders mirroring the entry/category pair.
- [x] 1.2 Add `LocalStoreActivityUndoTests`: snapshot contents (activity + assignments + all entries), atomicity, `.missing` for unknown id, `.runBlocked` leaves everything untouched and buffers nothing, undo restores identity/assignments/entries with no outbox row, expiry fanout enqueues activity + per-entry DELETE rows, supersession keeps newest only.
- [x] 1.3 Verify relay cascade assumption: confirm server `DELETE /activities/:id` behavior for entries (cascade vs not) and record the outcome in design D2; no code change expected either way (404-treats-as-success covers cascade).

## 2. Activity editor Delete

- [x] 2.1 Add bottom Delete (D5) to `ActivityEditorView` in edit mode only + scope confirmation alert (name + entry count + total duration + 30-second shake hint); wire `ActivityEditorViewModel.deleteConfirmed()` (`.deleted`/`.missing` → dismiss; `.failure`/`.runBlocked` → error banner, draft intact).
- [x] 2.2 Add `ActivityEditorViewModel` delete tests: blocked-while-running keeps draft with message, missing dismisses, failure keeps form open.
- [x] 2.3 Register activity-filtered system undo + foreground expiry reconciliation on both presenters (Track, History/Detail flow) per D7; Track selection clears and Detail sheet dismisses (existing D6) after delete; History drops the entries.

## 3. Category editor Delete + list simplification

- [x] 3.1 Add bottom Delete (D5) to `CategoryEditorView` in edit mode only, reusing the tag-only confirmation copy (reworded off the toast, D8); wire `CategoryEditorViewModel.deleteConfirmed()` via existing `deleteCategoryUndoable`; dismiss + list reload.
- [x] 3.2 Remove from `ManageCategoriesView`: row `swipeActions`, deletion `confirmationDialog`, `UndoToast` inset + countdown; swap active `ShakeCatcher`/`onShake` for the passive first-responder host + resource-filtered system prompt (D4).
- [x] 3.3 Strip `ManageCategoriesViewModel` toast/ticker/swipe plumbing per D6 (`UndoToastState`, ticker, `dismissUndo`/`expireUndo`, `confirmDelete`/`pendingDeletion`); keep `performUndo`, `commitExpiredUndo`, `registerSystemUndo` (category-filtered). Update `CategoryManagementViewModelTests`: swipe/toast tests removed, editor-delete + system-prompt + foreign-snapshot-ignored tests added.

## 4. Strings, theme, accessibility

- [x] 4.1 Add `activity.delete.*` keys (title, scope message, running-timer block message) to `en.lproj` + `ru.lproj` + `L10n` (U4); reword `delete.category.message` off the toast; reuse the existing Delete string for undo action names (D8). Confirm `LocalizationTests` `allCases` coverage.
- [x] 4.2 Verify Delete buttons use `Theme` semantic colors only, 44×44 targets, stable ids (`ActivityEditorDeleteButton`, `CategoryEditorDeleteButton`), VoiceOver labels.

## 5. Docs, requirements, verification (S5)

- [x] 5.1 Update `Design/` (`ActivityEditor`, `CategoryEditor`, `ManageCategories`, `INTERACTIONS` Undo flow) + `docs/project-context.md` (routing + "Incomplete / deferred": supersede the old destructive-activity-delete plan, note toast removal); re-check `Requirements/FURPS/*.md` rows for conflicts.
- [x] 5.2 Run `swiftlint lint --strict`, warning-as-error `xcodebuild` build, full iOS test suite green; `gofmt -l .` empty (no backend change expected). Archive the change only after all tasks verify.

## 6. Undo limit → app restart (follow-up; §§1–5 were completed under the original 30 s design)

- [x] 6.1 Remove the wall-clock window: drop `UndoBufferStore.window`/`isExpired`, replace `undoBufferCommitExpired` with `undoBufferCommitAll`, drop foreground reconciliation (`RootView`, `ManageCategoriesView`), commit all buffered rows once at cold launch (`RootView.task`); reword the three delete confirmations EN+RU ("until you restart the app").
- [x] 6.2 Rewrite expiry tests as restart tests (`LocalStoreTests`, `ActivityDetailViewModelTests`, `CategoryManagementViewModelTests`): old buffered rows stay restorable, `commitAll` fans out, superseded rows stay buffered, cold launch commits.
- [x] 6.3 Update delta specs (`activity-deletion`, `category-management`, `local-first-store`), `design.md` (D10), `proposal.md`; full suite + lint green.
