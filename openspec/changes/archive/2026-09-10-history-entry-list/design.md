## Context

The History tab in `AppShellView` is currently a `DestinationPlaceholder` (empty state). The local-first data layer already has full `TimeEntry` CRUD in `LocalStore` (`entries()`, `entry(id:)`, `createEntry`, `updateEntry`, `deleteEntry`, `mergeEntry`) with outbox sync. The `entries()` query returns all entries newest-first, joining `activity_name` from the `activities` table. Categories are resolved from the activity at read time (category-management spec: "current assignments classify Activity history") — no category snapshot is stored on the entry.

The existing design system has `ListRow` (single-subtitle), `ActivityRow` (manage-list row with first-category icon + name + category names + trailing chevron), `SectionHeader`, and `EmptyState`. The app-shell spec's "Running timer remains globally accessible" requirement already holds via the compact timer `safeAreaInset` on the History tab.

A layout spike (variants A–K on a booted simulator) confirmed the chosen row layout: Variant H — icon leading, spanning both text lines, top-aligned with the activity name's capital letter top; name + timespan on line 1; categories (left) + timeframe (right) on line 2.

## Goals / Non-Goals

**Goals:**
- Replace the History placeholder with a real list of committed time entries.
- Group entries by day with relative-then-absolute labels.
- Resolve activity categories at read time (no denormalization).
- Introduce a reusable `EntryRow` design-system component.

**Non-Goals:**
- Tap-to-open, editing, deletion, filtering, manual addition, provenance labels, per-activity timelines (all in `docs/history-roadmap.md`).
- New `LocalStore` queries or schema changes (`entries()` already returns the needed shape).
- Backend / OpenAPI changes.

## Decisions

### D1: History is a list of entries, not activities
An activity is a reusable definition; an entry is a timed event. History answers "what did I spend time on and when?" — that's entries. Activities belong to Manage-Activities (definition management). This keeps History and Manage-Activities cleanly separated: one manages definitions, the other reviews events.

**Alternative considered**: History as a list of activities with nested entries. Rejected — conveys nothing about time spent without drilling in; mixes two entity levels in one surface.

### D2: Day grouping by entry start date
Entries are grouped by the calendar day of `startedAt` (not `createdAt`). Newest day first; within each day, newest entry first. The grouping is a presentation concern owned by `HistoryViewModel` — `LocalStore.entries()` returns a flat list and stays unchanged.

**Alternative considered**: Group by `createdAt`. Rejected — `createdAt` is the sync record timestamp, not when the timed event happened. `startedAt` is the user-meaningful date.

### D3: Relative-then-absolute day labels
"Today" / "Yesterday" for the two most recent calendar days, then the device's regional date format for older days. Uses `RelativeDateTimeFormatter` / `DateFormatter` with the user's locale, following regional standards automatically. No custom date format strings.

### D4: Variant H row layout (spike-confirmed)
The chosen `EntryRow` layout from the spike:
```
  [icon]  Activity Name                    1h 20m
          Health, Morning              14:00 – 15:20
```
- Icon: first category's SF Symbol, `.title3`, `Theme.textSecondary`, 28pt column, vertically spans both text lines, top-aligned with the activity name's **cap-height top** (the top of capital letters), not the text frame top. The offset is tuned per font metrics so the icon's optical top visually aligns with the name's first capital letter.
- Line 1: activity name `.headline` `Theme.textPrimary` (left) + duration `.headline` `Theme.textPrimary` `.monospacedDigit()` (right).
- Line 2: category names `.caption` `Theme.textSecondary` (left) + timeframe `.caption` `Theme.textSecondary` `.monospacedDigit()` (right).
- Fallback: `questionmark` icon when the activity has no categories.
- Min height `Theme.minTapArea`; dividers between rows, leading-aligned after the icon column.

**Alternatives considered**: Variant A (compact subtitle, timespan prominent), Variant B (name alone on line 1, fastest scan), Variants E/F/G (icon alignment variations), Variants J/K (filled circle backgrounds). All spiked on simulator; H was selected for icon-name top alignment and clean two-line density.

### D5: Natural-language duration format
Duration is formatted as natural-language: `33s`, `1m 20s`, `1h 12m`, `1d 12h`, etc. Computed from `durationSeconds` when present; when `endedAt` is nil (entry in progress — edge case for manually created entries), show an in-progress indicator.

