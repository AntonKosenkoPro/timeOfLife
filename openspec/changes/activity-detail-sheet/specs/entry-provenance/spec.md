## MODIFIED Requirements

### Requirement: User-visible source labels
The system SHALL display the provenance of an entry to the user as a localized "via <Source>" suffix on entry rows (e.g., "via Screen Time", "via Garmin", "via Widget") wherever entry rows are shown: in the History list and in the activity detail sheet's entry list. Entries with `source='manual'` SHALL display no source label (they are the default). The label SHALL use localized strings.

#### Scenario: Screen Time entry shown with label
- **WHEN** a history entry row has `source='screentime'`
- **THEN** the row shows a localized "via Screen Time" label (EN and RU)

#### Scenario: Manual entry shows no label
- **WHEN** a history entry row has `source='manual'`
- **THEN** no source label is displayed

#### Scenario: Label on detail sheet rows
- **WHEN** the activity detail sheet's entry list shows an entry with a non-manual source
- **THEN** that row shows the same localized "via <Source>" label