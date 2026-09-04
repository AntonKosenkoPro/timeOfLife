## Context

History (`Features/AppShell`) is a read-only day-grouped list; `HistoryViewModel` already resolves everything a row shows (icon from first category, category names, timeframe, natural duration, in-progress state) via pure, unit-tested helpers. `EntryRow` is purely presentational. `LocalStore` has `activity(id:)`, `entries()`, `categories()`, but no per-activity entry query and no duration-sum query. Deletion cascades (activity delete removes its entries — `LocalStore.swift:570`), so an entry always has a live activity; the sheet is unreachable for deleted activities. `ActivityEditorView` (editor-sheet-ux scaffold) is already presented as a sheet from Track and can be stacked. Entry `source` storage is complete (D10); the "via <Source>" label UI is deferred (project-context "Incomplete / deferred", task 6.2) — this change delivers it on rows. See proposal.md for why.

## Goals / Non-Goals

Goals:
- Row tap → medium/large activity detail sheet, reusing History's row rendering and grouping.
- Deliver "via <Source>" labels on all entry rows (History + sheet), closing the deferred provenance surface.
- All-time total, edit-activity route (editor stacks), lazy uncapped per-activity entry list.

Non-Goals:
- Entry detail/edit/delete surfaces (rows in the sheet are inert).
- Activity deletion UI (separate `delete-activity` change; the warn-then-delete contract lands there).
- Period statistics (Insights, later).
- Undo/UndoToast interplay (History stays non-destructive).

## Decisions

### D1: Sheet, not navigation push; medium detent, draggable to large
The tap is exploratory (browse-then-glance). A sheet keeps History's scroll position and nav bar untouched and matches the app's existing sheet-first navigation (search, editor). Medium shows identity + total + first rows; large carries the full history browse. Alternative (push) was rejected: heavier, breaks the "History always visible" pattern, and the detail is dismiss-first, not drill-down-first.

### D2: New `ActivityDetailView` + `ActivityDetailViewModel` in a new `Features/ActivityDetail` folder
Keeps AppShell owning only the tap affordance. The VM reuses `HistoryViewModel`'s **pure static helpers** (`makeDayGroups`, `dayLabel`, `naturalDuration`) rather than duplicating them — they are already `nonisolated static` and unit-tested, so this is reuse, not coupling. Alternatives: put the view in AppShell (mixes capabilities) or in Catalog (detail is History-driven, not catalog-management-driven).

### D3: Data via new read-only `LocalStore` queries
- `entries(activityID:)` — committed entries for one activity, `started_at DESC` (same join as `entries()` for `activity_name`).
- `totalDuration(activityID:)` — `SELECT COALESCE(SUM(duration_seconds), 0)` for the header total (all-time, committed only).
- `activity(id:)` already exists.
No writes, no outbox, no new migration. Invariant honored: LocalStore stays the only data chokepoint.

### D4: Presentation layering in the sheet VM mirrors HistoryViewModel's
Load `activity(id:)`, its categories, its entries; build `[DayGroup]` with the shared helpers; expose row-presentation funcs mirroring the History VM's (`icon/categoryNames/timeframe/duration`), extended with a provenance formatter (`viaText(for:)` → localized "via X" or empty for `manual`). The source-name mapping is a single static table (`manual`→nil, `widget`/`siri`/`control`/`screentime`/`garmin`/`calendar`/`healthkit`→localized names) shared by History VM and detail VM.

### D5: Refresh semantics — sheet reloads on appear and after the editor dismisses
The sheet VM loads on `.task`/appear. After `ActivityEditorView` dismisses (stacked on top), the sheet reloads so name/icon/categories reflect edits. While the sheet is open, a timer running elsewhere does not refresh it (running entries are excluded anyway; committed data changing mid-sheet is possible only from sync — the next History appear invalidation pattern covers staleness on re-entry).

### D6: Deleted-while-open activity → dismiss the sheet
If `activity(id:)` returns nil on reload, the sheet presents an empty/error-free dismissal (guard: cascade means its entries are gone too). The History list refresh (existing `needsReload` on next appear + `refreshSignal`) removes the dead rows. No alert needed — there is no in-app path to delete an activity today; this is future-proofing for `delete-activity`.

### D7: Provenance label placement on rows
The "via <Source>" text is appended to the row's category caption line (left caption): categories, then ", via Screen Time" when source ≠ `manual`. Rationale: the category caption is the row's metadata line; the alternative (a third line) inflates row height for a rarely-present label. This touches `EntryRow` inputs (a `viaText` string) and both VMs. A11y label folds it in via the existing `accessibilityLabel` builder.

### D8: Editor stacks via a second `.sheet(item:)` on the detail view
Native stacked-sheet behavior; dismissing returns to the detail sheet which then reloads (D5). The detail sheet stays non-destructive: no delete button — `delete-activity` will add deletion to the editor surface later.

## Risks / Trade-offs

- [All-time total grows stale while sheet is open (sync writes)] → Mitigation: reload on editor dismissal; acceptable staleness for a glance surface; History's invalidate-on-appear pattern remains the safety net.
- [Uncapped list at large detent re-renders like History] → Mitigation: same `ScrollView`+`LazyVStack` approach and lazy loading as History; entries query is indexed by `activity_id` (FK index exists via join table usage — verify; add index if EXPLAIN shows a scan).
- ["via" text changes row layout for imported entries] → Mitigation: caption-line append keeps row height stable; snapshot-style previews for rows with/without label in both languages.
- [Two VMs sharing static helpers could drift] → Mitigation: helpers are unit-tested pure functions in one file; a future extraction into a shared `EntryRowModel` builder is mechanical if drift appears.

## Migration Plan

No data migration. New strings to both `en.lproj`/`ru.lproj` + `L10n` (U4). Docs updates: `docs/project-context.md` (retire "via <Source>" incomplete item; note the new capability), `Design/COMPONENTS.md` if the sheet needs a new component entry.

## Open Questions

None blocking. Insights (period stats) and `delete-activity` (warn + delete UI) are separate future changes with their own proposals.