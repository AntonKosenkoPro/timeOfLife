# History Screen

Implements the `history-entry-list` capability (`openspec/specs/history-entry-list/spec.md`): a day-grouped list of committed time entries in the History tab. Rows are read-only (`EntryRow` is purely presentational); the screen owns the entry-form push, the Log Time sheet, pull-to-refresh, and shake-to-undo. Deferred items live in `docs/history-roadmap.md`.

The History destination answers "what did I spend time on and when?" — a chronology of timed events (entries), not definitions. Entries are grouped by the calendar day they started on; each entry owns its text, ordered categories, and notes at write time (no resolution, no retroactive mutation).

---

## Screen: HistoryView

- **File**: `ios/TimeOfLife/TimeOfLife/Features/AppShell/Views/HistoryView.swift`
- **Route**: App shell History tab (replaces `DestinationPlaceholder`)
- **ViewModel**: `HistoryViewModel` (`Features/AppShell/ViewModels/HistoryViewModel.swift`)

### Layout

- Body: `List(.plain)` of day-group sections (newest day first) with `EntryRow` rows (zeroed horizontal insets, hidden separators, clear row backgrounds, hidden scroll content background, `listSectionSpacing(Theme.spacingExtraSmall)` between day groups, `defaultMinListHeaderHeight` 0 above headers, `accessibilityIdentifier("HistoryList")`). Headers are bare two-line `SectionHeader(title:subtitle:)` blocks (day label + total subline "2h 35m tracked", Calendar-Agenda-like, zero top padding) with no background fill — pinned bleed (row text crossing beneath pinned headers) is accepted on every OS (design.md D8). The tab bar is opaque on iOS 18 and glass on iOS 26+ (bar-visibility gating).
- Day-group headers: `SectionHeader(title:subtitle:)` in `UIHostingConfiguration` header views — static two-line block (day label + total subline "2h 35m tracked", Calendar-Agenda-like), identical in-list and pinned with no scroll-state gating; day label left-aligned to the `EntryRow` icon column's leading edge. History headers carry zero top padding (tight dock under the nav bar; editors keep `spacingSmall` vertical). The header hosting content paints an opaque `Theme.backgroundPrimary` full-width band — invisible against the page at rest, the deterministic occluder when pinned (no `.bar` material, no hairline: the user rejected the boxed slab look). Cell data lives in `HistorySectionModel` (diff-applied by the table; identical models skip `reloadData`).
- Row dividers lead after the icon column (Variant H).
- Inline navigation title: "History" (`L10n.tabHistory`), shown at rest.
- Navigation bar (inline title + Profile button) permanently visible at every scroll position (the scroll-driven collapse from the original change was reverted — see the `revert-history-nav-collapse` change). Profile is reachable at all times on History.
- Empty state: when no committed entries exist show `EmptyState(icon: "clock.arrow.circlepath", title: L10n.historyEmptyTitle, subtitle: L10n.historyEmptySubtitle)` — the pre-existing shell empty state is preserved.
- History shows committed entries only: the running session does NOT appear as a History entry until stopped and saved, and no in-app running-timer surface is shown. Newly saved entries appear through the existing reload flows (tab re-entry, external-stop and foreground events, sync-cycle exit).

### Behaviors

- On appear, load entries (`LocalStore.entries()`) and categories (`LocalStore.categories()`); rebuild day groups. Rows are read-only — the screen's mutation paths are the entry-form push (EDIT/LOCKED), the Log Time sheet (`[+]` in the toolbar, CREATE mode), pull-to-refresh sync (`HistoryPullModel` verdict flow with the inline offline notice and OK-only failure dialog), and shake-to-undo (`ShakeFirstResponderHost`).
- Entry rows show the localized "via <Source>" provenance label on line 2 for non-`manual` sources (`EntryRow.viaText`); `manual` shows nothing.
- Entry rows with non-empty notes show the small blue notes indicator on line 2, immediately left of the timeframe (`EntryRow.hasNotes`, resolved by `HistoryViewModel.hasNotes(for:)` — whitespace-only counts as empty); the glyph is presentational and VoiceOver folds the localized `historyHasNotes` segment into the row label.
- Tapping a row pushes the unified entry form onto the History navigation stack (EDIT for `manual`, LOCKED read-only for imported with delete only) — the push provides the system back button and edge-back gesture; there is no intermediate detail surface.

