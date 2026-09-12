## Why

The History tab is a placeholder (`DestinationPlaceholder` with an empty state). The local-first data layer already stores `TimeEntry` records with full CRUD and sync — but the user has no way to see them. This change implements the first real History surface: a read-only, day-grouped list of time entries so the user can review what they spent time on.

## What Changes

- Replace the History tab's `DestinationPlaceholder` with a real `HistoryView` backed by a `HistoryViewModel`.
- Load committed `TimeEntry` records from `LocalStore.entries()` (newest first), resolve each entry's activity categories, and group entries by day.
- Each row shows: first-category icon (leading, vertically spanning both text lines, top-aligned with the activity name's cap-height top), activity name, comma-separated category names, entry timeframe (start – end), and entry timespan (natural-language duration).
- Day group headers use relative-then-absolute labels following the regional standard ("Today", "Yesterday", then localized date). **In their in-list scroll position the headers show only the day label; when elevated (pinned at the top during scroll) they also show the total tracked time for that day, right-aligned** (e.g. "2h 35m tracked"), aligned flush with the row content columns.
- The History destination shows the navigation bar (inline "History" title + Profile button) at rest and collapses it on scroll-down, restoring it when the user scrolls back to the top — maximizing list space while scrolling without sacrificing Profile reachability at rest.
- Rows with no categories render a `questionmark` fallback icon.
- The list is read-only: tapping a row does nothing in this change.
- The existing empty state (`historyEmptyTitle` / `historyEmptySubtitle`) is preserved.
- The compact cross-tab timer remains wired via `safeAreaInset`.
- New `EntryRow` component in the design system.
- New localization keys for day group labels and the "tracked" total suffix.

## Capabilities

### New Capabilities
- `history-entry-list`: the read-only, day-grouped list of time entries shown in the History tab.

### Modified Capabilities
- `app-shell`: the History destination changes from a placeholder to a real list view. The "Running timer remains globally accessible" and "Three primary destinations" requirements still hold; the History destination gains content.

## Impact

- **iOS code**: new `HistoryView`, `HistoryViewModel`, `EntryRow` component; `AppShellView` History tab wiring changes (nav bar collapses on scroll on History); `SectionHeader` gains an optional trailing total and row-column alignment; `AppContainer` may need a factory for the VM.
- **Design docs**: new `Design/SCREENS/History.md` screen spec; new `EntryRow` entry in `Design/COMPONENTS.md`; `SectionHeader` updated in `Design/COMPONENTS.md`.
- **Localization**: new keys in `en.lproj` and `ru.lproj` for day group labels and the "tracked" total suffix; `L10n` enum additions.
- **Backend / OpenAPI**: no changes — `entries()` and the `/entries` resource already exist.
- **LocalStore**: no schema changes — `entries()` already returns the data shape needed; the VM resolves categories from activities at read time and computes per-day totals from the entry list.
- **Tests**: new `HistoryViewModelTests`; `EntryRow` snapshot/accessibility tests; day-total computation tests.

## Non-goals

The following are deferred to later changes (captured in `docs/history-roadmap.md`):
- Tap on entry → EntryDetail / EntryEditor.
- Manual entry addition (no-timer start/end logging).
- History filtering (by activity, date range, source).
- Entry delete / undo from History.
- "via <Source>" provenance labels.
- Running / in-progress session row in History.
- ActivityDetail screen with per-activity timeline.