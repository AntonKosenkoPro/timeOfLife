## Why

History → ActivityDetail is a read-only dead end: entries cannot be corrected or removed, and ActivityDetail rows are inert by spec. The history-roadmap's step 2 (EntryDetail + EntryEditor) is the sequencing-lean next task, but exploration settled on a simpler shape — no separate read-first detail: a tap opens the same entry form used for creation, directly editable. This unblocks entry correction and entry deletion (both long-deferred) in one change.

## What Changes

- ActivityDetail entry rows become tappable and open the unified entry form as a full-screen cover (not another stacked sheet):
  - `manual` entries open in EDIT mode: prefilled Activity + Starts/Ends (Calendar grammar reused from Log Time), Save via `updateEntry`, bottom-of-page Delete.
  - Non-`manual` (imported) entries open in LOCKED mode: all mutation controls disabled, Save hidden, Delete enabled, with a read-only provenance note explaining editing is disabled to avoid conflicts with the external source.
- The Log Time sheet grows into the unified entry form with three modes (CREATE = today's behavior unchanged; EDIT; LOCKED) sharing one Calendar-grammar layout, one validity gate, and the shared activity picker.
- Delete (both manual and imported): bottom-of-page destructive button → destructive confirm alert → enters the durable undo buffer (`UndoBufferStore.enter`, no outbox row) → dismisses the form → ActivityDetail and History reload. No UndoToast in this change; undo is via the shake gesture (`.onShake` / `ShakeHostingController` + `UndoManager` registration, mirroring Manage Categories) within the 30 s wall-clock window; expiry commits on foreground via the existing global reconciliation.
- ActivityDetail lists committed entries only (`endedAt != nil`); in-progress sessions never appear there and never contribute to its totals (totals already exclude NULL durations — restated and tested).
- **BREAKING (spec-level)**: modifies the activity-detail-sheet "rows SHALL NOT respond to taps" requirement and the history-entry-list "tap inside the detail sheet does nothing" requirement.

Non-goals: History swipe-to-delete (stays deferred to history-roadmap §8); History filtering (§5); UndoToast UI (deferred, §8 adds UI onto the buffer semantics shipped here); dirty-draft-back protection; activity-scope deletion (`delete-activity` stays a separate planned change); any backend / OpenAPI change (store methods used already exist); running-session-in-History (§7).

## Capabilities

### New Capabilities

- `entry-editor`: unified entry form (CREATE / EDIT / LOCKED modes), edit save via LWW `updateEntry` with stale handling, delete-with-confirm into the durable undo buffer with shake-to-undo and no toast, locked-mode rules for imported entries.

### Modified Capabilities

- `activity-detail-sheet`: entry rows become tappable (MODIFIES inert-rows requirement); entry list is committed-only (MODIFIES full-history requirement); sheet reloads identity/entries/total after the entry form's save/delete; entry form presents as a full-screen cover.
- `history-entry-list`: tapping an entry row inside the activity detail sheet now opens the entry form (MODIFIES tap-inside-detail-does-nothing); the History list reflects entry edits/deletes via the existing invalidate/reload chain.
- `manual-entry`: the Log Time sheet becomes the CREATE mode of the unified entry form (create behavior unchanged; gains EDIT and LOCKED modes plus the edit-only Delete button and mode-specific titles/copy).

## Impact

- iOS only (`Features/ActivityDetail`, `Features/ManualEntry` form + VM, `ActivityDetailViewModel` committed-only filter + `performUndo`, shake wiring on the detail surface, `L10n` + EN/RU strings, reload chain History ← ActivityDetail ← entry form). No backend, no OpenAPI, no migration (no schema change).
- Store reuse: `LocalStore.entry(id)` / `updateEntry` / `undoBufferEnter` / `undoBufferRestore` / `undoBufferCommitExpired` + `UndoBufferStore` already exist; needs an entry-snapshot restore helper mirroring `undoCategoryDeletion` (implementation detail for design).
- Tests: VM tests (modes, gate, stale-save, locked rules, committed-only filter, delete→buffer), store round-trip tests for entry undo, UI identifier tests for tappable rows and cover presentation.
- Docs: `docs/history-roadmap.md` §1–2 resolved by this change; `docs/project-context.md` incomplete/deferred list updated (entry edit/delete shipped, toast still deferred).