### Search

Implements the `history-search` capability (`add-history-search` change): one always-visible inline native `.searchable` field on the History root (navigation-bar drawer with `displayMode: .automatic`, pinned with the list, hiding on scroll-down and returning on scroll-up; name-and-category-default prompt, no autocapitalization/correction; no autocomplete, suggestions, token chips, scope bar, filter panel, activation button, or modes, and never on pushed destinations). There is no structural layout change when typing or clearing: a blank query (even a focused empty field) keeps the bottom tab bar, while any non-blank query (results, no-matches, or syntax diagnostics) hides it with an animated transition, giving results the full content height. Typing filters the account's committed entries locally, offline, with no submission and no network request.

- **Blank query** (empty/whitespace-only) renders exactly the unfiltered History above: same groups, full-day "tracked" totals, unchanged rows, existing empty state. No highlights or excerpts.
- **Grammar** (manual entry only): plain text defaults to entry names and category names (`gym` ≡ `gym in:name,categories`); `in:name,categories,notes` (comma/repeated unions replacing the default globally); uppercase `AND`/`OR` combine groups (`AND` binds tighter, no parentheses; lowercase/quoted forms stay text); `has:notes`/`has:category` with `-has:` negation only; double-quoted phrases with `\"`/`\\` escapes; `started:`/`ended:` bare/comparison/inclusive-range/open-range constraints over dates, absolute timestamps, and wall-clock times. Date-only operands are device-local calendar days (`S(d)`/`N(d)`); full-second `Z`/explicit-offset timestamps are absolute instants; `HH:MM`/`HH:MM:SS` operands filter device-local clock time on any date (bare `HH:MM` covers its minute, bare `HH:MM:SS` its second, earlier-ending ranges wrap midnight); `ended:` reuses all operand rules against the entry end (entries without an end match nothing). `duration:` takes bare/comparison/inclusive-range/open-range constraints over contiguous `d`/`h`/`m`/`s` lengths in descending order without repeats (bare means exact-second equality; no wrap — a smaller end is a reversed diagnostic); it resolves the stored seconds else the start-to-end interval, matches nothing when unresolvable, binds to its group, and adds no highlights or excerpts. Qualifiers are contiguous unquoted tokens; `in:` stays global while `started:`/`ended:`/`duration:`/`has:` bind to their group; quoted qualifier values, spaced operators, unknown qualifiers/scopes, empty values, bad dates/times/durations, mixed-kind ranges, reversed ranges (including smaller-end duration ranges), misplaced `AND`/`OR`, parentheses, unsupported negations, and `*..*` are correctable diagnostics.
- **Results**: matching entries once each in their start-day groups, newest-first; empty days omitted; a scrolling summary above the first group states the match count (localized plurals) and the combined known-duration total (same formatting as day totals; blank/invalid/zero-match queries show none); group totals count only matches with the localized "matching" suffix. Only in-scope positive text matches highlight (accent wash + bold, original-string ranges); a `Notes:` excerpt (bounded, whitespace-collapsed, `…` only at omitted ends) appears only when notes are in scope and hit, carrying the distinct notes treatment (notes glyph + italic excerpt text, Theme-only) so it never reads as a category match. Rows stay a single accessibility element; the label reads the displayed excerpt as notes content, never the full note.
- **States**: syntax diagnostic + static example (invalid), no-results + Clear search (valid, zero matches), existing empty state (blank, no entries). Populated results keep sync-only pull; invalid/no-match states add none. The query survives same-account reloads/navigation/tab switches and re-evaluates on edits, renames, sync, undo, foreground, and timezone changes; it resets on account change/launch and is never persisted, logged, or sent anywhere.

### States

