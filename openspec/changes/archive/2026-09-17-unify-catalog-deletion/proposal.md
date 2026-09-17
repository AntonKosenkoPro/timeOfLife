## Why

Catalog deletion is inconsistent: entries delete from their editing form with confirmation and shake-to-undo (`entry-editor`), while categories delete from the list via swipe (plus an `UndoToast`), and activities have no UI deletion at all (`LocalStore.deleteActivity` has no caller). One interaction grammar — Delete button in the editing form, confirmation, durable undo buffer, system Undo prompt — should cover all three, so users learn deletion once.

## What Changes

- `ActivityEditorView` (edit mode) gains a bottom destructive Delete button mirroring the entry form: confirmation alert naming the activity and its scope, `LocalStore.deleteActivityUndoable` into the durable undo buffer (no outbox row), editor dismisses, presenters reload/dismiss.
- `CategoryEditorView` (edit mode) gains the same bottom Delete button wired to the existing `LocalStore.deleteCategoryUndoable`; editor dismisses, Manage Categories reloads.
- Manage Categories list swipe-to-delete (and its confirmation dialog) is removed. The only way to delete a category is the editor's Delete button.
- Manage Categories `UndoToast` (countdown, ticker, immediate-restore shake) is removed. Category undo moves to the DEFAULT system Undo confirmation (shake → prompt → confirm restores one), identical to entries.
- New `LocalStore.deleteActivityUndoable`: snapshots the activity **plus all its committed entries** into the undo buffer in one transaction and removes them (no outbox row). Undo restores all; a cold launch commits whatever is still buffered via the generic fanout (one outbox DELETE per record; entry rows 404-tolerantly succeed when the relay cascades).
- Deleting the activity a timer is currently running against is blocked with a localized message (the running session has no entry row to snapshot and `timer_state` must never dangle).
- U7 supersession extends unchanged: only the most recent buffer row is restorable, filtered per surface by snapshot resource (`activity` / `entry` / `category`).

## Capabilities

### New Capabilities

- `activity-deletion`: deleting an activity from its editor with confirmation, cascade scope, undoable system-prompt restore, and presenter behavior. No baseline covers activity deletion UI today.

### Modified Capabilities

- `category-management`: deletion entry point moves from list swipe to the category editor's Delete button; undo moves from UndoToast + immediate shake to the system Undo confirmation; tag-only semantics (activities, entries, timer state untouched) unchanged.
- `local-first-store`: the durable undo buffer gains activity deletions — full snapshot (activity + entries), restorable until the app restarts (no wall-clock window; cold launch commits), no outbox while buffered; plus the running-timer delete block.

## Impact

- iOS only; no backend / OpenAPI change (outbox DELETE rows already exist for all three resources; redundant entry DELETEs resolve via the existing 404-treats-as-success rule).
- Touched: `ActivityEditorView(ViewModel)`, `CategoryEditorView(ViewModel)`, `ManageCategoriesView(ViewModel)`, Track + ActivityDetail presenters (shake registration, post-delete reload/dismiss), `LocalStore` (+1 method), `L10n` + EN/RU strings, Design docs (`ActivityEditor`, `CategoryEditor`, `ManageCategories`, `INTERACTIONS` Undo flow).
- Explicit non-goals: no delete affordance on the ActivityDetail sheet itself, History rows stay swipe-free, no UndoToast anywhere after this change, no change to the Track search restorable-deletion restore prompt, no `timer_state` snapshotting.
- Supersedes the old plan noted in `docs/project-context.md` ("destructive confirm, not undoable" activity deletion).