### D6: VM resolves categories at read time
`HistoryViewModel` loads `LocalStore.entries()`, `LocalStore.activities()`, and `LocalStore.categories()`, builds an `activityID → [Category]` map, and resolves each entry's display icon + category names from the activity's current category set. No new store queries; no denormalization. This is consistent with the category-management spec ("current assignments classify Activity history").

### D7: No new LocalStore queries
`entries()` already returns `TimeEntry` with `activityName` joined. The VM adds category resolution on top. If performance becomes an issue with large datasets (hundreds of entries + activities), a future change can add a store-level query with joins — but that is premature for v1 data sizes.

### D8: Day-group headers show total tracked time when elevated
Each day-group header shows the day label in its normal in-list position. When the header is elevated (pinned/sticky at the top of the list during scroll), it also shows the total tracked time for that day, right-aligned, using the same natural-language duration formatter as the rows (`33s`, `1m 20s`, `1h 12m`, `1d 12h`) followed by a localized "tracked" suffix (e.g. "2h 35m tracked"). The total is the sum of `durationSeconds` across the day's entries; entries with no `durationSeconds` (in-progress) contribute zero. The total is a presentation concern computed by `HistoryViewModel` from the already-loaded entry list — no new store queries; the view gates its display on the header's elevation state.

**Alternative considered**: Always show the total (header in-list and elevated). Rejected after user testing — the in-list header reads cleaner as a label-only divider; the total earns its place only when the header becomes the top chrome.

### D9: Navigation bar collapses on scroll
The History destination shows the navigation bar (inline "History" title + Profile button) at rest. When the list scrolls down, the nav bar collapses out of view to maximize vertical space for the entry list; when the user scrolls back to the top, the nav bar restores. The Profile button is reachable at rest, so the app-shell baseline "each tab root carries the top-trailing person control" is preserved — no deviation, no follow-up app-shell change needed.

**Alternative considered**: Permanently hide the nav bar. Rejected after user testing — Profile is needed at rest, and the collapsing behavior gives the list full height while scrolling without sacrificing reachability.

> **SUPERSEDED** by `revert-history-nav-collapse`: user testing of the shipped collapse found it unreliable (thresholds only evaluate during an active drag) and jarring (no animation); the nav bar is now permanently visible on History.

### D10: Day-group header aligns with row content columns
The day-group header's day label is left-aligned to the `EntryRow` icon column's leading edge, and the total (when shown) is right-aligned to the `EntryRow` duration/timeframe trailing edge. This makes the elevated header flush with the row content columns rather than the list's default content inset, so the header reads as a continuation of the row grid.

## Risks / Trade-offs

- **Icon top-alignment is font-metric-dependent**: The negative top padding that aligns the icon's top pixel with the name's capital letter top is tuned for `.title3` icon + `.headline` name. If the font stack changes, the offset needs re-tuning. → Mitigation: document the tuning in `Design/COMPONENTS.md` `EntryRow` section; keep the offset as a named constant.
- **Category resolution cost**: The VM loads all activities and categories to build the map. For v1 data sizes (pre-release, single user, no bulk import) this is negligible. → Mitigation: if sync or import brings thousands of entries, add pagination and a store-level join query in a later change.
- **No tap interaction**: Read-only is intentionally limited for step 1. Users may expect tappable rows. → Mitigation: the empty state and visual presentation make the list's read-only nature clear; the roadmap captures tap-to-detail as the next step.
- **Scroll-driven chrome**: The collapsing nav bar and the elevation-gated header total both depend on tracking list scroll offset and the pinned-section state. SwiftUI `List` does not expose scroll offset directly on iOS 15; the implementation uses a scroll-offset preference/observer or a `ScrollViewReader`/`GeometryReader` approach. → Mitigation: isolate the scroll-tracking in `HistoryView`; keep `HistoryViewModel` free of scroll state (it owns data, not chrome).

## Open Questions

- **In-progress entry display**: An entry with `endedAt == nil` and no `durationSeconds` is an edge case (can happen if an entry is created manually with only a start time, or if the app crashed mid-save). The spec says "show an in-progress indicator" — the exact visual (e.g. "in progress" text, a pulsing dot, or just the start time alone) can be finalized during implementation without changing the spec.