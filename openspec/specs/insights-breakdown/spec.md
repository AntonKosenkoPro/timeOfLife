# Insights Breakdown Specification

## Purpose

This capability answers "where does my time actually go?" — a read-only, period-scoped mirror of committed tracked time through the category lens (with an activity lens beside it), observing without judging: no targets, streaks, comparisons, or coaching.

## Requirements


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

### Requirement: Category and text lenses with full-credit attribution
The breakdown SHALL offer a lens toggle (`By category | By text`, default `By category`). The text lens SHALL group committed entries by trimmed exact text (`Gym` and `GYM` are distinct rows) and attribute each entry's full duration to its text row (rows sum to the hero). The category lens SHALL attribute each committed entry's full duration to **every** category stored on that entry; category rows MAY therefore sum above the hero, which is correct behavior, not an error. Entries with no categories SHALL aggregate into a localized "Without category" row that sorts by its own total like any other row. No edit on one entry SHALL reclassify any other entry. There is no activity entity — the former "activity lens" name is retired; the lens is the text lens.

#### Scenario: Category lens default
- **WHEN** the user opens Insights
- **THEN** the category lens is selected, showing one row per category with committed time in the period plus the "Without category" row when applicable, ordered biggest-first

#### Scenario: Multi-category entry counts fully toward each
- **WHEN** an entry carries two categories
- **THEN** the entry's full duration contributes to both category rows in the selected period

#### Scenario: Text lens sums to hero
- **WHEN** the user selects the text lens
- **THEN** rows show one row per exact text with committed time, and the row durations sum to the hero total

#### Scenario: Recategorization reclassifies history
- **WHEN** the user changes one entry's categories and reopens Insights (retags are per-entry; no other entry reclassifies)
- **THEN** only that entry contributes to the updated category set; same-text entries are unchanged

### Requirement: Mirror-only presentation
Insights SHALL observe without judging: rows SHALL show icon, name, duration, and a proportional bar scaled to the **max row** (relative presence, never scaled to the hero and never implying summation). Row durations SHALL use the same locale-aware natural language as the hero. The screen SHALL show no percentages, targets, streaks, goals, deltas, comparisons, or red/green judgments. Rows SHALL NOT be tappable — no drill-in, filtering, or export. The category lens SHALL carry a one-line footnote naming the full-credit rule ("An activity with several categories counts fully toward each", localized).

#### Scenario: No summation cues on category lens
- **WHEN** the user views the category lens with multi-category activities
- **THEN** no percentage is shown on any row, bars reflect each row's fraction of the largest row, and the footnote is visible below the list

#### Scenario: Rows do not navigate
- **WHEN** the user taps a breakdown row
- **THEN** nothing happens (no sheet, push, or selection state)

### Requirement: Honest per-period empty states
Insights SHALL keep the existing true-zero empty state ("Nothing here yet" / "Patterns emerge…") only when `All time` has no committed entries. A `Today` or `This week` period with no committed entries SHALL show a one-line period-specific empty sentence naming that period instead of bars or skeleton content.

#### Scenario: True zero
- **WHEN** the user opens Insights with no committed entries at all
- **THEN** the existing empty title and subtitle are shown

#### Scenario: Empty today with a non-empty week
- **WHEN** the user selects `Today` with no committed entries started today while the week has entries
- **THEN** a "Nothing tracked today yet" sentence is shown (localized), with no bars and no hero total of zero competing with it

### Requirement: Insights is signed-in-only and accessible
The period switch, lens toggle, hero total, and breakdown rows SHALL be reachable by the signed-in account behind the launch auth gate and SHALL expose stable accessibility labels and identifiers, remaining operable with VoiceOver and Dynamic Type. Row accessibility labels SHALL name the category or activity and its duration.

#### Scenario: VoiceOver reads a row
- **WHEN** VoiceOver focuses a breakdown row
- **THEN** it announces the category or activity name and its localized duration

#### Scenario: Signed-out user meets the auth gate
- **WHEN** a user without an account reaches Insights
- **THEN** the launch auth gate precedes it: the breakdown is available only after sign-in

### Requirement: Insights reflects synced changes without re-entry
The Insights destination SHALL recompute its breakdown when a sync cycle completes while Insights is visible, including a manual Sync now triggered from the Profile sheet opened over Insights. Pulled entries, category changes, and tombstone deletions SHALL appear in the hero total and rows without requiring the user to leave and re-enter the tab.

#### Scenario: Sync now from Profile over Insights
- **WHEN** the user opens Profile from the Insights tab, taps Sync now, the cycle pulls cross-device changes, and dismisses Profile
- **THEN** the hero total and breakdown rows reflect the pulled state without any tab switch

#### Scenario: Automatic sync while Insights is visible
- **WHEN** a foreground or connectivity-restored sync cycle merges relay changes while Insights is on screen
- **THEN** the breakdown reloads to reflect the merged state once the cycle completes
