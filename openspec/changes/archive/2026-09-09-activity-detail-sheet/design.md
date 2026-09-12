## Context

History (`Features/AppShell`) is a read-only day-grouped list; `HistoryViewModel` already resolves everything a row shows (icon from first category, category names, timeframe, natural duration, in-progress state) via pure, unit-tested helpers. `EntryRow` is purely presentational. `LocalStore` has `activity(id:)`, `entries()`, `categories()`, but no per-activity entry query and no duration-sum query. Deletion cascades (activity delete removes its entries — `LocalStore.swift:570`), so an entry always has a live activity; the sheet is unreachable for deleted activities. `ActivityEditorView` (editor-sheet-ux scaffold) is already presented as a sheet from Track and can be stacked. Entry `source` storage is complete (D10); the "via <Source>" label UI is deferred (project-context "Incomplete / deferred", task 6.2) — this change delivers it on rows. See proposal.md for why.

## Goals / Non-Goals

Goals:
- Row tap → medium/large activity detail sheet where each activity field appears exactly once.
- Divider-separated Entries section with the all-time total in its header and entry-only rows.
- "via <Source>" labels on History rows; compact sync-icon + source-name provenance on sheet rows — closing the deferred provenance surface.

Non-Goals:
- Entry detail/edit/delete surfaces (rows in the sheet are inert).
- Activity deletion UI (separate `delete-activity` change; the warn-then-delete contract lands there).
- Period statistics (Insights, later).
- Undo/UndoToast interplay (History stays non-destructive).

## Decisions

### D1: Sheet, not navigation push; medium detent, draggable to large
The tap is exploratory (browse-then-glance). A sheet keeps History's scroll position and nav bar untouched and matches the app's existing sheet-first navigation (search, editor). Medium shows identity + total + first rows; large carries the full history browse. Alternative (push) was rejected: heavier, breaks the "History always visible" pattern, and the detail is dismiss-first, not drill-down-first.

### D2: New `ActivityDetailView` + `ActivityDetailViewModel` in a new `Features/ActivityDetail` folder
Keeps AppShell owning only the tap affordance. The VM reuses `HistoryViewModel`'s **pure static helpers** (`makeDayGroups`, `dayLabel`, `naturalDuration`) for grouping and day labels rather than duplicating them — they are already `nonisolated static` and unit-tested, so this is reuse, not coupling. The sheet does NOT reuse `EntryRow` for its entry list: `EntryRow` is built around activity identity (icon + name + categories), which the sheet must not repeat — the sheet gets a small dedicated entry-only row. Alternatives: put the view in AppShell (mixes capabilities) or in Catalog (detail is History-driven, not catalog-management-driven).

### D2a: Single-appearance layout (revision)
Toolbar: activity name (title) + "Edit activity" action. Body header: activity icon leading; categories line with each category's icon under a localized "Categories" label — always rendered, showing a localized "none" value when the activity has no categories; notes when present; no name. A `Divider` separates the header from the Entries section, whose header row is "Entries" + "Total: <three-component duration>". Rationale: the original implementation repeated name/icon/categories in the nav title, the header, and every row; the revision keeps one canonical spot per field.

### D3: Data via new read-only `LocalStore` queries
- `entries(activityID:)` — committed entries for one activity, `started_at DESC` (same join as `entries()` for `activity_name`).
- `totalDuration(activityID:)` — `SELECT COALESCE(SUM(duration_seconds), 0)` for the header total (all-time, committed only).
- `activity(id:)` already exists.
No writes, no outbox, no new migration. Invariant honored: LocalStore stays the only data chokepoint.

### D4: Presentation layering in the sheet VM mirrors HistoryViewModel's
Load `activity(id:)`, its categories, its entries; build `[DayGroup]` with the shared helpers. Row presentation is entry-only and does not mirror History's row funcs: a `timeRangeText(for:in:)` (bare "2:34 PM – 5:46 PM" when both endpoints share the group's day, day-prefixed endpoints otherwise, using the shared `dayLabel`), a provenance pair (sync icon name + localized source name, empty for `manual`), and durations via the new three-component formatter (D4a). The source-name mapping is the shared static table from D7 (`manual`→nil, others→localized names).

