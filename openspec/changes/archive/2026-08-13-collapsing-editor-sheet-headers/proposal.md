## Why

The Activity and Category editor sheets render their title as a custom bold text inside the scroll content while the always-visible navigation bar holds only Cancel. Scrolling sends content sliding under a bar with no header and no material, so the Cancel button visually overlaps content mid-scroll instead of reading as a header. The user wants the Apple-native collapsing-header pattern (large title at rest, material bar with inline title on scroll), shared by every current and future editor sheet.

## What Changes

- Editor sheets (Category create/edit, Activity edit/refine, and future quick-create) adopt the native collapsing large-title navigation header: large title at rest with Cancel floating top-left, collapsing into a material bar with an inline title + Cancel on scroll, expanding back at the top edge.
- The custom `Text(...).font(.title.bold())` title is removed from each editor's scroll content; the title moves to the native `navigationTitle`.
- A new shared `EditorSheetScaffold` component in `Core/Design/Components/` encapsulates the header pattern, Cancel affordance, scroll container, and pinned bottom save bar; both editors are migrated to it and future editor sheets are required to reuse it.
- The header presentation is system-owned (SwiftUI `navigationTitle` + large title mode); no custom overlay, geometry tracking, or UIKit appearance hacks.

## Capabilities

### New Capabilities
- `editor-sheet-ux`: the shared presentation contract for editor sheets — collapsing native header with an always-available Cancel affordance, one reusable scaffold for all editor sheets, and preservation of the existing keyboard-safe pinned save bar.

### Modified Capabilities

None. The baseline `category-management` and `timer-capture-experience` requirements (draft preservation, cancel semantics, refinement behavior) are unchanged; only presentation details move from Design docs into a first-class spec.

## Impact

- **iOS views**: `CategoryEditorView`, `ActivityEditorView` (migrated to the scaffold; per-view `@FocusState`, dismiss-on-save hooks stay in each editor).
- **New component**: `Core/Design/Components/EditorSheetScaffold.swift`.
- **Docs**: `Design/SCREENS/CategoryEditor.md`, `Design/SCREENS/ActivityEditor.md` (layout + header sections), `Design/COMPONENTS.md` (new component contract), `Design/DECISIONS.md` (new D33 decision), `docs/project-context.md` if component standards need a pointer.
- **Localization**: none — the titles already exist (`activityEditor.*Title`, `categoryEditor.*Title`) and are reused as navigation titles.
- **Backend**: none.

## Non-Goals

- Do not change the searchable Activity search sheet header (system-owned search presentation).
- Do not apply the collapsing header to Manage Categories or other pushed list screens.
- Do not introduce custom bar overlays, scroll-offset tracking, or `UINavigationBarAppearance` overrides.
- Do not change cancel/save semantics, validation, conflict handling, or detents behavior.
