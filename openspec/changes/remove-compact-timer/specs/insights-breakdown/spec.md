## MODIFIED Requirements

### Requirement: Period-scoped breakdown with hero total
The Insights destination SHALL present a hero total of committed tracked time for the selected period plus a proportional breakdown of that time, scoped by a period switch (`Today | This week | All time`, default `This week`). Only committed entries (`endedAt != nil`, NULL durations contributing zero) SHALL contribute; the running timer is excluded from all numbers. The hero total and all row durations SHALL render in the device locale's natural language with locale-correct unit abbreviations and plurals (e.g. English `1h 20m`; Russian uses Russian abbreviations). Entries are bucketed by the calendar day of `startedAt` (device calendar, same day-boundary rule as History); `Today` covers the calendar day containing now (start-of-day to start-of-next-day, so future-dated manual entries count by `startedAt` with no special-casing), `This week` covers the locale week interval containing now, `All time` covers everything. Removing the compact timer SHALL NOT prevent newly saved timer entries from contributing when Insights is visible again or when an existing external-stop path saves while Insights remains visible.

#### Scenario: Default view
- **WHEN** the user opens Insights with tracked time in the current week
- **THEN** the period switch shows `This week` selected, the hero shows the week's committed total in natural-language duration, and the breakdown lists the week's rows biggest-first

#### Scenario: Switch period
- **WHEN** the user selects a different period
- **THEN** the hero total and all breakdown rows recompute for that period while the selected lens is preserved

#### Scenario: Running timer excluded
- **WHEN** a timer is running and the user opens Insights
- **THEN** the hero and rows reflect committed entries only, and no in-app running-timer surface is shown

#### Scenario: Hero follows the device locale
- **WHEN** the device locale is Russian
- **THEN** the hero total and row durations render with Russian unit abbreviations (not English `h`/`m`/`s`)

#### Scenario: Return after saving on Track
- **WHEN** the user stops and saves a timer on Track and returns to Insights
- **THEN** the saved entry contributes to the applicable selected period's hero total and rows without requiring a manual refresh, while period and lens selection remain unchanged

#### Scenario: Save through an existing external-stop path
- **WHEN** an existing external-stop path saves the running timer while Insights remains visible, or finishes while the app is backgrounded and Insights becomes visible again
- **THEN** the applicable selected period's hero total and rows reflect the committed entry without requiring a tab switch or manual refresh after it becomes visible, while period and lens selection remain unchanged
