# History Screen

Implements the `history-entry-list` capability (`openspec/specs/history-entry-list/spec.md`): a read-only, day-grouped list of committed time entries in the History tab. Deferred items live in `docs/history-roadmap.md`.

The History destination answers "what did I spend time on and when?" — a chronology of timed events (entries), not activity definitions. Entries are grouped by the calendar day they started on; categories are resolved from each activity's current category set at read time (no denormalization, design D6).

---

## Screen: HistoryView

- **File**: `ios/TimeOfLife/TimeOfLife/Features/AppShell/Views/HistoryView.swift`
- **Route**: App shell History tab (replaces `DestinationPlaceholder`)
- **ViewModel**: `HistoryViewModel` (`Features/AppShell/ViewModels/HistoryViewModel.swift`)

### Layout

- Body: `List` with a section per calendar day (newest day first), `EntryRow` per entry (newest first within the day), `accessibilityIdentifier("HistoryList")`. List background `Theme.backgroundPrimary`.
- Day-group headers: `SectionHeader` with the day label (`SectionHeader` history usage, D8/D10) — day label left-aligned to the `EntryRow` icon column's leading edge (`contentLeadingInset: EntryRow.iconColumnWidth + EntryRow.columnSpacing` minus the list's own content inset). When the header is elevated (pinned at the top of the list), it also shows the day's total tracked time, right-aligned ("2h 35m tracked"). In-list headers show only the day label.
- Row dividers lead after the icon column (Variant H).
- Inline navigation title: "History" (`L10n.tabHistory`), shown at rest.
- Navigation bar (inline title + Profile button) permanently visible at every scroll position (the scroll-driven collapse from the original change was reverted — see the `revert-history-nav-collapse` change). Profile is reachable at all times on History.
- Empty state: when no committed entries exist show `EmptyState(icon: "clock.arrow.circlepath", title: L10n.historyEmptyTitle, subtitle: L10n.historyEmptySubtitle)` — the pre-existing shell empty state is preserved.
- Compact cross-tab running timer stays visible via `.safeAreaInset(edge: .bottom)` (app-shell "Running timer remains globally accessible"); the running session does NOT appear as a History entry until stopped and saved.

### Behaviors

- On appear, load entries (`LocalStore.entries()`), activities (`LocalStore.activities()`), and categories (`LocalStore.categories()`); rebuild day groups. Read-only — no mutation paths on this screen.
- Rows do not respond to taps in this capability (see roadmap: tap-to-detail is deferred).
- Elevated-header tracking is view state owned by `HistoryView`; `HistoryViewModel` owns data only (design risk note).

### States

| State | Visual |
|---|---|
| Loading | Progress indicator while the local store is read |
| Empty | `EmptyState` (`clock.arrow.circlepath`, `historyEmptyTitle` / `historyEmptySubtitle`) |
| Loaded | Day-grouped `List` of `EntryRow` |
| In-progress entry | Row shows the start time + localized in-progress indicator in place of end time and duration |
| Elevated header | Pinned day-group header shows the day total ("2h 35m tracked"); in-list headers show only the day label |

### Data model

```swift
struct DayGroup: Identifiable, Equatable {
    let id: String          // day-start identifier, e.g. "2026-09-03"
    let label: String       // "Today" / "Yesterday" / absolute regional date
    let entries: [TimeEntry]
    let total: String        // natural-language sum, e.g. "2h 35m"
}

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var dayGroups: [DayGroup]
    @Published var isLoading: Bool
}
```

- Day labels: "Today" / "Yesterday" (localized via `L10n`) for the two most recent calendar days; device-locale `DateFormatter` for older days (regional standard, no custom format strings).
- Duration format: natural language — `33s`, `1m 20s`, `1h 12m`, `1d 12h` (pure function, unit-tested).
- Day total: sum of `durationSeconds` across the day's entries; entries with no duration (in-progress) contribute zero.

### Implementation checklist

- [ ] All strings use `L10n.*` keys (EN + RU).
- [ ] List has `accessibilityIdentifier("HistoryList")`.
- [ ] Rows use `EntryRow` with `EntryRow(<id>)` identifiers (per `COMPONENTS.md`).
- [ ] Day-group headers use `SectionHeader` with column alignment; the total renders only when elevated.
- [ ] Empty state preserved (`historyEmptyTitle` / `historyEmptySubtitle`).
- [ ] Compact timer `safeAreaInset` preserved.
- [ ] Nav bar visible at every scroll position (no collapse).
- [ ] Preview exists (entries + empty).

---

## New localization keys

Add to `en.lproj/Localizable.strings` and `ru.lproj/Localizable.strings`, then to `L10n`:

```text
// History day-group labels
"history.day.today" = "Today";
"history.day.yesterday" = "Yesterday";

// In-progress indicator
"history.inProgress" = "In progress";

// Day total suffix
"history.tracked" = "tracked";
```

Russian:

```text
// History day-group labels
"history.day.today" = "Сегодня";
"history.day.yesterday" = "Вчера";

// In-progress indicator
"history.inProgress" = "В процессе";

// Day total suffix
"history.tracked" = "отслеживано";
```