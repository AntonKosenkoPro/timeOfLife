## MODIFIED Requirements

### Requirement: Period-scoped breakdown with hero total
The Insights destination SHALL present a hero total of committed tracked time for the selected period plus a proportional breakdown of that time, scoped by a period switch (`Today | This week | All time`, default `This week`). Only committed entries (`endedAt != nil`, NULL durations contributing zero) SHALL contribute; the running timer is excluded from all numbers. The hero total and all row durations SHALL render in the device locale's natural language with locale-correct unit abbreviations and plurals (e.g. English `1h 20m`; Russian uses Russian abbreviations). Entries are bucketed by the calendar day of `startedAt` (device calendar, same day-boundary rule as History); `Today` covers the calendar day containing now (start-of-day to start-of-next-day, so future-dated manual entries count by `startedAt` with no special-casing), `This week` covers the locale week interval containing now, `All time` covers everything.

#### Scenario: Default view
- **WHEN** the user opens Insights with tracked time in the current week
- **THEN** the period switch shows `This week` selected, the hero shows the week's committed total in natural-language duration, and the breakdown lists the week's rows biggest-first

#### Scenario: Switch period
- **WHEN** the user selects a different period
- **THEN** the hero total and all breakdown rows recompute for that period while the selected lens is preserved

#### Scenario: Running timer excluded
- **WHEN** a timer is running and the user opens Insights
- **THEN** the hero and rows reflect committed entries only, and the compact timer remains visible above the tab bar per the app-shell contract

#### Scenario: Hero follows the device locale
- **WHEN** the device locale is Russian
- **THEN** the hero total and row durations render with Russian unit abbreviations (not English `h`/`m`/`s`)

### Requirement: Mirror-only presentation
Insights SHALL observe without judging: rows SHALL show icon, name, duration, and a proportional bar scaled to the **max row** (relative presence, never scaled to the hero and never implying summation). Row durations SHALL use the same locale-aware natural language as the hero. The screen SHALL show no percentages, targets, streaks, goals, deltas, comparisons, or red/green judgments. Rows SHALL NOT be tappable — no drill-in, filtering, or export. The category lens SHALL carry a one-line footnote naming the full-credit rule ("An activity with several categories counts fully toward each", localized).

#### Scenario: No summation cues on category lens
- **WHEN** the user views the category lens with multi-category activities
- **THEN** no percentage is shown on any row, bars reflect each row's fraction of the largest row, and the footnote is visible below the list

#### Scenario: Rows do not navigate
- **WHEN** the user taps a breakdown row
- **THEN** nothing happens (no sheet, push, or selection state)
