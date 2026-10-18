## Why

Creating a category today requires abandoning the entry form, navigating to Profile → Manage Categories, creating it there, and returning to re-open the form. Users in a capture flow instead mistag or skip tagging, degrading per-entry category quality — the core organizing signal of the app.

## What Changes

- `TagSelector` gains an opt-in trailing creation chip: rendered last in the flow only when the parent passes an `onCreate` closure; `nil` preserves today's select-only rendering. The chip is visually distinct from both unselected and selected chips (dashed-outline action style, `plus` glyph, localized label). The chip region grows with content but clamps at 3.5 visible rows (half-row peek signals scrollability), scrolling internally beyond that — small catalogs stay compact with no dead space.
- Tapping the chip pushes the full category editor (name + icon grid, identical validation and duplicate rules as Profile creation) onto the **host navigation stack** — never a stacked sheet:
  - LogTime CREATE (sheet with its own `NavigationStack`) → push inside the sheet.
  - LogTime EDIT/LOCKED host (pushed on `historyPath`) → push on the History stack.
  - Track tab (root of `trackPath`) → push a new `ShellRoute` destination.
- Saving a new category reloads the host's category options and **auto-selects** the new id (ordered append): `LogTimeViewModel.categoryIDs` for CREATE/EDIT, the running draft's `categoryIDs` while Track is running. The footer is reachable only while the timer runs or from the entry form (non-running Track shows Recents).
- Recents parity: `RecentActivitiesChips` adopts the same viewport contract — flexible height clamped at 3.5 visible rows with internal scroll (row height from its own scaled subheadline metrics) plus the same edge-aware hairline dividers (top fades in once scrolled, bottom fades out at the end, both hidden when everything fits). Shared clamp/edge math lives in `ChipViewport` so both groups behave identically.
- Duplicate names keep the existing contract everywhere: editor stays open with the localized `errorCategoryExists` banner, draft preserved (no "select the winner" shortcut from entry forms).
- New localized strings in `en` + `ru` + `L10n` (U4); `Theme` semantic colors only.

Non-goals: no quick-create (name-only) path; no Track Recents changes; no backend/OpenAPI changes (creation reuses `LocalStore.createCategory` + existing sync outbox); no Manage Categories list changes; no undo/toast additions.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `category-management`: category creation gains two entry points (entry form, running-tag row) beyond Profile; editor form becomes hostable on a push stack in addition to its sheet; TagSelector contract gains the opt-in trailing creation chip with a 3.5-row clamped chip viewport.
- `timer-capture-experience`: the running `TagSelector` is no longer strictly select-only — it offers the same creation entry point, scoped so plain-text capture, Recents behavior, and running-draft snapshot rules are otherwise unchanged.

## Impact

- iOS only: `Core/Design/Components/TagSelector.swift` (opt-in chip), `Catalog/Views/CategoryEditorView.swift` (extract pushable editor form from sheet chrome), `ManualEntry/Views/LogTimeView.swift` (wire `onCreate` + post-save reload/select), `TimeTracking/Views/TrackContent.swift` (+ owning view model reload/select), `AppShell` (`ShellRoute` + destinations for Track and pushed LogTime EDIT), `L10n` + `en`/`ru` strings, `Design/COMPONENTS.md` + `Design/SCREENS/CategoryEditor.md` doc updates.
- No backend, OpenAPI, on-disk format, or auth/session changes. Offline creation inherits the existing local-first outbox path.

## Research bundle (ctx7)

Pin: iOS 18 SDK via Xcode 16+ (unversioned IDs — no `/v18.x` variants offered).

- SwiftUI `/websites/developer_apple_swiftui` — query `NavigationStack push navigation programmatic navigation path iOS 18` (docs: `navigationlink`, `migrating-to-new-navigation-types`, `understanding-the-navigation-stack`, `navigationstack`): path-driven pushes via `NavigationLink(value:)` + `.navigationDestination(for:)`; direct path append for programmatic push; a sheet-hosted `NavigationStack` needs its own `@State` path scoped to the sheet.
- HIG `/websites/developer_apple_design_human-interface-guidelines` — query `adding creation affordances buttons in context` (docs: `context-menus`, `pull-down-buttons`, `widgets`): partially applicable — returned samples only, no chip-group/trailing-action prose (see design.md waiver); residue confirms in-context creation entry points are idiomatic.
- SwiftUI `/websites/developer_apple_swiftui` (reused ID, no extra library call) — query `accessibility custom button accessibilityLabel accessibilityValue VoiceOver` (docs: `accessibilitylabel`, `accessibilityvalue`, `view-accessibility`): `Button`-based chips announce automatically; icon-only `+` chip needs a localized label without the trait word; no `accessibilityValue` for a static action chip; all strings localized.