| State | Visual |
|---|---|
| Loading | Progress indicator while the local store is read |
| Empty | `EmptyState` (`clock.arrow.circlepath`, `historyEmptyTitle` / `historyEmptySubtitle`) |
| Loaded | Day-grouped `HistoryListTable` of `EntryRow` |
| Searching (invalid) | Syntax diagnostic + static example, no rows, field stays usable |
| Searching (no matches) | No-results state + Clear search action, distinct from Empty |
| Searching (results) | Scrolling summary (pluralized count + known-duration total), same groups newest-first, "matching" totals, scoped highlights + conditional `Notes:` excerpts with the distinct notes treatment |
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
- [ ] No in-app running-timer surface is rendered; no timer-only space is reserved.
- [ ] List content passes under the glass tab bar with no hard cut; final row reachable above the tab bar with no timer chrome.
- [ ] iOS 18 keeps the default tab bar (no content beneath it); iOS 26+ blurs rows beneath the glass bar.
- [ ] Nav bar visible at every scroll position (no collapse).
- [ ] Search field renders inline on the History root only (drawer, always visible, hides on scroll); never on pushed entry/Profile views; no suggestions, chips, scope bar, or filter panel.
- [ ] The tab bar stays visible for a blank query (focusing the empty field changes nothing) and hides with an animated transition for any non-blank query — first keystroke hides, clearing restores; last row stays reachable with compact-timer clearance with and without a running timer.
- [ ] No-results Clear search keeps compact-timer-equivalent bottom keyboard clearance with and without a running timer.
- [ ] Blank/whitespace-only query is pixel-identical to unfiltered History (groups, "tracked" totals, rows, empty state); no highlights or excerpts.
- [ ] Valid non-empty queries show a scrolling summary (pluralized count + known-duration total; none for blank/invalid/zero matches), "matching" totals, one row per match, scoped highlights, and `Notes:` excerpts only for in-scope notes hits with the distinct notes treatment (glyph + italic); invalid queries show the diagnostic, no-results shows Clear search.
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

### Search keys (history-search, all five locales)

```text
"history.matching" = "найдено";
"history.search.prompt" = "Поиск записей по названию и категории";
"history.search.noResults" = "Совпадений нет";
"history.search.noResults.subtitle" = "Попробуйте другие слова или даты.";
"history.search.clear" = "Очистить поиск";
"history.search.hint" = "Пример: morning gym in:name,notes started:2026-10-01..2026-10-31 OR swim has:notes";
"history.search.notesLabel" = "Заметки:";
"history.search.error.unknown" = "Неизвестный квалификатор «%@». Используйте in:, started:, ended:, duration: или has:.";
"history.search.error.scope" = "Неизвестное поле «%@». Используйте name, categories или notes.";
"history.search.error.empty" = "После «%@» нет значения.";
"history.search.error.quote" = "Незакрытая кавычка. Закройте каждую \" и используйте \\\" или \\\\ внутри фраз.";
"history.search.error.date" = "Проверьте дату после «%@». Формат: YYYY-MM-DD, YYYY-MM-DDTHH:MM:SSZ или HH:MM.";
"history.search.error.range" = "Проверьте диапазон «%@». Формат: A..B, A..* или *..B, сначала ранняя граница.";
"history.search.error.operator" = "Проверьте «%@». Используйте AND/OR между группами; скобки и квалификаторы с отрицанием (кроме -has:notes и -has:category) не поддерживаются.";
"history.search.error.has" = "Проверьте has:«%@». Используйте has:notes или has:category (отрицание — -has:).";
"history.search.error.time" = "Проверьте время в «%@». Формат: HH:MM или HH:MM:SS (00:00–23:59).";
"history.search.error.duration" = "Проверьте длительность в «%@». Единицы d/h/m/s, например 1h, 90m, 2d5h (от большей к меньшей).";
```

Qualifier keys/fields stay lowercase English in every locale; only the surrounding copy is translated. `en` values: `matching`, `Search entries by name and category`, `No matching entries`, `Try different words or dates.`, `Clear search`, the same `Example: …` hint, `Notes:`, and the ten `history.search.error.*` diagnostics.

The result-summary copy (`history.search.summary`) lives in `Localizable.stringsdict` in each locale — not in the strings table above — with per-locale plural variants (`en`: one/other; `ru`: one/few/many/other; `zh-Hans`: other; `es-419`/`pt-BR`: one/other): `%#@entries@ · %@`, pairing the pluralized match count with the known-duration total.