### D4a: Three-component duration format (revision)
A new pure static formatter (unit-tested): up to three largest `w/d/h/m/s` components, largest first, zero components omitted — except seconds are appended when minutes are shown even as `0s`, subject to the three-component cap ("2w 5d 11h", "1h 52m 31s", "1h 5m 0s", "59m 50s"). Used for both the Entries "Total:" and row durations in the sheet. History keeps its minute-granularity `naturalDuration`; the sheet's second-granularity is deliberate (short sessions like "16s" are the norm there).

### D5: Refresh semantics — sheet reloads on appear and after the editor dismisses
The sheet VM loads on `.task`/appear. After `ActivityEditorView` dismisses (stacked on top), the sheet reloads so name/icon/categories reflect edits. While the sheet is open, a timer running elsewhere does not refresh it (running entries are excluded anyway; committed data changing mid-sheet is possible only from sync — the next History appear invalidation pattern covers staleness on re-entry).

### D6: Deleted-while-open activity → dismiss the sheet
If `activity(id:)` returns nil on reload, the sheet presents an empty/error-free dismissal (guard: cascade means its entries are gone too). The History list refresh (existing `needsReload` on next appear + `refreshSignal`) removes the dead rows. No alert needed — there is no in-app path to delete an activity today; this is future-proofing for `delete-activity`.

### D7: Provenance label placement differs per surface (revised)
History rows keep the "via <Source>" text appended to the category caption line (left caption): categories, then ", via Screen Time" when source ≠ `manual`. Sheet entry rows instead show the shared two-arrows sync icon plus the localized source name ("Garmin") — no "via" prefix — since sheet rows carry no caption line at all. Both forms share the `EntryProvenance` source→name table; `EntryRow` keeps its `viaText` input for the History form. A11y labels fold the provenance in on both surfaces via the existing `accessibilityLabel` builder pattern.

### D8: Editor stacks via a second `.sheet(item:)` on the detail view
Native stacked-sheet behavior; dismissing returns to the detail sheet which then reloads (D5). The editor never dismisses itself — `save()` only fires `onSaved` — so the detail presenter clears its sheet item in `onSaved` (Save closes the editor) as well as on Cancel; the existing on-dismiss reload covers the refresh either way. Scoped to this presentation: Track's use of the same editor is untouched. The detail sheet stays non-destructive: no delete button — `delete-activity` will add deletion to the editor surface later.

## Risks / Trade-offs

- [All-time total grows stale while sheet is open (sync writes)] → Mitigation: reload on editor dismissal; acceptable staleness for a glance surface; History's invalidate-on-appear pattern remains the safety net.
- [Uncapped list at large detent re-renders like History] → Mitigation: same `ScrollView`+`LazyVStack` approach and lazy loading as History; entries query is indexed by `activity_id` (FK index exists via join table usage — verify; add index if EXPLAIN shows a scan).
- ["via" text changes row layout for imported entries] → Mitigation: caption-line append keeps row height stable; snapshot-style previews for rows with/without label in both languages.
- [Two VMs sharing static helpers could drift] → Mitigation: helpers are unit-tested pure functions in one file; a future extraction into a shared `EntryRowModel` builder is mechanical if drift appears.

## Migration Plan

No data migration. New strings to both `en.lproj`/`ru.lproj` + `L10n` (U4). Docs updates: `docs/project-context.md` (retire "via <Source>" incomplete item; note the new capability), `Design/COMPONENTS.md` if the sheet needs a new component entry.

## Open Questions

None blocking. Insights (period stats) and `delete-activity` (warn + delete UI) are separate future changes with their own proposals.