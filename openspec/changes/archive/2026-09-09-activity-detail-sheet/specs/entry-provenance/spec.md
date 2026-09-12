## MODIFIED Requirements

### Requirement: User-visible source labels
The system SHALL display the provenance of an entry to the user in two forms. In the History list, non-`manual` entries SHALL show a localized "via <Source>" suffix on the entry row (e.g., "via Screen Time", "via Garmin", "via Widget"). In the activity detail sheet's entry list, non-`manual` entries SHALL show the shared sync icon plus the localized source name (e.g. "Garmin"), without the "via" prefix. Entries with `source='manual'` SHALL display no source label in either surface (they are the default). All labels SHALL use localized strings.

#### Scenario: Screen Time entry shown with label
- **WHEN** a history entry row has `source='screentime'`
- **THEN** the row shows a localized "via Screen Time" label (EN and RU)

#### Scenario: Manual entry shows no label
- **WHEN** a history entry row has `source='manual'`
- **THEN** no source label is displayed

#### Scenario: Label on detail sheet rows
- **WHEN** the activity detail sheet's entry list shows an entry with a non-manual source
- **THEN** that row shows the shared sync icon plus the localized source name (e.g. "Garmin")