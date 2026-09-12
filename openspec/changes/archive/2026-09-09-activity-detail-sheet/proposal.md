## Why

History is shipped but deliberately inert: tapping an entry row does nothing, so the user has no way to go from "I tracked 1h 20m of Running yesterday" to "what is Running, how much have I tracked under it overall, and what else have I done under it?". The row shows one entry's slice; there is no surface that answers the activity-level question. Tapping the row is the natural entry point, and the `entry-provenance` baseline already promises user-visible "via <Source>" labels on entries that no surface delivers today.

## What Changes

- Tapping a History entry row opens an **Activity detail sheet** (medium detent, draggable to large).
- The sheet toolbar shows the activity name and an **Edit activity** action. The body header shows each activity field **exactly once**: the activity icon, its categories (each with its own icon, under a "Categories" label), and the notes — never repeating the name.
- A divider separates the activity header from the **Entries** section, whose header carries the **all-time tracked total** ("Total: 12h 40m 5s", three-component duration format).
- The Entries section lists **all committed entries, day-grouped** like the History list (uncapped, lazily loaded), each row showing **only entry data**: start–finish times (day-prefixed when spanning midnight), provenance as a shared sync icon plus source name, and duration — no activity name/icon/categories.
- Entry rows inside the sheet are not tappable. The running entry never appears in the sheet (same rule as History).
- "via <Source>" provenance labels appear on **History list rows**; the detail sheet uses the compact sync-icon + source-name form. Manual entries show no label anywhere. This retires the deferred "via <Source>" surface item (an entry-detail surface is explicitly not part of this change).
- History rows become tappable (they were intentionally inert per `history-entry-list`). No swipe actions, no long-press, no edit/delete of entries from History.
- "Edit activity" presents the existing `ActivityEditorView` stacked on top of the detail sheet; dismissing returns to the detail sheet.
- Non-goal (deferred): activity deletion UI with a destructive confirmation ("Delete Running and its 23 entries (12h 40m tracked)?") — separate change `delete-activity`. Cascade deletion semantics stay unchanged; entries die with their activity, so the sheet is unreachable for a deleted activity.
- Non-goal: period-based statistics (week/month) — belongs to a future Insights capability.

## Capabilities

### New Capabilities
- `activity-detail-sheet`: the sheet presented from a History entry tap — identity header, all-time total, edit-activity route, day-grouped committed entries.

### Modified Capabilities
- `history-entry-list`: "History is read-only" requirement is amended — the row tap now navigates to the activity detail sheet (still no edit/delete of entries).
- `entry-provenance`: "User-visible source labels" requirement is amended — the "via <Source>" label lives on entry rows (History and detail sheet); the entry-detail wording is dropped because no entry-detail surface exists.

## Impact

- iOS app: `Features/AppShell/Views/HistoryView.swift` (row tap handling), new detail sheet view + view model (likely `Features/Catalog` or a new `Features/ActivityDetail`), `LocalStore` read-only queries (activity by id, all committed entries for activity, all-time duration total), reuse of `EntryRow` and `EditorSheetScaffold`/`ActivityEditorView`.
- Localization: new strings in `en.lproj` + `ru.lproj` + `L10n` (sheet title, total label, edit button, "via <Source>" labels).
- `docs/project-context.md` "Incomplete / deferred" list: the "via <Source>" labels item is delivered by this change (rows everywhere); entry-detail part is dropped.
- Baseline specs touched: `openspec/specs/history-entry-list/spec.md`, `openspec/specs/entry-provenance/spec.md`.
- No backend/OpenAPI impact (read-only local queries; no new endpoints).
- Design docs: `Design/COMPONENTS.md` gains the detail sheet component if the layout needs one.