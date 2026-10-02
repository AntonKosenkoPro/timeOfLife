## Why

Opening the category editor from the populated Manage Categories list via the navbar `+` (`ManageCategoriesAddButton`) plays a weird plus-button animation as the sheet opens (issue #101). The empty-state Add path (`vm.addCategory()` — same call-site) does not show it, so the presenter side (toolbar / List / NavigationStack-in-sheet churn) is suspected, not the editor keyboard. Fix the visual glitch without changing any behavior.

## What Changes

- Repro-first spike: capture the glitch with slow animations + screen recording, comparing toolbar-plus (populated list, `ManageCategoriesView.swift:68-76`) vs empty-state Add (`:44-51`) into the same `vm.addCategory()` → sheet path.
- Probe-only isolation of keyboard-vs-transition: temporarily vary the editor sheet's `FocusDelay` autofocus (`PresentationMetrics.swift:8-19`, 400ms settle) / disable autofocus as throwaway probes to rule the keyboard in or out — not shippable changes.
- Minimal presenter-side calm on the confirmed cause (e.g. explicit transaction / animation-nil on the presenting button path) so sheet open shows no plus animation.
- No behavior change: same destinations, same `vm.addCategory()` semantics, same editor sheet content, same autofocus contract.

## Capabilities

### New Capabilities

- None — visual-only fix, no new behavior.

### Modified Capabilities

- None — no REQUIREMENT changes. Baseline `category-management` (Add opens editor) and `editor-sheet-ux` (presentation/autofocus contract) stay as-is; this change only calms the presenting animation. Validation opts out via `skip_specs: true` in `.openspec.yaml`.

## Impact

- Affected code: `ManageCategoriesView.swift` toolbar plus path (`:68-76`, `ManageCategoriesAddButton`), possibly the presenting transaction/animation only; probe-only touches to `CategoryEditorView` / `PresentationMetrics.swift` FocusDelay reverted before shipping.
- No API, OpenAPI, sync, persistence, or navigation-behavior changes.
- Non-goals (explicit): the editor sheet's 400ms `FocusDelay` autofocus is out of scope unless the spike implicates it; no Liquid-glass header redesign (#35 is context only); no change to empty-state Add, edit-row, save/cancel/delete, undo, localization, or accessibility identifiers.
