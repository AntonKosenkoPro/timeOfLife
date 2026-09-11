## Context

Entry deletion is the established grammar (`LogTimeView.deleteSection` + `LogTimeViewModel.deleteConfirmed` → `LocalStore.deleteEntryUndoable` → dismiss → passive `ShakeFirstResponderHost` + cleared-then-single `registerSystemUndo` on the presenting sheet, no toast). Category deletion uses an older grammar (list swipe → `ManageCategoriesViewModel.deleteConfirmed` → `deleteCategoryUndoable` → `UndoToast` + active `ShakeCatcher` with immediate restore). Activity deletion has no UI; only the generic buffer machinery speaks `activity` (`pendingDeletionActivity` / `restorePendingDeletionActivity`, `applySnapshot`'s `activity` case). See `proposal.md` for motivation. Constraints from the repo: `LocalStore` is the single mutation chokepoint; no on-disk backward compat (pre-release); strings in EN+RU + `L10n`; `Theme` colors only; no backend/OpenAPI change.

## Goals / Non-Goals

**Goals:**

- One deletion grammar for entries, categories, activities: editor Delete button → confirm → buffer → dismiss → system Undo prompt.
- Activity undo restores the activity *with* its history (entries are part of the snapshot).
- Net code removal on the category surface (toast, ticker, swipe, active shake catcher).

**Non-Goals:**

- No new buffer/outbox machinery: reuse `DeletionSnapshot`, `applySnapshot`, generic commit fanout, 404-treats-as-success drain.
- No `undo_buffer` schema change; no data migration.
- No touch to `SyncController`, the relay, or OpenAPI.

## Decisions

**D1 — Activity snapshot = one `activity` record + one `entry` record per committed entry, activity first.**
`applySnapshot` already restores both resource types with `INSERT OR IGNORE`; ordering guarantees the parent exists before entries reference it. No new resource types, no skip-markers (contrast D2).

**D2 — Accept generic commit fanout (one outbox DELETE per snapshotted record).**
Alternative was a `category_associations`-style skip-marker so only the activity DELETE syncs. Rejected: fanout is correct whether or not the relay cascades activity deletes — cascaded entry rows resolve as 404 → success under the existing D5 rule; non-cascaded rows are genuinely needed. Zero new conventions, at the cost of N extra idempotent rows for large histories.
Verified (task 1.3): `DELETE /api/v1/activities/{id}` is a server-side cascading hard delete (`backend/internal/handlers/catalog.go` `DeleteActivity`), so in practice the per-entry DELETEs will 404 and succeed tolerantly.

**D3 — Running-timer block enforced at the store boundary.**
`deleteActivityUndoable` checks `timer_state` in the same write transaction and returns a distinct `.runBlocked` outcome when the timer runs against that activity; the editor stays open with a localized message. Alternative (UI-only check) races with a timer starting between check and write; alternative (snapshotting `timer_state`) smuggles cross-process runtime state into a data snapshot. The store is the only place that can make the check atomic.

**D4 — Category shake adopts the passive host + system prompt, entry-style.**
Replace Manage Categories' active `ShakeCatcher`/`onShake` (immediate restore) with the passive `ShakeFirstResponderHost` (holds focus, handles no motion, lets the OS show the prompt), cleared-then-single `registerSystemUndo` with `setActionName`, and a resource filter accepting only buffers holding a `category` record — mirroring `ActivityDetailViewModel.registerSystemUndo`, which filters for `entry` records. U7 supersession across surfaces falls out of the shared `undoBufferMostRecent` + per-surface filter.

**D5 — Editor Delete buttons mirror `LogTimeView.deleteSection`.**
Bottom-of-form destructive card, `Theme.danger`, stable ids (`ActivityEditorDeleteButton`, `CategoryEditorDeleteButton`), confirmation alerts; ViewModels gain `deleteConfirmed() async -> Bool` mirroring `LogTimeViewModel` (`.deleted`/`.missing` → dismiss; `.failure`/`.runBlocked` → error banner, form stays open). Delete appears in edit mode only (create mode has nothing to delete).

**D6 — `ManageCategoriesViewModel` keeps undo ownership minus the toast.**
`performUndo` and `registerSystemUndo` stay; `UndoToastState`, the ticker, `dismissUndo`/`expireUndo` toast paths, `confirmDelete`/`pendingDeletion` swipe plumbing, and the list `swipeActions` + `confirmationDialog` go. Deletion itself moves into `CategoryEditorViewModel` (edit mode) via the existing `deleteCategoryUndoable`.

**D7 — Shake registration follows the deletion, per presenter.**
Activity deletes originate from two presenters (Track refine editor, Detail "Edit activity" editor); each presenting surface registers an activity-filtered system undo after the editor dismisses — the entry pattern, parameterized by resource. The detail sheet itself keeps its entry-only filter: after its activity is deleted the sheet dismisses (existing D6), so it must never offer to restore an activity it no longer shows. Track gains its first shake registration (no precedent there — follow the detail pattern).

**D8 — Copy reuses the entry trick.**
New `activity.delete.*` keys (title, scope message with name + count + total, running-timer block message) in EN+RU; category and entry messages share the until-restart shake phrasing; the undo action name reuses the existing localized Delete string so no new strings are needed for the prompt (U4, as entries do).

**D9 — Hard `deleteActivity` stays.**
The immediate (non-undoable) delete remains for test setup/teardown; the UI never calls it. No dead production path is introduced — the old planned "destructive, not undoable" UI simply never gets built.

**D10 — No wall-clock undo window; an app restart is the limit.**
Buffered deletions stay restorable for as long as the process lives (foreground/background cycles expire nothing); a cold launch commits everything still buffered. Motivation: the 30 s window expired before users found the shake gesture on device, silently destroying data. Alternatives were a longer window (still silent, still arbitrary) and an explicit on-screen Undo button (larger scope). The shared `UndoBufferStore` machinery means the restart limit applies uniformly to activity, category, and entry deletions. `BufferEntry.isExpired` / the `window` constant / foreground reconciliation are removed; `commitAll()` runs once at cold launch in `RootView.task`.

## Risks / Trade-offs

- [Risk] A surface restores a foreign resource (e.g. History shake resurrects a category) → Mitigation: resource filter in every `registerSystemUndo`/`performUndo`, one test per surface asserting foreign snapshots are ignored.
- [Risk] Expiry fanout writes N outbox rows for entry-rich activities → Mitigation: rows are tiny, idempotent, and 404-tolerant; accepted in D2. A bulk-delete cap remains deferred as before.
- [Risk] Shake discoverability drops without the toast → Mitigation: confirmation copy teaches the gesture ("shake to undo until you restart the app"), same as entries today.
- [Risk] Track shake registration has no precedent and could double-register with the search restore prompt → Mitigation: cleared-then-single registration; the search `restorableDeletion` prompt is a name-matched restore path, independent of the buffer-most-recent undo — tests cover both coexisting.

## Migration Plan

No migration: `undo_buffer` schema and `DeletionSnapshot` shape are unchanged (multi-record payloads already exist). Deploy with the app; in-flight category buffers from the old build restore through the same rows under the new prompt. Rollback is a clean revert — buffered rows remain valid for the old code. After archive, update `docs/project-context.md` (routing + "Incomplete / deferred": drop the old destructive-activity-delete plan, note toast removal) and the `Design/` screen/interaction docs.
