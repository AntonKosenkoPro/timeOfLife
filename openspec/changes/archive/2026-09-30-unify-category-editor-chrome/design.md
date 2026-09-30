## Context

See `proposal.md` (Why). Current state: `CategoryEditorView` renders through `EditorSheetScaffold` (medium+large detents, collapsing large title, text Cancel, pinned bottom Save bar); the scaffold's only consumer is the category editor. `LogTimeView.chrome` implements the target pattern (inline title, toolbar X/`checkmark`, `.scrollDismissesKeyboard(.interactively)`, no bottom bar) and its CREATE sheet is a plain full-height `.sheet`. The settle-delayed autofocus + compact field from `fix-category-name-field-layout` (now baseline) stay.

## Goals / Non-Goals

**Goals:**
- Category editor indistinguishable in chrome from the Log Time sheet; zero sheet motion on keyboard events.
- One obvious home for the chrome: either the scaffold grows a variant or the editor owns Log-Time-style chrome directly.

**Non-Goals:**
- No validation, save, sync, delete, or icon-picker behavior changes; no color/typography changes beyond chrome placement.
- No new detent physics, no custom keyboard avoidance — system full-height sheet behavior only.

## Decisions

1. **Category editor leaves `EditorSheetScaffold`; owns `LogTimeView`-style chrome directly.**
   The scaffold's contract (collapsing large title + measured bottom bar + medium detents) is exactly what this change removes — bending it into a variant flag (`usesToolbarChrome`) would leave a one-consumer abstraction with two contradictory contracts. Alternative (add variant to scaffold) rejected: dead flexibility; a future editor can re-extract shared pieces then. The scaffold stays for future collapsing-header editors; its `usesMediumDetent` flag stays (still honest for that presentation).
   Consequence: `CategoryEditorView` gets its own `NavigationStack` + full-height `.sheet` presentation (presentation moves back to the presenter: plain `.sheet`, no detents — like History's Log Time sheet), inline title, toolbar X/`checkmark`, `scrollDismissesKeyboard(.interactively)`.

2. **Inline title (Log Time parity), not collapsing large.**
   Kills the collapse-driven clipping vector behind finding 2 and matches the reference sheet pixel-for-pixel in chrome. Alternative (keep large title on a full-height sheet) rejected: preserves the collapse animation that contributed to content parking under the bar, for no user value on a two-section form.

3. **✓ gating mirrors `canSave` (`CategoryName.validate` + `!isLoading`); X mirrors Cancel paths.**
   Same disabled-while-saving rules for X and swipe-down (`interactiveDismissDisabled(isLoading)` stays). A11y ids `CategoryEditorCancelButton`/`CategoryEditorSaveButton` move onto the toolbar items (stable ids preserved); VoiceOver labels follow the Log Time precedent (`entryDismissLabel`/`entryConfirmSaveLabel` analogues as new `L10n` keys, EN+RU).

4. **Keep the settle-delayed autofocus.**
   Still the correct call on a full-height sheet (keyboard mid-animation is harmless when nothing resizes, but the delay costs nothing and the task cancels on dismiss). If verification shows focus landing cleanly without it, simplify then — not now.

## Risks / Trade-offs

- [Risk] Full-height sheet feels heavier than medium for a two-field form → Mitigation: matches the Log Time sheet users already accept; content is top-anchored and short.
- [Risk] Deleting the bottom Save bar removes a large tap target → Mitigation: ✓ is the platform-idiomatic confirm (Calendar grammar, already shipped in Log Time); Save's disabled logic moves unchanged onto ✓.
- [Risk] Scaffold becomes unused (dead code) → Mitigation: accepted deliberately; remove the scaffold only in a later cleanup change if no second consumer appears — not here, to keep this diff reviewable.
- [Trade-off] Editor chrome now lives in two places (LogTime chrome + editor chrome) until a future extraction — duplication of ~30 lines in exchange for not over-abstracting.

## Migration Plan

No migration: no on-disk, API, or localization-contract changes (new L10n keys only). Rollback is a plain revert. Archive folds the two delta specs into `editor-sheet-ux` and `category-management`.
