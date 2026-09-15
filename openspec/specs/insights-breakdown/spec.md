# Insights Breakdown Specification

## Purpose

This capability answers "where does my time actually go?" — a read-only, period-scoped mirror of committed tracked time through the category lens (with an activity lens beside it), observing without judging: no targets, streaks, comparisons, or coaching.

## Requirements

### Requirement: Period-scoped breakdown with hero total
The Insights destination SHALL present a hero total of committed tracked time for the selected period plus a proportional breakdown of that time, scoped by a period switch (`Today | This week | All time`, default `This week`). Only committed entries (`endedAt != nil`, NULL durations contributing zero) SHALL contribute; the running timer is excluded from all numbers. Entries are bucketed by the calendar day of `startedAt` (device calendar, same day-boundary rule as History); `Today` covers the calendar day containing now (start-of-day to start-of-next-day, so future-dated manual entries count by `startedAt` with no special-casing), `This week` covers the locale week interval containing now, `All time` covers everything.

#### Scenario: Default view
- **WHEN** the user opens Insights with tracked time in the current week
- **THEN** the period switch shows `This week` selected, the hero shows the week's committed total in natural-language duration, and the breakdown lists the week's rows biggest-first

#### Scenario: Switch period
- **WHEN** the user selects a different period
- **THEN** the hero total and all breakdown rows recompute for that period while the selected lens is preserved

#### Scenario: Running timer excluded
- **WHEN** a timer is running and the user opens Insights
- **THEN** the hero and rows reflect committed entries only, and the compact timer remains visible above the tab bar per the app-shell contract

### Requirement: Category and activity lenses with full-credit attribution
The breakdown SHALL offer a lens toggle (`By category | By activity`, default `By category`). The activity lens SHALL attribute each committed entry's full duration to its single activity (rows sum to the hero). The category lens SHALL attribute each committed entry's full duration to **every** currently-attached category of its activity (entries resolve current categories at query time, so recategorization reclassifies history); category rows MAY therefore sum above the hero, which is correct behavior, not an error. Activities with no categories SHALL aggregate into a localized "Without category" row that sorts by its own total like any other row.

#### Scenario: Category lens default
- **WHEN** the user opens Insights
- **THEN** the category lens is selected, showing one row per category with committed time in the period plus the "Without category" row when applicable, ordered biggest-first

#### Scenario: Multi-category entry counts fully toward each
- **WHEN** an entry's activity carries two categories
- **THEN** the entry's full duration contributes to both category rows in the selected period

#### Scenario: Activity lens sums to hero
- **WHEN** the user selects the activity lens
- **THEN** rows show one entry per activity with committed time, and the row durations sum to the hero total

#### Scenario: Recategorization reclassifies history
- **WHEN** the user changes an activity's categories and reopens Insights
- **THEN** existing entries for that activity contribute to the updated category set

### Requirement: Mirror-only presentation
Insights SHALL observe without judging: rows SHALL show icon, name, duration, and a proportional bar scaled to the **max row** (relative presence, never scaled to the hero and never implying summation). The screen SHALL show no percentages, targets, streaks, goals, deltas, comparisons, or red/green judgments. Rows SHALL NOT be tappable — no drill-in, filtering, or export. The category lens SHALL carry a one-line footnote naming the full-credit rule ("An activity with several categories counts fully toward each", localized).

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

### Requirement: Insights is accessible and unsigned
The period switch, lens toggle, hero total, and breakdown rows SHALL be reachable without authentication and SHALL expose stable accessibility labels and identifiers, remaining operable with VoiceOver and Dynamic Type. Row accessibility labels SHALL name the category or activity and its duration.

#### Scenario: VoiceOver reads a row
- **WHEN** VoiceOver focuses a breakdown row
- **THEN** it announces the category or activity name and its localized duration

#### Scenario: Unsigned access
- **WHEN** a user without an account opens Insights
- **THEN** the full breakdown is available with no sign-in prompt
