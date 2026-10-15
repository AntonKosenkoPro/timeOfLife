# History Screen

Implements the `history-entry-list` capability (`openspec/specs/history-entry-list/spec.md`): a day-grouped list of committed time entries in the History tab. Rows are read-only (`EntryRow` is purely presentational); the screen owns the entry-form push, the Log Time sheet, pull-to-refresh, and shake-to-undo. Deferred items live in `docs/history-roadmap.md`.

The History destination answers "what did I spend time on and when?" — a chronology of timed events (entries), not definitions. Entries are grouped by the calendar day they started on; each entry owns its text, ordered categories, and notes at write time (no resolution, no retroactive mutation).

---

## Screen: HistoryView

- **File**: `ios/TimeOfLife/TimeOfLife/Features/AppShell/Views/HistoryView.swift`
- **Route**: App shell History tab (replaces `DestinationPlaceholder`)
- **ViewModel**: `HistoryViewModel` (`Features/AppShell/ViewModels/HistoryViewModel.swift`)

### Layout

- Body: `HistoryListTable` (`Features/AppShell/Views/HistoryListTable.swift`) — a `UITableView(style: .plain)` `UIViewRepresentable` whose sections map one per calendar day (newest day first), `EntryRow` per row via `UIHostingConfiguration` with zero margins (the row carries its own horizontal `Theme.spacingMedium` padding), `accessibilityIdentifier("HistoryList")` on the table. Chrome is stripped to the page: no separators, transparent cell backgrounds (`UIBackgroundConfiguration.clear()`), clear table background over `Theme.backgroundPrimary`. The bridge (not `List`, not a custom ScrollView): UIKit's pinned header draws **above** cells deterministically on every OS — SwiftUI `List` pinned headers never occlude (scrolled rows composite over them on iOS 18 regardless of header background, proven on-device; see the change's design.md D4/D6). On iOS 26+ the table frame extends under the glass tab bar (bottom edge-to-edge, so scrolled rows blur beneath it) with the measured bottom inset (tab bar + compact timer) keeping the final row reachable; on iOS 18 the table keeps the default safe-area frame with content stopping above the bar (design.md D7 gating).
- Day-group headers: `SectionHeader(title:subtitle:)` in `UIHostingConfiguration` header views — static two-line block (day label + total subline "2h 35m tracked", Calendar-Agenda-like), identical in-list and pinned with no scroll-state gating; day label left-aligned to the `EntryRow` icon column's leading edge. The header hosting content paints an opaque `Theme.backgroundPrimary` full-width band — invisible against the page at rest, the deterministic occluder when pinned (no `.bar` material, no hairline: the user rejected the boxed slab look). Cell data lives in `HistorySectionModel` (diff-applied by the table; identical models skip `reloadData`).
- Row dividers lead after the icon column (Variant H).
- Inline navigation title: "History" (`L10n.tabHistory`), shown at rest.
- Navigation bar (inline title + Profile button) permanently visible at every scroll position (the scroll-driven collapse from the original change was reverted — see the `revert-history-nav-collapse` change). Profile is reachable at all times on History.
- Empty state: when no committed entries exist show `EmptyState(icon: "clock.arrow.circlepath", title: L10n.historyEmptyTitle, subtitle: L10n.historyEmptySubtitle)` — the pre-existing shell empty state is preserved.
- Compact cross-tab running timer stays visible via `.safeAreaInset(edge: .bottom)` (app-shell "Running timer remains globally accessible"); the running session does NOT appear as a History entry until stopped and saved.

### Behaviors

- On appear, load entries (`LocalStore.entries()`) and categories (`LocalStore.categories()`); rebuild day groups. Rows are read-only — the screen's mutation paths are the entry-form push (EDIT/LOCKED), the Log Time sheet (`[+]` in the toolbar, CREATE mode), pull-to-refresh sync (`HistoryPullModel` verdict flow with the inline offline notice and OK-only failure dialog), and shake-to-undo (`ShakeFirstResponderHost`).
- Entry rows show the localized "via <Source>" provenance label on line 2 for non-`manual` sources (`EntryRow.viaText`); `manual` shows nothing.
- Entry rows with non-empty notes show the small blue notes indicator on line 2, immediately left of the timeframe (`EntryRow.hasNotes`, resolved by `HistoryViewModel.hasNotes(for:)` — whitespace-only counts as empty); the glyph is presentational and VoiceOver folds the localized `historyHasNotes` segment into the row label.
- Tapping a row pushes the unified entry form onto the History navigation stack (EDIT for `manual`, LOCKED read-only for imported with delete only) — the push provides the system back button and edge-back gesture; there is no intermediate detail surface.

### States

| State | Visual |
|---|---|
| Loading | Progress indicator while the local store is read |
| Empty | `EmptyState` (`clock.arrow.circlepath`, `historyEmptyTitle` / `historyEmptySubtitle`) |
| Loaded | Day-grouped `HistoryListTable` of `EntryRow` |
| Day-group header | Static two-line header (day label + total subline) on an opaque page-color band, identical in-list and pinned |

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
- [ ] Rows with non-empty notes show the line-2 notes indicator left of the timeframe; empty/whitespace-only notes show none.
- [ ] Day-group headers use two-line `SectionHeader(title:subtitle:)` inside `HistoryListTable` header hosting (opaque page-color band, no `.bar`); label + subline never overlap at accessibility sizes.
- [ ] Empty state preserved (`historyEmptyTitle` / `historyEmptySubtitle`).
- [ ] Compact timer `safeAreaInset` preserved.
- [ ] List content passes under the glass tab bar with no hard cut; final row reachable above the compact timer whether it is shown or hidden.
- [ ] iOS 18 keeps the default tab bar (no content beneath it); iOS 26+ blurs rows beneath the glass bar.
- [ ] Nav bar visible at every scroll position (no collapse).
- [ ] Preview exists (entries + empty).

---

## New localization keys

Add to `en.lproj/Localizable.strings` and `ru.lproj/Localizable.strings`, then to `L10n`:

```text
// History day-group labels
"history.day.today" = "Today";
"history.day.yesterday" = "Yesterday";

// Day total suffix
"history.tracked" = "tracked";

// Notes indicator
"history.hasNotes" = "has notes";
```

Russian:

```text
// History day-group labels
"history.day.today" = "Сегодня";
"history.day.yesterday" = "Вчера";

// Day total suffix
"history.tracked" = "отслеживано";

// Notes indicator
"history.hasNotes" = "есть заметки";
```