## MODIFIED Requirements

### Requirement: History shows committed time entries
The History destination SHALL display committed `TimeEntry` records as a chronological list, newest first, grouped by the day each entry started on. The list SHALL NOT show running (uncommitted) timer sessions. An empty or whitespace-only search query SHALL preserve the existing unfiltered History presentation. A valid non-empty query SHALL narrow the displayed entries according to `history-search`, retaining the same grouping and ordering and omitting days without matches. This narrowing applies to list updates from creation, editing, deletion, sync, and undo; a changed entry appears only if it matches the current query.

#### Scenario: History with entries
- **WHEN** the user selects History with a blank query and at least one committed time entry exists
- **THEN** the app shows a list of time entries grouped by day, newest day first, with entries within each day ordered newest first

#### Scenario: History with no entries
- **WHEN** the user selects History with a blank query and no committed time entries exist
- **THEN** the app shows the existing empty state (`historyEmptyTitle` / `historyEmptySubtitle`) and no list

#### Scenario: Running timer is not in History
- **WHEN** a timer is running and the user selects History
- **THEN** the compact timer remains visible but the running session does not appear as a History entry until the timer is stopped and saved

#### Scenario: Search narrows existing day groups
- **WHEN** a valid non-empty query matches committed entries from some days
- **THEN** only those entries appear, once each, in their original start-day groups and newest-first ordering
- **AND** days with no matches have no header

### Requirement: Each History row shows entry identity and timing
Each History row SHALL display the entry's own text (headline — the entry's identity; there is no activity identity), the entry's start–end timeframe and natural-language duration (right-aligned), the entry's own comma-separated category names (left-aligned caption), and the first category's SF Symbol icon (leading, spanning both identity/timing text lines, top-aligned with the name's cap-height top, not the text frame top). The duration SHALL render in the device locale's natural language with locale-correct unit abbreviations and plurals (e.g. English `1h 20m`; Russian uses Russian abbreviations). Rows with no categories SHALL render a `questionmark` fallback icon. Blank-query rows SHALL retain their existing presentation. During a non-empty search, rows SHALL add only the scoped text highlights and conditional notes excerpt defined by `history-search`; any excerpt SHALL sit below the identity/timing content without replacing its fields or adding separate row actions.

#### Scenario: Row with categories
- **WHEN** an entry has one or more categories
- **THEN** the row shows the first category's icon (leading), the entry text (headline), all category names comma-separated (caption, left-aligned), the start–end timeframe (caption, right-aligned), and the duration (headline, right-aligned, top line)

#### Scenario: Row with no categories
- **WHEN** an entry has no categories
- **THEN** the row shows a `questionmark` fallback icon (leading), the entry text (headline), no category names, the start–end timeframe (caption, right-aligned), and the duration (headline, right-aligned, top line)

#### Scenario: Entry with no end time
- **WHEN** an entry has a start time but no end time (duration not yet computed)
- **THEN** the row shows the start time and an in-progress indicator in place of the end time and duration

#### Scenario: Duration follows the device locale
- **WHEN** the device locale is Russian and an entry lasted 1 hour 20 minutes
- **THEN** the row duration renders with Russian unit abbreviations (not `1h 20m`)

#### Scenario: Notes search adds context below the normal row
- **WHEN** notes are in scope and contain a matching text term
- **THEN** the row retains its identity, categories, provenance, timing, duration, and icon and adds the contextual excerpt beneath them
- **AND** tapping either highlighted text or the excerpt performs the existing whole-row action

### Requirement: History rows indicate entries with notes
Each History row SHALL show a small blue notes icon when the entry's notes are non-empty and SHALL show no icon otherwise. Whitespace-only notes count as empty. The icon is purely presentational: it changes no tap, swipe, long-press, or navigation behavior, and the row's VoiceOver label folds in a localized "has notes" affordance when the icon is shown. This indicator SHALL remain present under search even when a matching notes excerpt is shown; it SHALL NOT by itself reveal note contents. A search excerpt SHALL follow `history-search` scope and match rules and its displayed plain text SHALL be included in the existing single-element row label.

#### Scenario: Row with notes shows the icon
- **WHEN** an entry has non-empty notes
- **THEN** its History row shows the small blue notes icon on line 2, immediately left of the timeframe

#### Scenario: Row without notes shows no icon
- **WHEN** an entry has empty notes
- **THEN** its History row renders exactly as today, with no icon and no layout shift beyond the icon's absence

#### Scenario: Whitespace-only notes count as empty
- **WHEN** an entry's notes contain only whitespace or newlines
- **THEN** its History row shows no notes icon

#### Scenario: Icon does not change row interaction
- **WHEN** the user taps a History row that shows the notes icon
- **THEN** the unified entry form opens for that entry, exactly as for rows without the icon

