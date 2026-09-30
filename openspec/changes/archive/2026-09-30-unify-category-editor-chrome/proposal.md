## Why

Two follow-ups to the category name-field fix (user-verified on device): (1) the category editor's text-Cancel + pinned bottom Save bar look foreign next to the Log Time sheet's toolbar X / ✓ grammar — same app, same "form" job, two visual languages; (2) the medium detent makes the sheet jump when the keyboard appears and parks scrolled content half under the nav bar. Both dissolve if the category editor inherits the Log Time sheet contract: full-height sheet, toolbar chrome, no detent transition to fight.

## What Changes

- Category editor adopts the Log Time toolbar grammar: `xmark` at `.cancellationAction` for cancel, `checkmark` at `.confirmationAction` for save, gated on validity + idle (mirroring `LogTimeView.chrome` disabled rules). The text Cancel button and the pinned bottom Save bar are removed.
- The category sheet goes full-height only: the medium detent is dropped (closed or fully open, per user decision) — no detent resize when the keyboard appears, no jump.
- Keyboard + scroll contract: sheet opens full-height, autofocus engages (the settle-delayed focus from `fix-category-name-field-layout` stays), and content remains top-anchored — the name field fully visible with no auto-scroll displacement.
- Accessibility identifiers are preserved (`CategoryEditorCancelButton`, `CategoryEditorSaveButton`, field/grid/banner/delete ids); the X/✓ buttons get proper VoiceOver labels (Log Time precedent: `entryDismissLabel`, `entryConfirmSaveLabel` analogues).
- Title presentation (inline vs collapsing large) is a design decision with a recommendation (inline, Log Time parity — also removes the collapse-driven clipping vector); the spec pins only observable outcomes.

## Capabilities

### New Capabilities

(none — corrective unification within existing contracts)

### Modified Capabilities

- `editor-sheet-ux`: the shared editor-sheet contract gains the Log Time chrome option (toolbar X/✓, full-height presentation, no-jump keyboard behavior); the medium-detent collapsing-header presentation stops being the category editor's contract.
- `category-management`: the category editor's Cancel/Save affordances change from text-Cancel + bottom Save bar to toolbar X + ✓ with validity gating; all other editor behavior (validation, duplicate/stale flows, delete + undo, icon picker) is unchanged.

## Impact

- iOS only: `Features/Catalog/Views/CategoryEditorView.swift`, `Core/Design/Components/EditorSheetScaffold.swift` (detent flag + chrome ownership — category editor is currently its only consumer), `L10n` + EN/RU strings for the new VoiceOver labels (U4), `Design/SCREENS/CategoryEditor.md`, `Design/INTERACTIONS.md` (D13/D21 editor-sheet wording), `Design/COMPONENTS.md` if the scaffold contract changes.
- No API, backend, OpenAPI, sync, persistence, validation-rule, or color changes. No new user-facing copy except accessibility labels.
- Non-goals: entry-form (Log Time) presentation untouched; no new detent physics of our own (use the system full-height sheet); no unifying the three field patterns (still future work); the settle-delayed autofocus and compact field from `fix-category-name-field-layout` stay as-is.
- Docs consulted (ctx7, prior change): Apple SwiftUI `/websites/developer_apple_swiftui` — `presentationDetents` semantics and keyboard-avoidance behavior; project docs `Design/INTERACTIONS.md` (D13/D21), `Design/SCREENS/CategoryEditor.md`.
