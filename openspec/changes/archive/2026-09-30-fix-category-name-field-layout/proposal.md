## Why

Issue #82 reports that the Name field in the Category create/edit forms renders with a weirdly large height and lands partly out of viewport when focused. The cause traces to the #42 clear-button rework (`2fa5608`): the field's height now depends on clear-button visibility (54pt ⇄ ~76pt), and the `@FocusState` binding sits on the field's wrapper container instead of the `TextField` itself. Fix now while the regression window is two days old and the pattern hasn't spread to new call sites.

## What Changes

- `TextFieldWithError` accepts a `FocusState<Bool>.Binding` and applies `.focused` to its inner `TextField` (per Apple docs, focus moves to *the modified view*); the inner field gets a stable `minHeight` of `Theme.minTapArea` so the 44pt clear button fits inside an already-44pt row and the field never breathes with focus state.
- `CategoryEditorView` passes its focus state down instead of attaching `.focused` to the wrapper, and autofocuses after the sheet presentation settles (cancellable, NamePicker-style) so the keyboard doesn't fire mid-animation and the ScrollView auto-scroll lands the field fully in viewport.
- Same wrapper-`.focused` audit for `EmailEntryView` (no height symptom there — no clear button — but its autofocus may be silently dead for the same reason); fixed only if the spike confirms it.
- No string, validation, save, sync, or visual-design changes: same copy, same Apple-standard × look, same medium+large detents, same pinned Save bar.

## Capabilities

### New Capabilities

(none — this is a corrective fix within existing contracts)

### Modified Capabilities

- `category-management`: the category-editor name-field contract gains layout/focus stability — stable field height regardless of clear-button visibility, focus bound to the actual text field, autofocus landing fully in viewport.
- `editor-sheet-ux`: the editor-sheet focus contract gains presentation-settle timing — autofocus engages after the sheet animation settles so keyboard-driven auto-scroll computes against final layout.

## Impact

- iOS only: `Core/Design/Components/TextFieldWithError.swift`, `Features/Catalog/Views/CategoryEditorView.swift`, possibly `Features/Auth/Views/EmailEntryView.swift` (audit only).
- No API, backend, OpenAPI, sync, persistence, or localization changes. No new strings (U4 untouched).
- Non-goals: unifying the three plain-text field patterns (`TextFieldWithError` / `NamePicker` fieldCard / `FormCard` rows) — noted as future work, not this change. No detent or keyboard-avoidance redesign. No behavior change to validation, duplicate, stale-conflict, or delete flows.
- Docs consulted (ctx7): Apple SwiftUI `/websites/developer_apple_swiftui` — "`focused(_:)` modifier placement" (focus moves to the modified view; all examples bind the `TextField` directly) and "conditionally showing views vs overlay/hidden layout semantics" (`if` omits from layout; `.overlay` never participates; `.hidden()` keeps footprint). Project docs: `Design/INTERACTIONS.md` (Focus management, Editor sheets D13/D21).