#### Scenario: VoiceOver announces notes presence
- **WHEN** VoiceOver reads a History row whose entry has non-empty notes
- **THEN** the row label includes the localized "has notes" affordance alongside the existing text, duration, categories, and timeframe
- **AND** includes the displayed excerpt only when scoped notes search reveals one, without reading the full hidden note

### Requirement: Day groups use relative-then-absolute labels with static total sublines
Day group headers SHALL use relative labels ("Today", "Yesterday") for the two most recent days and the regional-standard absolute date for older days. Each header SHALL show the day label on its first line and a total as a subheader second line, following the Calendar Agenda week-number pattern. For a blank query the total SHALL be the day's full tracked time ("8h 30m tracked": total formatted in the device locale's natural language with a localized "tracked" suffix). For a valid non-empty query the total SHALL count only matching entries and use a localized "matching" suffix instead. The total subline SHALL be visible in every header position — in-list and pinned alike, with no scroll-state gating. On compact width, the day label SHALL be left-aligned to the `EntryRow` icon column's leading edge (both at `Theme.spacingMedium`); regular width follows when the iPad reflow lands (deferred: iPhone-first scope). Day group headers SHALL render as bare two-line blocks with no background fill or material. Pinned headers do NOT occlude scrolled rows — row text may visibly cross beneath a pinned header on every OS (accepted bleed); the day label and total subline remain readable. Under Reduce Transparency / Increase Contrast nothing changes (there is no material to fall back from; the page background is opaque).

#### Scenario: Today's entries
- **WHEN** entries exist for the current calendar day with a blank query
- **THEN** their day group header reads "Today" (localized) with the day's full tracked time as its subline

#### Scenario: Yesterday's entries
- **WHEN** entries exist for the previous calendar day with a blank query
- **THEN** their day group header reads "Yesterday" (localized) with the day's full tracked time as its subline

#### Scenario: Older entries
- **WHEN** entries exist for a day before yesterday with a blank query
- **THEN** their day group header reads the absolute date formatted using the device's regional settings, with the day's full tracked time as its subline

#### Scenario: In-list headers show the full two lines
- **WHEN** a day group header sits in its in-list scroll position (not pinned at the top)
- **THEN** the header shows the day label on its first line together with the applicable tracked/matching total subline on its second line — in-list and pinned headers render identically

#### Scenario: Day with in-progress entries
- **WHEN** a day group contains an entry with no end time
- **THEN** the total counts only entries with a known `durationSeconds`; in-progress entries contribute zero to the total

#### Scenario: Total follows the device locale
- **WHEN** the device locale is Russian
- **THEN** the day total renders with Russian unit abbreviations followed by the applicable localized "tracked" or "matching" suffix

#### Scenario: Pinned header bleed is accepted
- **WHEN** the user scrolls a day group so its header pins at the top of the list
- **THEN** scrolled row text may remain visible crossing beneath the pinned header, while the day label and total subline stay readable

#### Scenario: Reduce Transparency changes nothing
- **WHEN** Reduce Transparency (or Increase Contrast requiring opacity) is enabled
- **THEN** day group headers render exactly as otherwise (bare text over the opaque page; no material involved)

#### Scenario: Search totals are not full-day totals
- **WHEN** a query matches 30 minutes within a day containing 8 hours of entries
- **THEN** its header shows the original day label and 30 minutes with the localized "matching" suffix
- **AND** clearing the query restores the 8-hour total with the localized "tracked" suffix

### Requirement: History offers manual entry creation
The History destination SHALL offer a `[+]` action in the navigation bar that opens the Log Time sheet (`manual-entry`). The `[+]` action SHALL remain reachable at all scroll positions, alongside the inline "History" title and Profile button. Saving from the sheet SHALL refresh the list and include the new entry in its day group when the query is blank or the entry matches the active valid query. Saving SHALL NOT clear the query or force a non-matching entry into the result list.

#### Scenario: Open the Log Time sheet
- **WHEN** the user activates the `[+]` action in the History navigation bar
- **THEN** the Log Time sheet opens with default times and empty name, categories, and notes

#### Scenario: Action stays reachable
- **WHEN** the user scrolls the History list down and back up
- **THEN** the `[+]` action remains visible alongside the title and Profile button

#### Scenario: Saved entry appears
- **WHEN** the user saves a manual entry from the sheet opened via `[+]` with a blank query
- **THEN** the sheet dismisses and the entry appears in its day group in the list

#### Scenario: Search remains active after saving
- **WHEN** the user saves an entry that does not match the active query
- **THEN** the sheet dismisses and the query remains unchanged without displaying the new entry
- **AND** clearing the query reveals it in normal History
