## Context

See proposal.md (Why) and `specs/history-entry-list/spec.md` (requirements). Current state: `ManageCategoriesView` + `ManageCategoriesViewModel.registerSystemUndo` implement the proven pattern — passive `ShakeFirstResponderHost` returning the owner's `UndoManager`, clear-then-single registration of the newest snapshot, `entryDeletionSnapshot`-style ownership check, in-flight-push guard via the store throw, re-registration after undo. `HistoryView`/`HistoryViewModel` have none of this: the view owns no undo-manager environment value, the view model owns no `UndoBufferStore`, and `LogTimeView.deleteEntry` dismisses without registering. Store primitives (`entryDeletionSnapshot`, `undoEntryDeletion` with `UndoError.pushInFlight`) already exist and need no change. Constraints: LocalStore stays the single mutation chokepoint; DEFAULT system prompt only, no toast; per-owner supersession (U7) preserved.

## Goals / Non-Goals

**Goals:**
- Give History an entry-owned system-Undo registration that behaves identically to the category one (single most-recent restore, in-flight refusal, silent no-op for foreign snapshots).
- Prove the join-restore contract (`undoCategoryDeletion` re-inserts `entry_categories`) with a regression test, since entry restores depend on the same snapshot shape.

**Non-Goals:**
- No buffer-lifetime, supersession, or push-commit semantic changes; no entry-form UX changes; no new strings.

## Decisions

- **Mirror the category pattern file-for-file** (`@Environment(\.undoManager)` + `.background(ShakeFirstResponderHost(...))` on HistoryView; `registerSystemUndo`/`performUndo` on HistoryViewModel gated on `entryDeletionSnapshot != nil`) over inventing an entry-specific mechanism — rationale: the ownership check + clear-then-single + re-register-after-undo already encode the U7/in-flight subtleties; a second mechanism would drift. Alternative (register in `LogTimeViewModel` at delete time) rejected: the form dismisses immediately, tearing down its responder chain, so the registration would die with the sheet — the surviving list surface must own it, exactly as Manage Categories does.
- **HistoryViewModel takes `UndoBufferStore` as a new init dependency** (same as `ManageCategoriesViewModel`) over reaching into `LocalStore` for `mostRecent()` — rationale: buffer-row recency is the buffer store's job; keeps the owner-check split (buffer = recency, store = snapshot decode) identical on both surfaces.
- **Reuse the existing Delete confirm string for `setActionName`** (U4, no new strings) over a dedicated "Undo delete entry" string — matches the category surface grammar.
- **Reload-then-register ordering on History appear and on entry-form dismiss** (invalidate → loadIfNeeded → registerSystemUndo) — rationale: registration reads the newest buffer row, which only exists after the delete transaction commits; registering before reload races it.

## Risks / Trade-offs

- [Risk] Shake on History with an entry-newest buffer while Manage Categories is also alive → both surfaces register against different managers; each manager is per-responder-chain so no double-restore. Mitigation: per-owner snapshot gate on both sides (spec scenarios lock it).
- [Risk] `removeAllActions(withTarget:)` scope — clearing History's own target only, never the other surface's. Mitigation: mirror the category call exactly (`withTarget: self` where self is the History VM).
- [Risk] Undo after the entry's categories were deleted underneath → snapshot holds stale category ids; restore re-inserts joins for missing categories. Mitigation: `INSERT OR IGNORE` join writes already tolerate this; row renders with unknown ids skipped (existing `categories(for:)` behavior). No spec change — accepted edge, same as today.

## Migration Plan

No migration: pre-release, no on-disk format change, no rollout steps. Rollback = revert the two view files + VM init call sites.

## Open Questions

None.
